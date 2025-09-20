from app import db

# Association tables
song_artist = db.Table(
    'song_artist',
    db.Column('song_id', db.Integer, db.ForeignKey('Songs.id'), primary_key=True),
    db.Column('artist_id', db.Integer, db.ForeignKey('artists.id'), primary_key=True)
)

"""song_genre = db.Table(
    'song_genre',
    db.Column('song_id', db.Integer, db.ForeignKey('Songs.id'), primary_key=True),
    db.Column('genre_id', db.Integer, db.ForeignKey('genres.id'), primary_key=True)
)"""

<<<<<<< Updated upstream
=======
"""class Playlist(db.Model):
    __tablename__ = "playlists"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_playlist_id = db.Column(db.String(100), nullable=False)
    name = db.Column(db.String(200), nullable=False)
    description = db.Column(db.Text, nullable=True)
    user_id = db.Column(db.Integer, db.ForeignKey('users.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)



    #relationships
    user = db.relationship('User', back_populates='playlist')
    songs = db.relationship('Song', back_populates='playlist')
    recommendations = db.relationship('Recommendation')"""
>>>>>>> Stashed changes
class Song(db.Model):
    __tablename__ = "Songs"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
<<<<<<< Updated upstream
    tempo = db.Column(db.Integer, nullable=False)
=======
    spotify_id = db.Column(db.String(100), unique=True, nullable=False)
    name = db.Column(db.String(200), nullable=False)
    artists = db.Column(db.list, nullable=False)
    
    # Audio features for Gemini analysis
    tempo = db.Column(db.Float, nullable=True)
    danceability = db.Column(db.Float, nullable=True)
    energy = db.Column(db.Float, nullable=True)
    valence = db.Column(db.Float, nullable=True)
    acousticness = db.Column(db.Float, nullable=True)
    instrumentalness = db.Column(db.Float, nullable=True)
    liveness = db.Column(db.Float, nullable=True)
    loudness = db.Column(db.Float, nullable=True)
    speechiness = db.Column(db.Float, nullable=True)
    key = db.Column(db.Integer, nullable=True)
    mode = db.Column(db.Integer, nullable=True)
    time_signature = db.Column(db.Integer, nullable=True)
    
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # One-to-many relationship with playlist
    """playlist_id = db.Column(db.Integer, db.ForeignKey('playlists.id'), nullable=False)
    playlist = db.relationship('Playlist', back_populates='songs')"""
    
    # Many-to-many relationships
>>>>>>> Stashed changes
    artists = db.relationship('Artist', secondary=song_artist, back_populates='songs')
    """genres = db.relationship('Genre', secondary=song_genre, back_populates='songs')"""

class Artist(db.Model):
    __tablename__ = "artists"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
<<<<<<< Updated upstream
    name = db.Column(db.String, nullable=False)
=======
    spotify_id = db.Column(db.String(100), unique=True, nullable=False)
    name = db.Column(db.String(200), nullable=False)
    genre = db.Column(db.List, nullable=True)
    #Many to many
>>>>>>> Stashed changes
    songs = db.relationship('Song', secondary=song_artist, back_populates='artists')

"""class Genre(db.Model):
    __tablename__ = "genres"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String, nullable=False)
<<<<<<< Updated upstream
    songs = db.relationship('Song', secondary=song_genre, back_populates='genres')
=======
    songs = db.relationship('Song', secondary=song_genre, back_populates='genres')"""

class Recommendation(db.Model):
    __tablename__ = "recommendations"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_song_id = db.Column(db.String(100), nullable=False)  # Spotify ID of recommended song
    name = db.Column(db.String(200), nullable=False)  # Song name
    image_url = db.Column(db.String(500), nullable=True)  # Album artwork
    external_url = db.Column(db.String(500), nullable=True)  # Spotify link
    preview_url = db.Column(db.String(500), nullable=True)  # 30-second preview
    created_at = db.Column(db.DateTime, default=datetime.utcnow)
    
    # Link to playlist
    playlist_id = db.Column(db.Integer, db.ForeignKey('playlists.id'), nullable=False)
    playlist = db.relationship('Playlist', back_populates='recommendations')

"""
Utility functions :)
"""


def create_song(spotify_id, name, artist, audio_features=None):
    song = Song(spotify_id=spotify_id, name=name, artist=[artist])
    if audio_features:
        song.tempo = audio_features.get('tempo')
        song.danceability = audio_features.get('danceability')
        song.energy = audio_features.get('energy')
        song.valence = audio_features.get('valence')
        song.acousticness = audio_features.get('acousticness')
        song.instrumentalness = audio_features.get('instrumentalness')
        song.liveness = audio_features.get('liveness')
        song.loudness = audio_features.get('loudness')
        song.speechiness = audio_features.get('speechiness')
        song.key = audio_features.get('key')
        song.mode = audio_features.get('mode')
        song.time_signature = audio_features.get('time_signature')
    db.session.add(song)
    db.session.commit()

    def create_gemini_json():
        songs = Song.query.all()
        gemini_data = []
        for song in songs:
            song_data = {
                "author": [artist.name for artist in song.artists],
                "spotify_id": song.spotify_id,
                "name": song.name,
                "tempo": song.tempo,
                "danceability": song.danceability,
                "energy": song.energy,
                "valence": song.valence,
                "acousticness": song.acousticness,
                "instrumentalness": song.instrumentalness,
                "liveness": song.liveness,
                "loudness": song.loudness,
                "speechiness": song.speechiness,
                "key": song.key,
                "mode": song.mode,
                "time_signature": song.time_signature
            }
            gemini_data.append(song_data)
        return gemini_data


    return song

>>>>>>> Stashed changes
