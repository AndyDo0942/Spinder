from config import db
from datetime import datetime

# Association tables
song_artist = db.Table(
    'song_artist',
    db.Column('song_id', db.Integer, db.ForeignKey('Songs.id'), primary_key=True),
    db.Column('artist_id', db.Integer, db.ForeignKey('artists.id'), primary_key=True)
)

song_genre = db.Table(
    'song_genre',
    db.Column('song_id', db.Integer, db.ForeignKey('Songs.id'), primary_key=True),
    db.Column('genre_id', db.Integer, db.ForeignKey('genres.id'), primary_key=True)
)

class Playlist(db.Model):
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
    recommendations = db.relationship('Recommendation')
class Song(db.Model):
    __tablename__ = "songs"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_id = db.Column(db.String(100), unique=True, nullable=False)
    name = db.Column(db.String(200), nullable=False)
    
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
    playlist_id = db.Column(db.Integer, db.ForeignKey('playlists.id'), nullable=False)
    playlist = db.relationship('Playlist', back_populates='songs')
    
    # Many-to-many relationships
    artists = db.relationship('Artist', secondary=song_artist, back_populates='songs')
    genres = db.relationship('Genre', secondary=song_genre, back_populates='songs')

class Artist(db.Model):
    __tablename__ = "artists"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_id = db.Column(db.String(100), unique=True, nullable=False)
    name = db.Column(db.String(200), nullable=False)
    #Many to many
    songs = db.relationship('Song', secondary=song_artist, back_populates='artists')

class Genre(db.Model):
    __tablename__ = "genres"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String, nullable=False)
    songs = db.relationship('Song', secondary=song_genre, back_populates='genres')

class Recommendation(db.Model):
    __tablename__ = "recommendations"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    playlist_id = db.Column(db.Integer, db.ForeignKey('playlists.id'), nullable=False)
    seed_song_id = db.Column(db.Integer, db.ForeignKey('songs.id'), nullable=False)
    recommended_song_id = db.Column(db.Integer, db.ForeignKey('songs.id'), nullable=False)
    created_at = db.Column(db.DateTime, default=datetime.utcnow)

    # Relationships
    playlist = db.relationship('Playlist', back_populates='recommendations')
    seed_song = db.relationship('Song', foreign_keys=[seed_song_id])
    recommended_song = db.relationship('Song', foreign_keys=[recommended_song_id])
