import ast
import base64
import urllib
import json

from flask_sqlalchemy import SQLAlchemy
import requests
from flask import request, jsonify, Flask
from flask_cors import CORS
from google import genai
import re



app = Flask(__name__)
CORS(app)

app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///mydatabase.db"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

client_id = "ed7a342821fb4142af5a9feae25d3395"
client_secret = "5f5df8bdf93d458f89ca1e17da6131af"
credentials = f"{client_id}:{client_secret}"
encoded_credentials = base64.b64encode(credentials.encode()).decode()

authOptions = {
    "url": 'https://accounts.spotify.com/api/token',
    "headers": {
        "Authorization": f"Basic {encoded_credentials}",
        "Content-Type": "application/x-www-form-urlencoded"
    },
    "form": {
        "grant_type": 'client_credentials'
    }
}
response = requests.post(authOptions["url"], headers=authOptions["headers"], data=authOptions["form"])

access_token = response.json()["access_token"]

from db import create_song, create_gemini_json, db, reset_schema

db.init_app(app)
with app.app_context():
    reset_schema()  # drop_all + create_all defined in db.py


def getSpotifyIDs(SpotifyJSON):
    SpotifyIDs = []
    for track in SpotifyJSON["tracks"]["items"]:
        SpotifyIDs.append(track["track"]["id"])
    return SpotifyIDs

from collections import defaultdict

# extract a 22-char spotify track id from plain id / URI / URL
_SPOTIFY_ID_RE = re.compile(r'([0-9A-Za-z]{22})')

def _normalize_spotify_id(value):
    if not value or not isinstance(value, str):
        return None
    m = _SPOTIFY_ID_RE.search(value)
    return m.group(1) if m else None

def _chunks(lst, n):
    for i in range(0, len(lst), n):
        yield lst[i:i+n]

def getReccoSongProperties(SpotifyIDs):
    """
    Returns a list aligned with SpotifyIDs:
      [ {"spotify_id": <input_id>, "song_features": dict|None}, ... ]
    Uses Recco /v1/track?ids=<spotify_ids> then fetches audio-features with Recco's INTERNAL id,
    and writes features back to positions matching the ORIGINAL SpotifyIDs. Missing ones -> None.
    """
    recHeaders = {'Accept': 'application/json'}

    # Pre-fill to preserve index alignment
    results = [{"spotify_id": sid, "song_features": None} for sid in SpotifyIDs]

    # Handle duplicates: map normalized spotify id -> all indices in input
    id_to_indices = defaultdict(list)
    for idx, sid in enumerate(SpotifyIDs):
        norm = _normalize_spotify_id(sid)
        if norm:
            id_to_indices[norm].append(idx)

    for batch in _chunks(SpotifyIDs, 40):
        # de-dup within batch while keeping order
        seen = set()
        unique_norm_ids = []
        for sid in batch:
            norm = _normalize_spotify_id(sid)
            if norm and norm not in seen:
                seen.add(norm)
                unique_norm_ids.append(norm)

        if not unique_norm_ids:
            continue

        ids_param = ",".join(unique_norm_ids)

        # 1) get Recco tracks for these Spotify IDs
        try:
            tracks_resp = requests.get(
                f"https://api.reccobeats.com/v1/track?ids={ids_param}",
                headers=recHeaders, timeout=15
            )
            tracks_resp.raise_for_status()
            content = tracks_resp.json().get("content", [])
        except requests.RequestException:
            # batch failed => leave all as None
            continue

        # 2) for each returned track, find BOTH: recco_internal_id and spotify_id
        for t in content:
            # Recco internal id (used to call audio-features):
            recco_internal_id = t.get("id")  # this is Recco's internal id

            # Try to recover the spotify id from common fields
            # Adjust these keys if your payload uses different names.
            spotify_id_raw = (
                t.get("spotify_id")
                or t.get("spotifyId")
                or t.get("spotify")              # could be a dict or string
                or t.get("uri")                  # e.g. spotify:track:xxxx
                or t.get("href")                 # sometimes a URL
                or t.get("external_id")
                or t.get("externalId")
                or ""
            )

            # If "spotify" is a dict like {"id": "..."} handle that:
            if isinstance(spotify_id_raw, dict):
                spotify_id_raw = (
                    spotify_id_raw.get("id")
                    or spotify_id_raw.get("spotify_id")
                    or spotify_id_raw.get("uri")
                    or ""
                )

            norm_spotify_id = _normalize_spotify_id(spotify_id_raw)
            if not norm_spotify_id:
                # as a fallback, sometimes Recco echoes 'original_id' etc.
                norm_spotify_id = _normalize_spotify_id(t.get("original_id", ""))

            if not recco_internal_id or not norm_spotify_id:
                # can't map or can't fetch features; skip
                continue

            # 3) fetch audio-features using Recco's INTERNAL id
            features = None
            try:
                feat = requests.get(
                    f"https://api.reccobeats.com/v1/track/{recco_internal_id}/audio-features",
                    headers=recHeaders, timeout=15
                )
                feat.raise_for_status()
                features = feat.json() or None
                if isinstance(features, dict):
                    features.pop("id", None)
                    features.pop("href", None)
            except requests.RequestException:
                features = None  # leave None on failure

            # 4) write features back to ALL indices where this spotify id appears
            for idx in id_to_indices.get(norm_spotify_id, []):
                results[idx]["song_features"] = features

        # any IDs from this batch that Recco didn't return remain None (pre-filled)
    return results



def geminiCall(prompt: str):
    client = genai.Client(api_key="AIzaSyBRFtS9ieNV0i4QvhqeX9afbc9oKOUJlWo")
    model_name = "gemini-2.5-flash"
    return client.models.generate_content(
        model=model_name,
        contents=prompt
    ).text


def get_spotify_id(title: str, artist: str):
    # Build query: e.g. 'track:Shape of You artist:Ed Sheeran'
    query = f"track:{title} artist:{artist}"
    encoded_query = urllib.parse.quote(query)

    url = f"https://api.spotify.com/v1/search?q={encoded_query}&type=track&limit=1"

    headers = {
        "Authorization": f"Bearer {access_token}"
    }

    response = requests.get(url, headers=headers)
    response.raise_for_status()

    data = response.json()
    items = data.get("tracks", {}).get("items", [])
    if not items:
        return None  # no track found

    # First match
    track = items[0]
    spotify_id = track["id"]
    name = track["name"]
    artists = ", ".join(a["name"] for a in track["artists"])
    return spotify_id


def get_album_art(spotify_id: str, size: int = 640):
    """
    Returns the album art URL for a Spotify track ID.
    size can be 640, 300, or 64 (the sizes Spotify gives).
    """
    try:
        url = f"https://api.spotify.com/v1/tracks/{spotify_id}"
        headers = {"Authorization": f"Bearer {access_token}"}

        resp = requests.get(url, headers=headers, timeout=10)
        resp.raise_for_status()
        track = resp.json()

        images = track["album"]["images"]
        if not images:
            return "https://via.placeholder.com/300x300/1DB954/FFFFFF?text=Music"
        
        # Find image with requested size or just return the largest
        for img in images:
            if img["height"] == size:
                return img["url"]
        # If requested size not found, return the first image
        return images[0]["url"]
    except Exception as e:
        return "https://via.placeholder.com/300x300/1DB954/FFFFFF?text=Music"


def parse_markdown_json(raw: str):
    """
    Parse a JSON string that may be wrapped in Markdown ```json fences.
    Returns a Python object (list, dict, etc.).
    """
    text = raw.strip()

    # strip leading ```json or ```JSON
    if text.lower().startswith("```json"):
        text = text[7:].strip()  # remove '```json'
    elif text.startswith("```"):
        text = text[3:].strip()  # remove plain '```'

    # strip trailing ```
    if text.endswith("```"):
        text = text[:-3].strip()

    return json.loads(text)

from db import store_gemini_recommendations, get_recommendations
def getRecommendations(spotify_ids: list, names: list, artists: list):
    reccoSongDetails = getReccoSongProperties(spotify_ids)

    for i in range(len(reccoSongDetails)):
        create_song(spotify_ids[i], names[i], artists[i], reccoSongDetails[i]["song_features"])

    geminiJSON = create_gemini_json()
    prompt = f"""SYSTEM:
You are a music recommendation assistant. Output ONLY a JSON list (array) of EXACTLY 10 objects.
Each object MUST have exactly these keys with these types:
"name": string (track title)
"artist": array of strings (list of artist names; use a list even if there is only one artist)
No other text, no markdown, no extra keys.

INSTRUCTIONS:
Input is an array of seed songs with audio features and artist names.
Recommend 10 DISTINCT tracks that are similar to the overall seed profile.
You MUST infer likely genres of the seeds from your knowledge of the tracks/artists and use those inferred genres when selecting recommendations.
Do NOT return any seed tracks or those specifically disallowed. In other words DO NOT recommend any songs that are already mentioned in the following JSONS or that you have already mentioned.
Diversity: cap at 2 tracks involving the same artist name (across any position in the artist list).

OPTIMIZATION (in order):
1) Match audio profile: keep tempo within ±8% of the median seed tempo; prefer similar danceability, energy, and valence; respect mode and time_signature when helpful.
2) Incorporate inferred genres: align with the top inferred genres; include a mix across those genres.
3) Reflect the categories below (moods/use-cases/constraints) across the set.

SEEDS_JSON:
{geminiJSON}

DISALLOWED_JSON:
{get_recommendations()}

OUTPUT SHAPE EXAMPLE (structure only):
[
  {{"name": "Track Title 1", "artist": ["Primary Artist 1"]}},
  {{"name": "Track Title 2", "artist": ["Artist A", "Artist B"]}},
  ...
]
Return ONLY the JSON array (10 items)."""

    print(prompt)
    recommendationIDs = parse_markdown_json(geminiCall(prompt))

    # Process recommendations and add Spotify data
    processed_recommendations = []
    for recommendation in recommendationIDs:
        spotifyID = get_spotify_id(recommendation["name"], ",".join(recommendation["artist"]))
        if spotifyID is not None:
            image_url = get_album_art(spotifyID)
            processed_recommendation = {
                "name": recommendation["name"],
                "artist": recommendation["artist"],
                "spotify_id": spotifyID,
                "image_url": image_url
            }
            processed_recommendations.append(processed_recommendation)
        else:
            pass
    
    # Update the original list
    recommendationIDs = processed_recommendations

    store_gemini_recommendations(recommendationIDs)
    return recommendationIDs


def getSpotifyTrackInfo(SpotifyIDs):
    """
    Given a list of Spotify track IDs, fetches the track metadata
    (artist names and song names).

    Returns a dict with parallel lists:
    {
      "artists": [ [list of artist names], ... ],
      "names":   [ song name, ... ]
    }
    Order is preserved and matches the input list.
    If a track ID is invalid or missing, None is placed in its slot.
    """
    headers = {"Authorization": f"Bearer {access_token}"}

    # Pre-fill results with None to preserve index alignment
    artists = [None] * len(SpotifyIDs)
    names = [None] * len(SpotifyIDs)

    # Spotify's track endpoint allows up to 50 IDs at once
    def chunks(lst, n):
        for i in range(0, len(lst), n):
            yield lst[i:i+n], i  # return batch and starting index

    for batch, start_idx in chunks(SpotifyIDs, 50):
        ids_param = ",".join(batch)
        url = f"https://api.spotify.com/v1/tracks?ids={ids_param}"

        try:
            resp = requests.get(url, headers=headers, timeout=15)
            resp.raise_for_status()
            items = resp.json().get("tracks", [])
        except requests.RequestException:
            # Leave this batch as None if it fails
            continue

        # Fill results for each ID in the batch
        for offset, track in enumerate(items):
            idx = start_idx + offset
            if track is None:
                continue
            # Extract artist names and song title
            artist_names = [a["name"] for a in track["artists"]]
            song_name = track["name"]
            artists[idx] = artist_names
            names[idx] = song_name

    return {"artists": artists, "names": names}


@app.route("/link/<playlist_id>", methods=['GET'])
def playlistRecs(playlist_id: str):
    # 54ZA9LXFvvFujmOVWXpHga
    url = f"https://api.spotify.com/v1/playlists/{playlist_id}"
    headers = {
        "Authorization": f"Bearer {access_token}"
    }
    response = requests.get(url, headers=headers)
    response.raise_for_status()


    artists = []
    names = []
    for i in range(len(response.json()["tracks"]["items"])):
        track = response.json()["tracks"]["items"][i]["track"]
        artists.append([artist["name"] for artist in track["artists"]])
        names.append(track["name"])

    return getRecommendations(getSpotifyIDs(response.json()), names, artists), 200

@app.route("/songids" , methods=['POST'])
def moreRecs():
    spotifyIDs = request.get_json()
    info = getSpotifyTrackInfo(spotifyIDs)
    return getRecommendations(spotifyIDs, info["names"], info["artists"]), 200

@app.route("/clear", methods=['POST'])
def clear_database():
    from db import clear_all_data
    clear_all_data()
    return {"message": "Database cleared successfully"}, 200

