import ast
import base64
import urllib
import json

from flask_sqlalchemy import SQLAlchemy
import requests
from flask import request, jsonify, Flask
from flask_cors import CORS
from google import genai

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


def getReccoSongProperties(SpotifyIDs):
    """
    Gets the song properties from the Recco API

    :param SpotifyIDs: list of Spotify IDs
    :return: array of song properties
    """
    recHeaders = {
        'Accept': 'application/json'}

    reccoBeatsRes = requests.get(f"https://api.reccobeats.com/v1/track?ids={",".join(SpotifyIDs)}", headers=recHeaders)
    reccoSongDetails = []
    for track in reccoBeatsRes.json()["content"]:
        rawReturn = requests.get(f"https://api.reccobeats.com/v1/track/{track["id"]}/audio-features",
                         headers=recHeaders).json()
        rawReturn.pop("id")
        rawReturn.pop("href")
        reccoSongDetails.append(rawReturn)
    return reccoSongDetails


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
    url = f"https://api.spotify.com/v1/tracks/{spotify_id}"
    headers = {"Authorization": f"Bearer {access_token}"}

    resp = requests.get(url, headers=headers)
    resp.raise_for_status()
    track = resp.json()

    images = track["album"]["images"]
    # Find image with requested size or just return the largest
    for img in images:
        if img["height"] == size:
            return img["url"]
    # If requested size not found, return the first image
    return images[0]["url"]

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

@app.route("/linkSend", methods=['POST'])
def linkSend():
    data = request.get_json()
    playlist_id = data["playlist_id"]

    # 54ZA9LXFvvFujmOVWXpHga

    url = f"https://api.spotify.com/v1/playlists/{playlist_id}"

    headers = {
        "Authorization": f"Bearer {access_token}"
    }

    response = requests.get(url, headers=headers)
    response.raise_for_status()

    reccoSongDetails = getReccoSongProperties(getSpotifyIDs(response.json()))

    for i in range(len(response.json()["tracks"]["items"])):
        track = response.json()["tracks"]["items"][i]["track"]
        create_song(getSpotifyIDs(response.json())[i], track["name"], [artist["name"] for artist in track["artists"]], reccoSongDetails[i])

    geminiJSON = create_gemini_json()
    prompt = f"""SYSTEM:
You are a music recommendation assistant. Output ONLY a JSON list (array) of EXACTLY 30 objects.
Each object MUST have exactly these keys with these types:
"name": string (track title)
"artist": array of strings (list of artist names; use a list even if there is only one artist)
No other text, no markdown, no extra keys.

INSTRUCTIONS:
Input is an array of seed songs with audio features and artist names.
Recommend 30 DISTINCT tracks that are similar to the overall seed profile.
You MUST infer likely genres of the seeds from your knowledge of the tracks/artists and use those inferred genres when selecting recommendations.
Do NOT return any seed tracks.
Diversity: cap at 2 tracks involving the same artist name (across any position in the artist list).

OPTIMIZATION (in order):
1) Match audio profile: keep tempo within ±8% of the median seed tempo; prefer similar danceability, energy, and valence; respect mode and time_signature when helpful.
2) Incorporate inferred genres: align with the top inferred genres; include a mix across those genres.
3) Reflect the categories below (moods/use-cases/constraints) across the set.

SEEDS_JSON:
{geminiJSON}

OUTPUT SHAPE EXAMPLE (structure only):
[
  {{"name": "Track Title 1", "artist": ["Primary Artist 1"]}},
  {{"name": "Track Title 2", "artist": ["Artist A", "Artist B"]}},
  ...
]
Return ONLY the JSON array (30 items)."""

    recommendationIDs = parse_markdown_json(geminiCall(prompt))

    for index, recommendation in enumerate(recommendationIDs):
        spotifyID = get_spotify_id(recommendation["name"], ",".join(recommendation["artist"]))
        if spotifyID == None:
            recommendationIDs.pop(index)
            continue
        print(spotifyID)
        recommendationIDs[index]["spotify_id"] = spotifyID
        recommendationIDs[index]["image_url"] = get_album_art(spotifyID)


    return recommendationIDs, 200
