from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB
import os
import time

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/gamedb')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

db = SQLAlchemy(app)

class Player(db.Model):
    __tablename__ = 'players'
    username = db.Column(db.String(255), primary_key=True)
    data = db.Column(JSONB)
    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

def init_db():
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                db.create_all()
            print("Database initialized successfully.")
            return
        except Exception as e:
            print(f"Database connection failed, retrying... ({retries} left)")
            print(e)
            retries -= 1
            time.sleep(5)
    print("Could not connect to database.")

@app.route('/api/player/load', methods=['POST'])
def load_player():
    content = request.json
    username = content.get('username')
    
    if not username:
        return jsonify({"error": "Username required"}), 400
        
    player = Player.query.filter_by(username=username).first()
    
    if player:
        return jsonify(player.data)
    else:
        return jsonify({}) # Return empty dict for new player

@app.route('/api/player/save', methods=['POST'])
def save_player():
    content = request.json
    username = content.get('username')
    data = content.get('data')
    
    if not username or data is None:
        return jsonify({"error": "Username and data required"}), 400
        
    player = Player.query.filter_by(username=username).first()
    
    if player:
        player.data = data
    else:
        player = Player(username=username, data=data)
        db.session.add(player)
        
    db.session.commit()
    return jsonify({"status": "success"})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
