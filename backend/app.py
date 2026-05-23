from flask import Flask, request, jsonify
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import joinedload
from werkzeug.security import generate_password_hash, check_password_hash
import os
import time
import threading
import logging

app = Flask(__name__)
# Flask defaults app.logger to WARNING outside debug mode — raise it so account
# / character lifecycle info lines emit to docker logs.
app.logger.setLevel(logging.INFO)
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
    last_map = db.Column(db.String(255), default="town")
    party_id = db.Column(db.Integer, default=-1)
    monies = db.Column(db.Integer, default=0)
    ability_points = db.Column(db.Integer, default=0)
    # QuestManager.save_quests blob: {active, completed, onboarded}. Stored as a
    # single JSONB column since quests are only ever read/written wholesale per
    # character — no piecemeal queries — and the schema evolves freely on the
    # Godot side.
    quests = db.Column(JSONB, nullable=True)

    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    # Relationships
    items = db.relationship('PlayerItem', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerItem.player_username', primaryjoin="Player.username==PlayerItem.player_username")
    equipment = db.relationship('PlayerEquipment', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerEquipment.player_username', primaryjoin="Player.username==PlayerEquipment.player_username")
    abilities = db.relationship('PlayerAbility', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerAbility.player_username', primaryjoin="Player.username==PlayerAbility.player_username")
    hotbar = db.relationship('PlayerHotbar', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerHotbar.player_username', primaryjoin="Player.username==PlayerHotbar.player_username")
    buffs = db.relationship('PlayerBuff', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerBuff.player_username', primaryjoin="Player.username==PlayerBuff.player_username")

# Items are stored slim: only instance-specific data. All static fields (name,
# icon, type, base stats, etc.) are re-derived from the canonical .tres on the
# Godot side via `item_path`. `variant` holds per-instance overrides — either
# {"rarity", "bonus_stats"} for modified items (random rolls / crafting), or
# {"_full": <full item dict>} for items with no canonical resource.
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
    variant = db.Column(JSONB, nullable=True)

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
    variant = db.Column(JSONB, nullable=True)

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
    total_duration = db.Column(db.Float, default=0)
    stacks = db.Column(db.Integer, default=1)

# ==================== PER-PLAYER SAVE LOCKING ====================

_player_locks = {}
_lock_manager = threading.Lock()

def get_player_lock(username):
    with _lock_manager:
        if username not in _player_locks:
            _player_locks[username] = threading.Lock()
        return _player_locks[username]

# ==================== ITEM SERIALIZATION HELPERS ====================

def _build_item_data(item_path, item_id, variant, quantity):
    """Reconstructs the slim item dict the Godot client expects on load.
    `variant` may be None, {"rarity", "bonus_stats"} for modified items, or
    {"_full": <dict>} for items with no canonical resource."""
    if variant and '_full' in variant:
        return variant['_full']
    item_data = {
        "original_resource_path": item_path,
        "item_id": item_id,
    }
    if quantity is not None:
        item_data["current_stack_amount"] = quantity
    if variant:
        item_data.update(variant)
    return item_data


def _extract_variant(item_data, path):
    """Returns the variant blob to persist for an incoming item, or None for
    plain canonical items. Pathless items store the full dict so they can still
    be reconstructed without a backing resource."""
    if not path:
        return {'_full': item_data}
    if 'bonus_stats' in item_data:
        return {
            'rarity': item_data.get('rarity'),
            'bonus_stats': item_data.get('bonus_stats', {}),
        }
    return None


# ==================== BOT ACCOUNT ====================

# Bot characters have no player account, but Player.account_id is NOT NULL.
# All bots are owned by a single shared system account so they satisfy the FK
# while staying out of real players' character lists (those filter by account_id).
BOT_ACCOUNT_USERNAME = '__bots__'
_bot_account_id = None


def _ensure_bot_account():
    """Creates the shared bot account once, and caches its id."""
    global _bot_account_id
    account = Account.query.filter_by(username=BOT_ACCOUNT_USERNAME).first()
    if not account:
        # Not a valid password hash — check_password_hash always fails, so the
        # bot account can never be logged into.
        account = Account(username=BOT_ACCOUNT_USERNAME, password_hash='!no-login!')
        db.session.add(account)
        db.session.commit()
        print(f"Created shared bot account (id={account.id})")
    _bot_account_id = account.id
    return _bot_account_id


def _get_bot_account_id():
    """Returns the cached bot account id, resolving it lazily if needed."""
    if _bot_account_id is None:
        _ensure_bot_account()
    return _bot_account_id


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

    app.logger.info("ACCOUNT_REGISTERED: '%s' (account_id=%d)", username, new_account.id)
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
        app.logger.info("ACCOUNT_LOGIN_FAILED: '%s'", username)
        return jsonify({"error": "Invalid username or password"}), 401

    app.logger.info("ACCOUNT_LOGIN: '%s' (account_id=%d)", account.username, account.id)
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
        last_map="town",
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

    app.logger.info("CHARACTER_CREATED: '%s' (class_id=%d, account_id=%d)", char_name, class_id, account_id)
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
        
        # Reconstruct Inventory — slim dicts; Godot re-derives static fields
        # from the canonical .tres referenced by original_resource_path.
        inventory_slots = []
        for item in player.items:
            inventory_slots.append({
                "slot_index": item.slot_index,
                "item_data": _build_item_data(item.item_path, item.item_id, item.variant, item.quantity)
            })

        equipment_data = {}
        for eq in player.equipment:
            equipment_data[eq.slot_type] = _build_item_data(eq.item_path, eq.item_id, eq.variant, None)
            
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
                "total_duration": buff.total_duration or 0,
                "stacks": buff.stacks
            })
            
        response_data['buffs'] = {
            'active_buffs': active_buffs
        }

        # Quest progress (active, completed, onboarded). QuestManager.load_quests
        # treats an empty dict as "no save data" and falls through to defaults.
        response_data['quests'] = player.quests or {}

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
    is_bot = bool(content.get('is_bot', False))

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
            # Real players already have a Player row from character creation;
            # only bots reach here, and they're owned by the shared bot account.
            if not is_bot:
                return jsonify({"error": f"No character record for '{username}'"}), 404
            player = Player(username=username, account_id=_get_bot_account_id())
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
                quantity = item_data.get('current_stack_amount', 1)
                variant = _extract_variant(item_data, path)

                if slot_index in existing_items:
                    # UPDATE existing slot
                    item = existing_items[slot_index]
                    item.item_id = item_id
                    item.item_path = path
                    item.quantity = quantity
                    item.variant = variant
                else:
                    # INSERT new slot
                    db.session.add(PlayerItem(
                        player_username=username,
                        item_id=item_id,
                        slot_index=slot_index,
                        item_path=path,
                        quantity=quantity,
                        variant=variant,
                    ))

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
                variant = _extract_variant(item_data, path)

                if slot_type_str in existing_eq:
                    # UPDATE existing equipment slot
                    eq = existing_eq[slot_type_str]
                    eq.item_id = item_id
                    eq.item_path = path
                    eq.variant = variant
                else:
                    # INSERT new equipment slot
                    db.session.add(PlayerEquipment(
                        player_username=username,
                        item_id=item_id,
                        slot_type=slot_type_str,
                        item_path=path,
                        variant=variant,
                    ))

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
                    existing_buffs[bid].total_duration = buff.get('total_duration', 0)
                    existing_buffs[bid].stacks = buff.get('stacks', 1)
                else:
                    db.session.add(PlayerBuff(
                        player_username=username,
                        buff_id=bid,
                        duration=buff.get('remaining_duration'),
                        total_duration=buff.get('total_duration', 0),
                        stacks=buff.get('stacks', 1)
                    ))

            for bid in existing_buffs:
                if bid not in incoming_buff_ids:
                    db.session.delete(existing_buffs[bid])

        # Quests — opaque JSONB blob shaped by QuestManager.save_quests on the
        # Godot side. Only update if the client sent it (partial saves like
        # "stats"-only never include it), so we don't blank out the column.
        if 'quests' in data and isinstance(data['quests'], dict):
            player.quests = data['quests']

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
        ("player_buffs", "total_duration", "ALTER TABLE player_buffs ADD COLUMN total_duration FLOAT DEFAULT 0"),
        ("player_items", "variant", "ALTER TABLE player_items ADD COLUMN variant JSONB"),
        ("player_equipment", "variant", "ALTER TABLE player_equipment ADD COLUMN variant JSONB"),
        ("players", "quests", "ALTER TABLE players ADD COLUMN quests JSONB"),
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

    # Backfill `variant` from the legacy normalized columns before they are
    # dropped, so existing modified items (random rolls) keep their stats.
    # Godot discards variant data that matches the canonical resource on load,
    # so over-preserving unmodified items here is harmless.
    for table in ("player_items", "player_equipment"):
        try:
            db.session.execute(db.text(f"SELECT stats FROM {table} LIMIT 1"))
        except Exception:
            db.session.rollback()
            continue  # legacy columns already gone — nothing to backfill
        try:
            print(f"Migration: backfilling {table}.variant from legacy columns")
            db.session.execute(db.text(
                f"UPDATE {table} "
                f"SET variant = jsonb_build_object('rarity', rarity, 'bonus_stats', stats) "
                f"WHERE variant IS NULL "
                f"AND stats IS NOT NULL AND stats::text NOT IN ('{{}}', 'null')"
            ))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Migration: backfill failed for {table}: {e}")

    # Drop obsolete normalized item columns — superseded by the `variant` JSONB.
    # Item static fields are now re-derived from the canonical .tres in Godot.
    obsolete_columns = [
        (table, column)
        for table in ("player_items", "player_equipment")
        for column in ("name", "description", "icon_path", "item_type", "item_level",
                       "rarity", "custom_value", "equipment_type", "armor_type",
                       "weapon_type", "attack_speed", "stats")
    ]
    for table, column in obsolete_columns:
        try:
            db.session.execute(db.text(f"SELECT {column} FROM {table} LIMIT 1"))
        except Exception:
            db.session.rollback()
            continue  # column (or table) already absent
        try:
            print(f"Migration: dropping obsolete {table}.{column}")
            db.session.execute(db.text(f"ALTER TABLE {table} DROP COLUMN {column}"))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Migration: failed to drop {table}.{column}: {e}")


def init_db():
    """Initialize database with retry logic for Docker startup"""
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                db.create_all()
                _run_migrations()
                _ensure_bot_account()
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
