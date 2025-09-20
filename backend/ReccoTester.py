from app import getReccoSongProperties, geminiCall, get_spotify_id, get_album_art

#Spotifyids = ['5CZ40GBx1sQ9agT82CLQCT', '2TOzTqQXNmR2zDJXihjZ2e', '4ZtFanR9U6ndgddUvNcjcG', '5wANPM4fQCJwkGd4rN57mH', '6HU7h9RYOaPRFeh0R3UeAr', '0MMyJUC3WNnFS1lit5pTjk', '6SRsiMl7w1USE4mFqrOhHC', '4wcBRRpIfesgcyUtis7PEg', '5JCoSi02qi3jJeHdZXMmR8', '6P4d1NWBCNIYZjzF9k1mVN', '61W7tEpxEfmizp6V5ZRN10']
#print(getReccoSongProperties(Spotifyids))


song_id = get_spotify_id("Shape of You", "Ed Sheeran")
print("Spotify ID:", song_id)
print(get_album_art(song_id))