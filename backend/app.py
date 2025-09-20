import base64

import requests
from flask import request, jsonify, Flask
from flask_sqlalchemy import SQLAlchemy
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

    playlist_data = response.json()

    # Print some info
    print("Playlist name:", playlist_data["name"])
    print("Owner:", playlist_data["owner"]["display_name"])
    print("Total tracks:", playlist_data["tracks"]["total"])

    # List first few tracks
    for item in playlist_data["tracks"]["items"][:5]:
        track = item["track"]
        print(track["name"], "-", ", ".join(artist["name"] for artist in track["artists"]))

    return response.json(), response.status_code
