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
    
    level = db.Column(db.Integer, default=1)
    character_class = db.Column(db.Integer, default=0)
    experience = db.Column(db.Integer, default=0)
    current_health = db.Column(db.Integer, default=100)
    max_health = db.Column(db.Integer, default=100)
    last_map = db.Column(db.String(255), default="game")
    party_id = db.Column(db.Integer, default=-1)
    monies = db.Column(db.Integer, default=0) # Moved monies to player table
    
    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    # Relationships
    items = db.relationship('PlayerItem', backref='player', cascade="all, delete-orphan")
    equipment = db.relationship('PlayerEquipment', backref='player', cascade="all, delete-orphan")
    abilities = db.relationship('PlayerAbility', backref='player', cascade="all, delete-orphan")
    hotbar = db.relationship('PlayerHotbar', backref='player', cascade="all, delete-orphan")
    buffs = db.relationship('PlayerBuff', backref='player', cascade="all, delete-orphan")

class PlayerItem(db.Model):
    __tablename__ = 'player_items'
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    item_id = db.Column(db.String(255)) # Godot UUID for smart syncing
    slot_index = db.Column(db.Integer)
    item_path = db.Column(db.String(512)) # Resource path
    quantity = db.Column(db.Integer, default=1)
    dynamic_data = db.Column(JSONB, default=dict) # Level, Bonus Stats, etc.

class PlayerEquipment(db.Model):
    __tablename__ = 'player_equipment'
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    item_id = db.Column(db.String(255)) # Godot UUID
    slot_type = db.Column(db.String(50)) # "HEAD", "CHEST", "WEAPON", etc.
    item_path = db.Column(db.String(512))
    dynamic_data = db.Column(JSONB, default=dict)

class PlayerAbility(db.Model):
    __tablename__ = 'player_abilities'
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    ability_id = db.Column(db.String(255))
    level = db.Column(db.Integer, default=0)

class PlayerHotbar(db.Model):
    __tablename__ = 'player_hotbar'
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    slot_index = db.Column(db.Integer)
    ability_id = db.Column(db.String(255))

class PlayerBuff(db.Model):
    __tablename__ = 'player_buffs'
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    buff_id = db.Column(db.String(255))
    duration = db.Column(db.Float)
    stacks = db.Column(db.Integer, default=1)

def init_db():
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                # db.drop_all() # REMOVED: Do not wipe DB on restart
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
        # Reconstruct JSON structure for Godot
        response_data = {
            'username': player.username,
            'level': player.level,
            'character_type': player.character_class,
            'experience': player.experience,
            'current_health': player.current_health,
            'max_health': player.max_health,
            'last_map': player.last_map,
            'party_id': player.party_id,
            'monies': player.monies
        }
        
        # Reconstruct Inventory
        inventory_slots = []
        for item in player.items:
            item_data = {
                "original_resource_path": item.item_path,
                "current_stack_amount": item.quantity,
                # We might need to store item_type in DB if we want to send it back, 
                # OR we rely on Godot to infer it from the path.
                # But since we added it to Godot's to_dictionary, we should probably store it.
                # For now, let's assume Godot can handle it if missing (it defaults to ANY),
                # BUT EquipmentData.from_dictionary might need it if path fails.
                # Let's check if dynamic_data has it.
            }
            if item.dynamic_data:
                item_data.update(item.dynamic_data)
            
            inventory_slots.append({
                "slot_index": item.slot_index,
                "item_data": item_data
            })
            
        equipment_data = {}
        for eq in player.equipment:
            item_data = {
                "original_resource_path": eq.item_path,
                "item_type": 1, # Constants.ItemType.EQUIPMENT
            }
            if eq.dynamic_data:
                item_data.update(eq.dynamic_data)
            equipment_data[eq.slot_type] = item_data
            
        response_data['inventory'] = {
            'monies': player.monies, # Legacy support if client looks here
            'slots': inventory_slots,
            'equipment': equipment_data
        }
        
        # Reconstruct Abilities
        ability_levels = {ab.ability_id: ab.level for ab in player.abilities}
        hotbar_config = {str(hb.slot_index): hb.ability_id for hb in player.hotbar}
        
        # Calculate points (simple logic for now, could be stored if needed)
        # Assuming 3 points per level - 3 (initial) - spent points
        # For now, we might need to store points if they can be unspent.
        # Let's assume points are derived or stored in dynamic_data if we add it later.
        # For this iteration, we'll send 0 available points or need a column for it.
        # Adding points column to Player for simplicity if not present.
        # Wait, previous schema had points in Ability table. Let's add it to Player or calculate.
        # Let's add 'ability_points' to Player table to be safe.
        
        response_data['abilities'] = {
            'available_points': 0, # TODO: Add column if needed, or calc
            'ability_levels': ability_levels,
            'hotbar_config': hotbar_config
        }
        
        # Reconstruct Buffs
        active_buffs = []
        for buff in player.buffs:
            active_buffs.append({
                "buff_id": buff.buff_id,
                "remaining_duration": buff.duration,
                "stacks": buff.stacks
            })
            
        response_data['buffs'] = {
            'active_buffs': active_buffs
        }
            
        return jsonify(response_data)
    else:
        return jsonify({})

@app.route('/api/player/save', methods=['POST'])
def save_player():
    content = request.json
    print(f"Received save request: {content}") # DEBUG LOG
    username = content.get('username')
    data = content.get('data')
    
    if not username or data is None:
        print("Error: Username or data missing")
        return jsonify({"error": "Username and data required"}), 400
        
    player = Player.query.filter_by(username=username).first()
    
    if not player:
        player = Player(username=username)
        db.session.add(player)
    
    # Update Core Stats
    if 'level' in data: player.level = data['level']
    if 'character_type' in data: player.character_class = data['character_type']
    if 'experience' in data: player.experience = data['experience']
    if 'current_health' in data: player.current_health = data['current_health']
    if 'max_health' in data: player.max_health = data['max_health']
    if 'last_map' in data: player.last_map = data['last_map']
    if 'party_id' in data: player.party_id = data['party_id']
    
    # Update Inventory
    if 'inventory' in data:
        inv_data = data['inventory']
        player.monies = inv_data.get('monies', 0)
        
        # --- Smart Sync for Items ---
        existing_items = {item.item_id: item for item in player.items if item.item_id}
        print(f"Existing items: {existing_items.keys()}") # DEBUG
        
        incoming_item_ids = set()
        
        for slot in inv_data.get('slots', []):
            item_data = slot.get('item_data', {})
            path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
            dynamic = item_data.copy()
            if 'current_stack_amount' in dynamic: del dynamic['current_stack_amount']
            
            item_id = item_data.get('item_id')
            print(f"Processing item: {item_id} (Path: {path})") # DEBUG
            
            if item_id and item_id in existing_items:
                # UPDATE existing
                print(f"Updating item {item_id}")
                item = existing_items[item_id]
                item.slot_index = slot.get('slot_index')
                item.item_path = path
                item.quantity = item_data.get('current_stack_amount', 1)
                item.dynamic_data = dynamic
                incoming_item_ids.add(item_id)
            else:
                # INSERT new
                print(f"Inserting new item {item_id}")
                new_item = PlayerItem(
                    player_username=username,
                    item_id=item_id,
                    slot_index=slot.get('slot_index'),
                    item_path=path,
                    quantity=item_data.get('current_stack_amount', 1),
                    dynamic_data=dynamic
                )
                db.session.add(new_item)
                if item_id: incoming_item_ids.add(item_id)
        
        # DELETE removed items
        for iid, item in existing_items.items():
            if iid not in incoming_item_ids:
                print(f"Deleting item {iid}")
                db.session.delete(item)
                
        # --- Smart Sync for Equipment ---
        existing_eq = {eq.item_id: eq for eq in player.equipment if eq.item_id}
        incoming_eq_ids = set()
        
        eq_data = inv_data.get('equipment', {})
        for slot_type, item_data in eq_data.items():
            path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
            dynamic = item_data.copy()
            item_id = item_data.get('item_id')
            
            if item_id and item_id in existing_eq:
                # UPDATE
                eq = existing_eq[item_id]
                eq.slot_type = str(slot_type)
                eq.item_path = path
                eq.dynamic_data = dynamic
                incoming_eq_ids.add(item_id)
            else:
                # INSERT
                new_eq = PlayerEquipment(
                    player_username=username,
                    item_id=item_id,
                    slot_type=str(slot_type),
                    item_path=path,
                    dynamic_data=dynamic
                )
                db.session.add(new_eq)
                if item_id: incoming_eq_ids.add(item_id)
                
        # DELETE removed equipment
        for iid, eq in existing_eq.items():
            if iid not in incoming_eq_ids:
                db.session.delete(eq)

    # Update Abilities
    if 'abilities' in data:
        ab_data = data['abilities']
        # Points - TODO: Add column, for now ignore or store in player dynamic
        
        PlayerAbility.query.filter_by(player_username=username).delete()
        PlayerHotbar.query.filter_by(player_username=username).delete()
        
        for ab_id, level in ab_data.get('ability_levels', {}).items():
            new_ab = PlayerAbility(player_username=username, ability_id=ab_id, level=level)
            db.session.add(new_ab)
            
        for slot, ab_id in ab_data.get('hotbar_config', {}).items():
            new_hb = PlayerHotbar(player_username=username, slot_index=int(slot), ability_id=ab_id)
            db.session.add(new_hb)

    # Update Buffs
    if 'buffs' in data:
        buff_data = data['buffs']
        PlayerBuff.query.filter_by(player_username=username).delete()
        
        for buff in buff_data.get('active_buffs', []):
            new_buff = PlayerBuff(
                player_username=username,
                buff_id=buff.get('buff_id'),
                duration=buff.get('remaining_duration'),
                stacks=buff.get('stacks', 1)
            )
            db.session.add(new_buff)

    db.session.commit()
    return jsonify({"status": "success"})

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
