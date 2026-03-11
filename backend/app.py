from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import joinedload
from werkzeug.security import generate_password_hash, check_password_hash
import os
import time
import threading

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/gamedb')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['SQLALCHEMY_ENGINE_OPTIONS'] = {
    'pool_size': 20,
    'pool_recycle': 3600,
    'pool_pre_ping': True,
}

db = SQLAlchemy(app)

import uuid
import datetime

class Account(db.Model):
    __tablename__ = 'accounts'
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    username = db.Column(db.String(255), unique=True, nullable=False)
    password_hash = db.Column(db.String(255), nullable=False)  # TODO: Hash passwords!
    created_at = db.Column(db.DateTime, default=datetime.datetime.utcnow)
    
    # Relationship
    players = db.relationship('Player', backref='account', cascade="all, delete-orphan")

class Player(db.Model):
    __tablename__ = 'players'
    # Integer Primary Key (Auto-incrementing)
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    # Foreign key to Account
    account_id = db.Column(db.Integer, db.ForeignKey('accounts.id'), nullable=False)
    # Username is unique and represents the CHARACTER NAME
    username = db.Column(db.String(255), unique=True, nullable=False)
    
    level = db.Column(db.Integer, default=1)
    character_class = db.Column(db.Integer, default=0)
    experience = db.Column(db.Integer, default=0)
    current_health = db.Column(db.Integer, default=100)
    max_health = db.Column(db.Integer, default=100)
    current_mana = db.Column(db.Integer, default=100)
    max_mana = db.Column(db.Integer, default=100)
    last_map = db.Column(db.String(255), default="game")
    party_id = db.Column(db.Integer, default=-1)
    monies = db.Column(db.Integer, default=0)
    ability_points = db.Column(db.Integer, default=0)

    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    # Relationships
    items = db.relationship('PlayerItem', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerItem.player_username', primaryjoin="Player.username==PlayerItem.player_username")
    equipment = db.relationship('PlayerEquipment', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerEquipment.player_username', primaryjoin="Player.username==PlayerEquipment.player_username")
    abilities = db.relationship('PlayerAbility', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerAbility.player_username', primaryjoin="Player.username==PlayerAbility.player_username")
    hotbar = db.relationship('PlayerHotbar', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerHotbar.player_username', primaryjoin="Player.username==PlayerHotbar.player_username")
    buffs = db.relationship('PlayerBuff', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerBuff.player_username', primaryjoin="Player.username==PlayerBuff.player_username")

class PlayerItem(db.Model):
    __tablename__ = 'player_items'
    __table_args__ = (
        db.Index('idx_playeritem_username', 'player_username'),
        db.UniqueConstraint('player_username', 'slot_index', name='uq_playeritem_slot'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    item_id = db.Column(db.String(255)) # Godot UUID
    slot_index = db.Column(db.Integer)
    item_path = db.Column(db.String(512))
    quantity = db.Column(db.Integer, default=1)
    
    # Normalized Data
    name = db.Column(db.String(255))
    description = db.Column(db.Text)
    icon_path = db.Column(db.String(512))
    item_type = db.Column(db.Integer, default=0)
    item_level = db.Column(db.Integer, default=0)
    rarity = db.Column(db.Integer, default=0)
    custom_value = db.Column(db.Integer, default=0)
    
    # Equipment Specifics (Nullable since not all items are equipment)
    equipment_type = db.Column(db.Integer, nullable=True)
    armor_type = db.Column(db.Integer, nullable=True)
    weapon_type = db.Column(db.Integer, nullable=True)
    attack_speed = db.Column(db.Float, nullable=True)
    
    stats = db.Column(JSONB, default=dict) # Replaces dynamic_data

class PlayerEquipment(db.Model):
    __tablename__ = 'player_equipment'
    __table_args__ = (
        db.Index('idx_playerequip_username', 'player_username'),
        db.UniqueConstraint('player_username', 'slot_type', name='uq_playerequip_slot'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    item_id = db.Column(db.String(255))
    slot_type = db.Column(db.String(50))
    item_path = db.Column(db.String(512))
    
    # Normalized Data
    name = db.Column(db.String(255))
    description = db.Column(db.Text)
    icon_path = db.Column(db.String(512))
    item_type = db.Column(db.Integer, default=1) # Default to EQUIPMENT
    item_level = db.Column(db.Integer, default=0)
    rarity = db.Column(db.Integer, default=0)
    custom_value = db.Column(db.Integer, default=0)
    
    # Equipment Specifics
    equipment_type = db.Column(db.Integer, default=0)
    armor_type = db.Column(db.Integer, default=0)
    weapon_type = db.Column(db.Integer, default=0)
    attack_speed = db.Column(db.Float, default=0.0)
    
    stats = db.Column(JSONB, default=dict) # Replaces dynamic_data

class PlayerAbility(db.Model):
    __tablename__ = 'player_abilities'
    __table_args__ = (
        db.Index('idx_playerability_username', 'player_username'),
        db.UniqueConstraint('player_username', 'ability_id', name='uq_playerability_id'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    ability_id = db.Column(db.String(255))
    level = db.Column(db.Integer, default=1)

class PlayerHotbar(db.Model):
    __tablename__ = 'player_hotbar'
    __table_args__ = (
        db.Index('idx_playerhotbar_username', 'player_username'),
        db.UniqueConstraint('player_username', 'slot_index', name='uq_playerhotbar_slot'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    slot_index = db.Column(db.Integer)
    ability_id = db.Column(db.String(255))

class PlayerBuff(db.Model):
    __tablename__ = 'player_buffs'
    __table_args__ = (
        db.Index('idx_playerbuff_username', 'player_username'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    buff_id = db.Column(db.String(255))
    duration = db.Column(db.Float)
    stacks = db.Column(db.Integer, default=1)

# ==================== PER-PLAYER SAVE LOCKING ====================

_player_locks = {}
_lock_manager = threading.Lock()

def get_player_lock(username):
    with _lock_manager:
        if username not in _player_locks:
            _player_locks[username] = threading.Lock()
        return _player_locks[username]

# ==================== ACCOUNT ENDPOINTS ====================

@app.route('/api/account/register', methods=['POST'])
def register_account():
    content = request.json
    username = content.get('username')
    password = content.get('password')
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    # Check if username already exists
    existing_account = Account.query.filter_by(username=username).first()
    if existing_account:
        return jsonify({"error": "Username already exists"}), 400
    
    # Create new account (Hash the password!)
    hashed_password = generate_password_hash(password)
    new_account = Account(username=username, password_hash=hashed_password)
    db.session.add(new_account)
    db.session.commit()
    
    return jsonify({"message": "Account created", "account_id": new_account.id}), 201


@app.route('/api/account/login', methods=['POST'])
def login_account():
    content = request.json
    username = content.get('username')
    password = content.get('password')
    
    if not username or not password:
        return jsonify({"error": "Username and password required"}), 400
    
    # Find account
    account = Account.query.filter_by(username=username).first()
    
    if not account or not check_password_hash(account.password_hash, password):
        return jsonify({"error": "Invalid username or password"}), 401
    
    return jsonify({"account_id": account.id, "username": account.username}), 200


@app.route('/api/account/characters', methods=['POST'])
def get_characters():
    content = request.json
    account_id = content.get('account_id')
    
    if not account_id:
        return jsonify({"error": "Account ID required"}), 400
    
    # Get all characters for this account
    characters = Player.query.filter_by(account_id=account_id).all()
    
    character_list = []
    for char in characters:
        character_list.append({
            "name": char.username,
            "level": char.level,
            "character_class": char.character_class
        })
    
    return jsonify({"characters": character_list}), 200


@app.route('/api/character/create', methods=['POST'])
def create_character():
    content = request.json
    account_id = content.get('account_id')
    char_name = content.get('name')
    class_id = content.get('class_id', 0)
    
    if not account_id or not char_name:
        return jsonify({"error": "Account ID and character name required"}), 400
    
    # Check if character name already exists
    existing_char = Player.query.filter_by(username=char_name).first()
    if existing_char:
        return jsonify({"error": "Character name already exists"}), 400
    
    # Create new character
    new_player = Player(
        account_id=account_id,
        username=char_name,
        level=1,
        experience=0,
        last_map="game",
        monies=0,
        character_class=class_id,
        current_health=100,
        max_health=100,
        current_mana=100,
        max_mana=100,
        party_id=-1
    )
    
    db.session.add(new_player)
    db.session.commit()
    
    return jsonify({"message": "Character created", "name": char_name}), 201


# ==================== PLAYER ENDPOINTS ====================

@app.route('/api/player/load', methods=['POST'])
def load_player():
    content = request.json
    username = content.get('username')
    
    if not username:
        return jsonify({"error": "Username required"}), 400
        
    player = Player.query.options(
        joinedload(Player.items),
        joinedload(Player.equipment),
        joinedload(Player.abilities),
        joinedload(Player.hotbar),
        joinedload(Player.buffs),
    ).filter_by(username=username).first()

    if player:
        # Reconstruct JSON structure for Godot
        response_data = {
            'username': player.username,
            'level': player.level,
            'character_type': player.character_class,
            'experience': player.experience,
            'current_health': player.current_health,
            'max_health': player.max_health,
            'current_mana': player.current_mana,
            'max_mana': player.max_mana,
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
                "item_id": item.item_id,
                "name": item.name,
                "description": item.description,
                "icon_path": item.icon_path,
                "item_type": item.item_type,
                "item_level": item.item_level,
                "rarity": item.rarity,
                "custom_item_value": item.custom_value,
                "equipment_type": item.equipment_type,
                "armor_type": item.armor_type,
                "weapon_type": item.weapon_type,
                "weapon_attack_speed": item.attack_speed,
                "bonus_stats": item.stats
            }
            
            inventory_slots.append({
                "slot_index": item.slot_index,
                "item_data": item_data
            })
            
        equipment_data = {}
        for eq in player.equipment:
            item_data = {
                "original_resource_path": eq.item_path,
                "item_id": eq.item_id,
                "name": eq.name,
                "description": eq.description,
                "icon_path": eq.icon_path,
                "item_type": eq.item_type,
                "item_level": eq.item_level,
                "rarity": eq.rarity,
                "custom_item_value": eq.custom_value,
                "equipment_type": eq.equipment_type,
                "armor_type": eq.armor_type,
                "weapon_type": eq.weapon_type,
                "weapon_attack_speed": eq.attack_speed,
                "bonus_stats": eq.stats
            }
            equipment_data[eq.slot_type] = item_data
            
        response_data['inventory'] = {
            'monies': player.monies, # Legacy support if client looks here
            'slots': inventory_slots,
            'equipment': equipment_data
        }
        
        # Reconstruct Abilities
        ability_levels = {ab.ability_id: ab.level for ab in player.abilities}
        hotbar_config = {str(hb.slot_index): hb.ability_id for hb in player.hotbar}
        
        response_data['abilities'] = {
            'available_points': player.ability_points if player.ability_points is not None else 0,
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
    # --- Fix 5: Basic Request Validation ---
    content = request.json
    if not content:
        return jsonify({"error": "No JSON body"}), 400

    username = content.get('username')
    data = content.get('data')

    if not username or not isinstance(username, str):
        return jsonify({"error": "Valid username required"}), 400
    if data is not None and not isinstance(data, dict):
        return jsonify({"error": "Data must be a dictionary"}), 400
    if data is None:
        return jsonify({"error": "Username and data required"}), 400

    # --- Fix 4: Per-Player Save Locking ---
    lock = get_player_lock(username)
    if not lock.acquire(timeout=5):
        return jsonify({"error": "Save in progress"}), 429

    try:
        player = Player.query.options(
            joinedload(Player.items),
            joinedload(Player.equipment),
            joinedload(Player.abilities),
            joinedload(Player.hotbar),
            joinedload(Player.buffs),
        ).filter_by(username=username).first()

        if not player:
            player = Player(username=username)
            db.session.add(player)

        # Update Core Stats
        if 'level' in data: player.level = data['level']
        if 'character_type' in data: player.character_class = data['character_type']
        if 'experience' in data: player.experience = data['experience']
        if 'current_health' in data: player.current_health = data['current_health']
        if 'max_health' in data: player.max_health = data['max_health']
        if 'current_mana' in data: player.current_mana = data['current_mana']
        if 'max_mana' in data: player.max_mana = data['max_mana']
        if 'last_map' in data: player.last_map = data['last_map']
        if 'party_id' in data: player.party_id = data['party_id']

        # Update Inventory
        if 'inventory' in data:
            inv_data = data['inventory']
            player.monies = inv_data.get('monies', 0)

            # --- Smart Sync for Items (By Slot Index) ---
            existing_items = {item.slot_index: item for item in player.items}
            incoming_slots = set()

            for slot in inv_data.get('slots', []):
                slot_index = slot.get('slot_index')
                if slot_index is None: continue

                incoming_slots.add(slot_index)
                item_data = slot.get('item_data', {})
                path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""

                item_id = item_data.get('item_id')

                # Extract normalized data
                name = item_data.get('name', "")
                description = item_data.get('description', "")
                icon_path = item_data.get('icon_path', "")
                item_type = item_data.get('item_type', 0)
                item_level = item_data.get('item_level', 0)
                rarity = item_data.get('rarity', 0)
                custom_value = item_data.get('custom_item_value', 0)

                equipment_type = item_data.get('equipment_type')
                armor_type = item_data.get('armor_type')
                weapon_type = item_data.get('weapon_type')
                attack_speed = item_data.get('weapon_attack_speed')

                stats = item_data.get('bonus_stats', {})

                if slot_index in existing_items:
                    # UPDATE existing slot
                    item = existing_items[slot_index]
                    item.item_id = item_id
                    item.item_path = path
                    item.quantity = item_data.get('current_stack_amount', 1)
                    item.name = name
                    item.description = description
                    item.icon_path = icon_path
                    item.item_type = item_type
                    item.item_level = item_level
                    item.rarity = rarity
                    item.custom_value = custom_value
                    item.equipment_type = equipment_type
                    item.armor_type = armor_type
                    item.weapon_type = weapon_type
                    item.attack_speed = attack_speed
                    item.stats = stats
                else:
                    # INSERT new slot
                    new_item = PlayerItem(
                        player_username=username,
                        item_id=item_id,
                        slot_index=slot_index,
                        item_path=path,
                        quantity=item_data.get('current_stack_amount', 1),
                        name=name,
                        description=description,
                        icon_path=icon_path,
                        item_type=item_type,
                        item_level=item_level,
                        rarity=rarity,
                        custom_value=custom_value,
                        equipment_type=equipment_type,
                        armor_type=armor_type,
                        weapon_type=weapon_type,
                        attack_speed=attack_speed,
                        stats=stats
                    )
                    db.session.add(new_item)

            # DELETE items in slots that are no longer occupied
            for idx, item in existing_items.items():
                if idx not in incoming_slots:
                    db.session.delete(item)

            # --- Smart Sync for Equipment (By Slot Type) ---
            existing_eq = {eq.slot_type: eq for eq in player.equipment}
            incoming_eq_slots = set()

            eq_data = inv_data.get('equipment', {})
            for slot_type, item_data in eq_data.items():
                slot_type_str = str(slot_type)
                incoming_eq_slots.add(slot_type_str)

                path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
                item_id = item_data.get('item_id')

                # Extract normalized data
                name = item_data.get('name', "")
                description = item_data.get('description', "")
                icon_path = item_data.get('icon_path', "")
                item_type = item_data.get('item_type', 1) # Default Equipment
                item_level = item_data.get('item_level', 0)
                rarity = item_data.get('rarity', 0)
                custom_value = item_data.get('custom_item_value', 0)

                equipment_type = item_data.get('equipment_type', 0)
                armor_type = item_data.get('armor_type', 0)
                weapon_type = item_data.get('weapon_type', 0)
                attack_speed = item_data.get('weapon_attack_speed', 0.0)

                stats = item_data.get('bonus_stats', {})

                if slot_type_str in existing_eq:
                    # UPDATE existing equipment slot
                    eq = existing_eq[slot_type_str]
                    eq.item_id = item_id
                    eq.item_path = path
                    eq.name = name
                    eq.description = description
                    eq.icon_path = icon_path
                    eq.item_type = item_type
                    eq.item_level = item_level
                    eq.rarity = rarity
                    eq.custom_value = custom_value
                    eq.equipment_type = equipment_type
                    eq.armor_type = armor_type
                    eq.weapon_type = weapon_type
                    eq.attack_speed = attack_speed
                    eq.stats = stats
                else:
                    # INSERT new equipment slot
                    new_eq = PlayerEquipment(
                        player_username=username,
                        item_id=item_id,
                        slot_type=slot_type_str,
                        item_path=path,
                        name=name,
                        description=description,
                        icon_path=icon_path,
                        item_type=item_type,
                        item_level=item_level,
                        rarity=rarity,
                        custom_value=custom_value,
                        equipment_type=equipment_type,
                        armor_type=armor_type,
                        weapon_type=weapon_type,
                        attack_speed=attack_speed,
                        stats=stats
                    )
                    db.session.add(new_eq)

            # DELETE equipment in slots that are no longer occupied
            for stype, eq in existing_eq.items():
                if stype not in incoming_eq_slots:
                    db.session.delete(eq)

        # --- Fix 3: UPSERT for Abilities ---
        if 'abilities' in data:
            ab_data = data['abilities']

            # Save ability points
            if 'available_points' in ab_data:
                player.ability_points = ab_data['available_points']

            # Smart sync abilities
            incoming_abilities = ab_data.get('ability_levels', {})
            existing_abilities = {a.ability_id: a for a in player.abilities}

            for ab_id, level in incoming_abilities.items():
                if ab_id in existing_abilities:
                    existing_abilities[ab_id].level = level
                else:
                    db.session.add(PlayerAbility(player_username=username, ability_id=ab_id, level=level))

            for ab_id in existing_abilities:
                if ab_id not in incoming_abilities:
                    db.session.delete(existing_abilities[ab_id])

            # Smart sync hotbar
            incoming_hotbar = ab_data.get('hotbar_config', {})
            existing_hotbar = {str(hb.slot_index): hb for hb in player.hotbar}

            for slot, ab_id in incoming_hotbar.items():
                slot_str = str(slot)
                if slot_str in existing_hotbar:
                    existing_hotbar[slot_str].ability_id = ab_id
                else:
                    db.session.add(PlayerHotbar(player_username=username, slot_index=int(slot), ability_id=ab_id))

            for slot_str in existing_hotbar:
                if slot_str not in {str(s) for s in incoming_hotbar}:
                    db.session.delete(existing_hotbar[slot_str])

        # --- Fix 3: UPSERT for Buffs ---
        if 'buffs' in data:
            buff_data = data['buffs']
            incoming_buffs = buff_data.get('active_buffs', [])
            existing_buffs = {b.buff_id: b for b in player.buffs}

            incoming_buff_ids = set()
            for buff in incoming_buffs:
                bid = buff.get('buff_id')
                if not bid:
                    continue
                incoming_buff_ids.add(bid)
                if bid in existing_buffs:
                    existing_buffs[bid].duration = buff.get('remaining_duration')
                    existing_buffs[bid].stacks = buff.get('stacks', 1)
                else:
                    db.session.add(PlayerBuff(
                        player_username=username,
                        buff_id=bid,
                        duration=buff.get('remaining_duration'),
                        stacks=buff.get('stacks', 1)
                    ))

            for bid in existing_buffs:
                if bid not in incoming_buff_ids:
                    db.session.delete(existing_buffs[bid])

        db.session.commit()
        return jsonify({"status": "success"}), 200

    except Exception as e:
        db.session.rollback()
        print(f"Error saving player data: {e}")
        return jsonify({"error": "Save failed", "details": str(e)}), 500
    finally:
        lock.release()

@app.route('/health', methods=['GET'])
def health_check():
    try:
        db.session.execute(db.text('SELECT 1'))
        return jsonify({"status": "healthy"}), 200
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 503


def _run_migrations():
    """Add columns that may be missing from older database schemas."""
    migrations = [
        ("players", "current_mana", "ALTER TABLE players ADD COLUMN current_mana INTEGER DEFAULT 100"),
        ("players", "max_mana",     "ALTER TABLE players ADD COLUMN max_mana INTEGER DEFAULT 100"),
    ]
    for table, column, sql in migrations:
        try:
            db.session.execute(db.text(
                f"SELECT {column} FROM {table} LIMIT 1"
            ))
        except Exception:
            db.session.rollback()
            print(f"Migration: adding {table}.{column}")
            db.session.execute(db.text(sql))
            db.session.commit()


def init_db():
    """Initialize database with retry logic for Docker startup"""
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                db.create_all()
                _run_migrations()
                print("Database tables created successfully!")
                return
        except Exception as e:
            print(f"Database connection failed, retrying... ({retries} left)")
            print(e)
            retries -= 1
            time.sleep(5)
    print("Could not connect to database after multiple retries.")

if __name__ == '__main__':
    init_db()
    app.run(host='0.0.0.0', port=5000)
