from config import db

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

class Song(db.Model):
    __tablename__ = "Songs"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    tempo = db.Column(db.Integer, nullable=False)
    artists = db.relationship('Artist', secondary=song_artist, back_populates='songs')
    genres = db.relationship('Genre', secondary=song_genre, back_populates='songs')

class Artist(db.Model):
    __tablename__ = "artists"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String, nullable=False)
    songs = db.relationship('Song', secondary=song_artist, back_populates='artists')

class Genre(db.Model):
    __tablename__ = "genres"
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    name = db.Column(db.String, nullable=False)
    songs = db.relationship('Song', secondary=song_genre, back_populates='genres')
