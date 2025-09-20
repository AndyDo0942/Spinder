import base64
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

from db import create_song, create_gemini_json, db
db.init_app(app)
with app.app_context():
    db.create_all()

with app.app_context():
    from db import reset_schema
    reset_schema()

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
        create_song(getSpotifyIDs(response.json())[i], track["name"], track["artists"]["name"], reccoSongDetails[i])

    geminiJSON = create_gemini_json()



    return geminiJSON, 200
