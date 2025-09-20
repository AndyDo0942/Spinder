import base64
from flask_sqlalchemy import SQLAlchemy
import requests
from flask import request, jsonify, Flask
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

app.config["SQLALCHEMY_DATABASE_URI"] = "sqlite:///mydatabase.db"
app.config["SQLALCHEMY_TRACK_MODIFICATIONS"] = False

db = SQLAlchemy(app)

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


def getSpotifyIDs(SpotifyJSON):
    SpotifyIDs = []
    for track in SpotifyJSON["tracks"]["items"]:
        SpotifyIDs.append(track["track"]["id"])
    return SpotifyIDs


def getReccoSongProperties(SpotifyIDs):
    recHeaders = {
        'Accept': 'application/json'}

    reccoBeatsRes = requests.get(f"https://api.reccobeats.com/v1/track?ids={",".join(SpotifyIDs)}", headers=recHeaders,
                                 data={})
    reccoSongDetails = []
    for track in reccoBeatsRes.json()["content"]:
        reccoSongDetails.append(
            requests.get(f"https://api.reccobeats.com/v1/track/{track["id"]}/audio-features", headers=recHeaders,
                         data={}).json())

    return reccoSongDetails


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

    reccoSongDetails = getReccoSongProperties(response.json())

    print(reccoSongDetails)
    return response.json(), response.status_code
