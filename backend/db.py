from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
# Association table for many-to-many relationship between songs and artists
"""song_artist = db.Table(
    'song_artist',
    db.Column('song_id', db.Integer, db.ForeignKey('songs.id'), primary_key=True),
    db.Column('artist_id', db.Integer, db.ForeignKey('artists.id'), primary_key=True)
)"""
from flask import current_app
from sqlalchemy import text

def reset_schema():
    """
    Drops all tables and recreates them according to the current models.
    Use only in dev—this wipes ALL data.
    """
    with current_app.app_context():
        db.drop_all()
        db.create_all()

class Song(db.Model):
    __tablename__ = "songs"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_id = db.Column(db.String(100), nullable=False)
    name = db.Column(db.String(200), nullable=False)
    artists = db.Column(db.JSON, nullable=False) #list of strings
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
    


class Recommendation(db.Model):
    __tablename__ = "recommendations"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    spotify_song_id = db.Column(db.String(100), nullable=False)
    name = db.Column(db.String(200), nullable=False)
    image_url = db.Column(db.String(500), nullable=True)

# Utility functions

def create_song(spotify_id, name, artists, audio_features):
    # Create the song
    song = Song(
        artists = artists,
        spotify_id=spotify_id,
        name=name,
        # Audio features
        tempo=audio_features.get('tempo'),
        danceability=audio_features.get('danceability'),
        energy=audio_features.get('energy'),
        valence=audio_features.get('valence'),
        acousticness=audio_features.get('acousticness'),
        instrumentalness=audio_features.get('instrumentalness'),
        liveness=audio_features.get('liveness'),
        loudness=audio_features.get('loudness'),
        speechiness=audio_features.get('speechiness'),
        key=audio_features.get('key'),
        mode=audio_features.get('mode'),
        time_signature=audio_features.get('time_signature')
    )
    
    
    db.session.add(song)
    db.session.commit()
    return song

def create_gemini_json():
    """
    Create JSON object to send to Gemini with the exact format you need
    
    Returns:
        list: List of dictionaries, each containing song data for Gemini
    """
    songs = Song.query.all()
    gemini_data = []
    
    for song in songs:
        
        song_data = {
            "song_name": song.name,
            "author_name": song.artists, # List of artist names
            "spotify_song_id": song.spotify_id,
            "audio_features": {
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
        }
        gemini_data.append(song_data)
    
    return gemini_data

def store_gemini_recommendations(recommended_songs):
    for rec_data in recommended_songs:
        recommendation = Recommendation(
            spotify_song_id=rec_data['spotify_id'],
            name=rec_data['name'],
            artist = rec_data.get('artist'),
            image_url=rec_data.get('image_url'),
        )
        
        db.session.add(recommendation)
    
    db.session.commit()
    return len(recommended_songs)

def get_recommendations():
    """Get all recommendations for user display"""
    return Recommendation.query.all()

def get_song_count():
    """Get total number of songs in database"""
    return Song.query.count()

def clear_all_data():
    """Clear all data from all tables (useful for testing)"""
    Recommendation.query.delete()
    Song.query.delete()
    db.session.commit()
    return "All data cleared"

