from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB
import os
import time

app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = os.environ.get('DATABASE_URL', 'postgresql://postgres:password@localhost:5432/gamedb')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False

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
    last_map = db.Column(db.String(255), default="game")
    party_id = db.Column(db.Integer, default=-1)
    monies = db.Column(db.Integer, default=0)
    
    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    # Relationships
    items = db.relationship('PlayerItem', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerItem.player_username', primaryjoin="Player.username==PlayerItem.player_username")
    equipment = db.relationship('PlayerEquipment', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerEquipment.player_username', primaryjoin="Player.username==PlayerEquipment.player_username")
    abilities = db.relationship('PlayerAbility', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerAbility.player_username', primaryjoin="Player.username==PlayerAbility.player_username")
    hotbar = db.relationship('PlayerHotbar', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerHotbar.player_username', primaryjoin="Player.username==PlayerHotbar.player_username")
    buffs = db.relationship('PlayerBuff', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerBuff.player_username', primaryjoin="Player.username==PlayerBuff.player_username")

class PlayerItem(db.Model):
    __tablename__ = 'player_items'
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
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username'))
    ability_id = db.Column(db.String(255))
    level = db.Column(db.Integer, default=1)

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
    
    # Create new account (TODO: Hash the password!)
    new_account = Account(username=username, password_hash=password)
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
    
    if not account or account.password_hash != password:
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
        
        # --- Smart Sync for Items (By Slot Index) ---
        # Use slot_index as the unique key for persistence
        existing_items = {item.slot_index: item for item in player.items}
        incoming_slots = set()
        
        for slot in inv_data.get('slots', []):
            slot_index = slot.get('slot_index')
            if slot_index is None: continue
            
            incoming_slots.add(slot_index)
            item_data = slot.get('item_data', {})
            path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
            dynamic = item_data.copy()
            if 'current_stack_amount' in dynamic: del dynamic['current_stack_amount']
            
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
        # Use slot_type as the unique key
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
        
        # --- Smart Sync for Items (By Slot Index) ---
        # Use slot_index as the unique key for persistence
        existing_items = {item.slot_index: item for item in player.items}
        incoming_slots = set()
        
        for slot in inv_data.get('slots', []):
            slot_index = slot.get('slot_index')
            if slot_index is None: continue
            
            incoming_slots.add(slot_index)
            item_data = slot.get('item_data', {})
            path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
            dynamic = item_data.copy()
            if 'current_stack_amount' in dynamic: del dynamic['current_stack_amount']
            
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
        # Use slot_type as the unique key
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

def init_db():
    """Initialize database with retry logic for Docker startup"""
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                db.create_all()
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
