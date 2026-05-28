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
    __table_args__ = (
        # account_id drives the character-select query; Postgres does not
        # auto-index FK columns, so declare it explicitly.
        db.Index('idx_players_account_id', 'account_id'),
    )
    # Integer Primary Key (Auto-incrementing)
    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    # Foreign key to Account
    account_id = db.Column(db.Integer, db.ForeignKey('accounts.id'), nullable=False)
    # Username is unique and represents the CHARACTER NAME
    username = db.Column(db.String(255), unique=True, nullable=False)
    # Discriminates bot characters (negative peer id in-game, owned by the shared
    # __bots__ account) from real players, without resolving the magic account id.
    # Single-table inheritance: bots share the player save shape, so they stay in
    # this table with a discriminator rather than a parallel `bots` table.
    is_bot = db.Column(db.Boolean, nullable=False, server_default=db.text('false'), default=False)

    level = db.Column(db.Integer, default=1)
    character_class = db.Column(db.Integer, default=0)
    experience = db.Column(db.Integer, default=0)
    current_health = db.Column(db.Integer, default=100)
    max_health = db.Column(db.Integer, default=100)
    current_mana = db.Column(db.Integer, default=100)
    max_mana = db.Column(db.Integer, default=100)
    last_map = db.Column(db.String(255), default="town")
    monies = db.Column(db.Integer, default=0)
    # Legacy single-pool ability points. PR 4 replaced this with
    # `ability_points_per_discipline` (a JSONB dict keyed by lowercase weapon
    # discipline -- "sword" / "bow" / "staff" / "dagger"). The legacy column
    # stays populated as `sum(values)` for one release so older clients /
    # tools that still read it stay coherent. A later PR can drop it once
    # we're confident the new column round-trips reliably.
    ability_points = db.Column(db.Integer, default=0)
    # PR 4: per-weapon-discipline ability point pools. Dict shape:
    # `{"sword": <int>, "bow": <int>, "staff": <int>, "dagger": <int>}`.
    # NULL means "never persisted in the new shape" -- the load handler then
    # falls back to evenly distributing the legacy `ability_points` int across
    # the four disciplines on the Godot side (with the remainder going to the
    # character's starting discipline).
    ability_points_per_discipline = db.Column(JSONB, nullable=True)
    # PR 7: manually-allocated attribute points (New World style). JSONB dict
    # keyed by StatType int -> spent points {"0": STR, "2": DEX, "1": INT,
    # "3": LUCK, "15": CON}. Absent/empty => the Godot side default-allocates to
    # the starting weapon discipline's ratio on load (existing chars keep stats).
    attribute_points = db.Column(JSONB, nullable=True)
    # Per-player onboarding flag (formerly part of the quests blob). Quest
    # progress itself now lives in the relational `player_quests` table, so a
    # quest tick rewrites one row instead of a growing wholesale blob.
    onboarded = db.Column(db.Boolean, nullable=False, server_default=db.text('false'), default=False)
    # PetManager save blob: {roster: [<pet records>], summoned: [<uuids>]}.
    # Same wholesale-only pattern as quests — pet records are dictionaries
    # whose shape is owned by Godot (see pet_manager.gd / docs/adr/0001).
    # The endpoint flattens this into two top-level keys on the wire
    # ('pets', 'summoned_pet_ids') to match Godot's existing save shape.
    pets = db.Column(JSONB, nullable=True)
    # WeaponMasteryComponent.save_mastery blob: {sword: {level, xp}, bow: ...,
    # staff: ..., dagger: ...}. Per-discipline mastery progression introduced
    # by PR 2 of the weapon-identity-overhaul. Wholesale only — the Godot
    # component owns the shape and rewrites the whole dict on save.
    # NULL on existing rows → loads as an empty dict in Godot, which
    # _ensure_default_disciplines fills in with four zero-state entries.
    weapon_mastery = db.Column(JSONB, nullable=True)
    updated_at = db.Column(db.DateTime, server_default=db.func.now(), onupdate=db.func.now())

    # Relationships. passive_deletes=True defers child cleanup to the DB's
    # ON DELETE CASCADE (declared on each child FK) instead of emitting a DELETE
    # per child row from the ORM.
    items = db.relationship('PlayerItem', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerItem.player_username', primaryjoin="Player.username==PlayerItem.player_username", passive_deletes=True)
    equipment = db.relationship('PlayerEquipment', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerEquipment.player_username', primaryjoin="Player.username==PlayerEquipment.player_username", passive_deletes=True)
    abilities = db.relationship('PlayerAbility', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerAbility.player_username', primaryjoin="Player.username==PlayerAbility.player_username", passive_deletes=True)
    hotbar = db.relationship('PlayerHotbar', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerHotbar.player_username', primaryjoin="Player.username==PlayerHotbar.player_username", passive_deletes=True)
    buffs = db.relationship('PlayerBuff', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerBuff.player_username', primaryjoin="Player.username==PlayerBuff.player_username", passive_deletes=True)
    quest_entries = db.relationship('PlayerQuest', backref='player', cascade="all, delete-orphan", foreign_keys='PlayerQuest.player_username', primaryjoin="Player.username==PlayerQuest.player_username", passive_deletes=True)

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
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
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
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
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
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
    ability_id = db.Column(db.String(255))
    level = db.Column(db.Integer, default=1)
    # PR 6: purchased upgrade ids for THIS ability — co-located with the ability
    # row instead of a parallel players.learned_ability_upgrades blob keyed by the
    # same ability_id. Small bounded list (the 3-tier upgrade tree). NULL = none.
    # uq_playerability_id guarantees exactly one upgrade list per owned ability.
    upgrades = db.Column(JSONB, nullable=True)

class PlayerHotbar(db.Model):
    __tablename__ = 'player_hotbar'
    __table_args__ = (
        db.Index('idx_playerhotbar_username', 'player_username'),
        db.UniqueConstraint('player_username', 'slot_index', name='uq_playerhotbar_slot'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
    slot_index = db.Column(db.Integer)
    ability_id = db.Column(db.String(255))

class PlayerBuff(db.Model):
    __tablename__ = 'player_buffs'
    __table_args__ = (
        db.Index('idx_playerbuff_username', 'player_username'),
        # Buff sync keys on buff_id; enforce it so a duplicate can't orphan a row.
        db.UniqueConstraint('player_username', 'buff_id', name='uq_playerbuff_id'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
    buff_id = db.Column(db.String(255))
    duration = db.Column(db.Float)
    total_duration = db.Column(db.Float, default=0)
    stacks = db.Column(db.Integer, default=1)

# Quest progress, one row per (player, quest). Splitting active vs. completed
# into rows means a quest-progress tick updates a single row instead of
# rewriting a growing {active, completed, tracked} blob on the players row.
class PlayerQuest(db.Model):
    __tablename__ = 'player_quests'
    __table_args__ = (
        db.Index('idx_playerquest_username', 'player_username'),
        db.UniqueConstraint('player_username', 'quest_id', name='uq_playerquest_id'),
    )
    id = db.Column(db.Integer, primary_key=True)
    player_username = db.Column(db.String(255), db.ForeignKey('players.username', ondelete='CASCADE'))
    quest_id = db.Column(db.String(255))
    # 'active' | 'completed'. Active rows carry objective progress; completed
    # rows are stable history that no longer gets rewritten on each tick.
    status = db.Column(db.String(16))
    # Objective progress for active quests: {objective_index: count}. NULL once
    # completed. Keys arrive as JSON strings; QuestManager re-ints them on load.
    progress = db.Column(JSONB, nullable=True)
    # UI pin state (a small subset of active quests).
    tracked = db.Column(db.Boolean, nullable=False, server_default=db.text('false'), default=False)

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


def _sync_child_rows(model, existing_by_key, desired_by_key):
    """Generic insert/update/delete-by-key sync for a player's child rows.

    existing_by_key: {key: orm_row} for the rows currently in the DB.
    desired_by_key:  {key: {column: value, ...}} for the incoming state; each
                     value dict carries the full column set for an INSERT
                     (including player_username and the key column).

    Updates rows present in both, inserts rows only in `desired`, deletes rows
    only in `existing`. Replaces five hand-rolled copies of this loop."""
    for key, fields in desired_by_key.items():
        row = existing_by_key.get(key)
        if row is not None:
            for col, val in fields.items():
                setattr(row, col, val)
        else:
            db.session.add(model(**fields))
    for key, row in existing_by_key.items():
        if key not in desired_by_key:
            db.session.delete(row)


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
        max_mana=100
    )
    
    db.session.add(new_player)
    db.session.commit()

    app.logger.info("CHARACTER_CREATED: '%s' (class_id=%d, account_id=%d)", char_name, class_id, account_id)
    return jsonify({"message": "Character created", "name": char_name}), 201


@app.route('/api/character/delete', methods=['POST'])
def delete_character():
    content = request.json
    account_id = content.get('account_id')
    char_name = content.get('name')

    if not account_id or not char_name:
        return jsonify({"error": "Account ID and character name required"}), 400

    player = Player.query.filter_by(username=char_name, account_id=account_id).first()
    if not player:
        return jsonify({"error": "Character not found"}), 404

    # Serialize against any in-flight save for this character before deletion.
    lock = get_player_lock(char_name)
    if not lock.acquire(timeout=5):
        return jsonify({"error": "Save in progress"}), 429

    try:
        db.session.delete(player)
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        app.logger.warning("CHARACTER_DELETE_FAILED: '%s' (account_id=%d): %s", char_name, account_id, e)
        return jsonify({"error": "Delete failed", "details": str(e)}), 500
    finally:
        lock.release()

    app.logger.info("CHARACTER_DELETED: '%s' (account_id=%d)", char_name, account_id)
    return jsonify({"message": "Character deleted", "name": char_name}), 200


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
        joinedload(Player.quest_entries),
    ).filter_by(username=username).first()

    if player:
        # Reconstruct JSON structure for Godot
        response_data = {
            'username': player.username,
            'level': player.level,
            'character_type': player.character_class,
            'attribute_points': player.attribute_points or {},
            'experience': player.experience,
            'current_health': player.current_health,
            'max_health': player.max_health,
            'current_mana': player.current_mana,
            'max_mana': player.max_mana,
            'last_map': player.last_map,
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
        
        # PR 4: emit the per-discipline pool dict. Godot's load_abilities
        # migrates an empty/missing dict by evenly distributing the legacy
        # `available_points` int across the four disciplines. We also keep
        # the legacy key on the wire as a safety fallback for one release.
        response_data['abilities'] = {
            'available_points': player.ability_points if player.ability_points is not None else 0,
            'available_points_per_discipline': player.ability_points_per_discipline or {},
            'ability_levels': ability_levels,
            # PR 6: rebuilt from each ability's own `upgrades` column (was a single
            # players.learned_ability_upgrades blob keyed by ability_id). The wire
            # shape {ability_id: [upgrade_id,...]} is unchanged, so Godot is unaffected.
            'learned_ability_upgrades': {ab.ability_id: ab.upgrades for ab in player.abilities if ab.upgrades},
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

        # Quest progress — rebuild the {active, completed, tracked, onboarded}
        # wire shape QuestManager.load_quests expects from the per-quest rows +
        # the onboarded flag (was a single players.quests blob).
        q_active = {}
        q_completed = []
        q_tracked = []
        for q in player.quest_entries:
            if q.status == 'completed':
                q_completed.append(q.quest_id)
            else:
                q_active[q.quest_id] = q.progress or {}
                if q.tracked:
                    q_tracked.append(q.quest_id)
        response_data['quests'] = {
            'active': q_active,
            'completed': q_completed,
            'tracked': q_tracked,
            'onboarded': player.onboarded,
        }

        # Pet roster — flatten the {roster, summoned} blob back into the two
        # top-level keys the Godot player save expects.
        pets_blob = player.pets or {}
        response_data['pets'] = pets_blob.get('roster', [])
        response_data['summoned_pet_ids'] = pets_blob.get('summoned', [])

        # Weapon mastery (PR 2). NULL on the row -> empty dict on the wire;
        # WeaponMasteryComponent._ensure_default_disciplines fills in the
        # four zero-state tier-1 entries so existing characters load cleanly.
        response_data['weapon_mastery'] = player.weapon_mastery or {}

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
            player = Player(username=username, account_id=_get_bot_account_id(), is_bot=True)
            db.session.add(player)

        # Update Core Stats
        if 'level' in data: player.level = data['level']
        if 'character_type' in data: player.character_class = data['character_type']
        if 'attribute_points' in data: player.attribute_points = data['attribute_points']
        if 'experience' in data: player.experience = data['experience']
        if 'current_health' in data: player.current_health = data['current_health']
        if 'max_health' in data: player.max_health = data['max_health']
        if 'current_mana' in data: player.current_mana = data['current_mana']
        if 'max_mana' in data: player.max_mana = data['max_mana']
        if 'last_map' in data: player.last_map = data['last_map']

        # Update Inventory
        if 'inventory' in data:
            inv_data = data['inventory']
            player.monies = inv_data.get('monies', 0)

            # Items, keyed by slot_index.
            desired_items = {}
            for slot in inv_data.get('slots', []):
                slot_index = slot.get('slot_index')
                if slot_index is None:
                    continue
                item_data = slot.get('item_data', {})
                path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
                desired_items[slot_index] = dict(
                    player_username=username,
                    slot_index=slot_index,
                    item_id=item_data.get('item_id'),
                    item_path=path,
                    quantity=item_data.get('current_stack_amount', 1),
                    variant=_extract_variant(item_data, path),
                )
            _sync_child_rows(PlayerItem, {it.slot_index: it for it in player.items}, desired_items)

            # Equipment, keyed by slot_type.
            desired_eq = {}
            for slot_type, item_data in inv_data.get('equipment', {}).items():
                st = str(slot_type)
                path = item_data.get('original_resource_path') or item_data.get('resource_path') or ""
                desired_eq[st] = dict(
                    player_username=username,
                    slot_type=st,
                    item_id=item_data.get('item_id'),
                    item_path=path,
                    variant=_extract_variant(item_data, path),
                )
            _sync_child_rows(PlayerEquipment, {eq.slot_type: eq for eq in player.equipment}, desired_eq)

        # --- Fix 3: UPSERT for Abilities ---
        if 'abilities' in data:
            ab_data = data['abilities']

            # Save ability points. PR 4: prefer the per-discipline dict; the
            # legacy single-int `available_points` is written through as
            # `sum(values)` for one release as a safety fallback. If only the
            # legacy key is present (older clients pre-rollout, or a partial
            # save written before the migration ran), distribute it evenly
            # into the JSONB dict so the next load round-trips cleanly.
            if 'available_points_per_discipline' in ab_data:
                per_disc = ab_data.get('available_points_per_discipline') or {}
                # Coerce to ints defensively -- JSON ints can arrive as floats.
                per_disc = {str(k): int(v) for k, v in per_disc.items() if v is not None}
                player.ability_points_per_discipline = per_disc
                player.ability_points = sum(per_disc.values())
            elif 'available_points' in ab_data:
                legacy_total = int(ab_data['available_points'] or 0)
                player.ability_points = legacy_total
                # Server-side migration safety net: split the legacy int evenly
                # across the four disciplines so the next load already has the
                # new shape persisted. Remainder goes to "sword" -- the Godot
                # client overrides this on the very next save with its own
                # starting-discipline-weighted distribution.
                base = legacy_total // 4
                remainder = legacy_total - (base * 4)
                player.ability_points_per_discipline = {
                    "sword": base + remainder,
                    "bow": base,
                    "staff": base,
                    "dagger": base,
                }

            # Abilities, keyed by ability_id. PR 6: each ability's purchased
            # upgrades now ride on its own row (was a separate players blob). The
            # {ability_id: [upgrade_id,...]} wire map is unchanged. Only touch the
            # upgrades column when the client actually sent the key, so a save
            # that omits it (older clients) never wipes existing upgrades.
            has_upgrades_key = 'learned_ability_upgrades' in ab_data
            incoming_upgrades = ab_data.get('learned_ability_upgrades', {}) or {}
            desired_abilities = {}
            for ab_id, level in ab_data.get('ability_levels', {}).items():
                fields = dict(player_username=username, ability_id=ab_id, level=level)
                if has_upgrades_key:
                    fields['upgrades'] = incoming_upgrades.get(ab_id) or None
                desired_abilities[ab_id] = fields
            _sync_child_rows(PlayerAbility, {a.ability_id: a for a in player.abilities}, desired_abilities)

            # Hotbar, keyed by str(slot_index).
            desired_hotbar = {}
            for slot, ab_id in ab_data.get('hotbar_config', {}).items():
                desired_hotbar[str(slot)] = dict(
                    player_username=username,
                    slot_index=int(slot),
                    ability_id=ab_id,
                )
            _sync_child_rows(PlayerHotbar, {str(hb.slot_index): hb for hb in player.hotbar}, desired_hotbar)

        # --- UPSERT for Buffs (keyed by buff_id; uq_playerbuff_id enforces it) ---
        if 'buffs' in data:
            desired_buffs = {}
            for buff in data['buffs'].get('active_buffs', []):
                bid = buff.get('buff_id')
                if not bid:
                    continue
                desired_buffs[bid] = dict(
                    player_username=username,
                    buff_id=bid,
                    duration=buff.get('remaining_duration'),
                    total_duration=buff.get('total_duration', 0),
                    stacks=buff.get('stacks', 1),
                )
            _sync_child_rows(PlayerBuff, {b.buff_id: b for b in player.buffs}, desired_buffs)

        # Quests — destructure the {active, completed, tracked, onboarded} wire
        # shape into per-quest rows + the onboarded flag. Only when the client
        # sent it (partial saves never include it), so we don't wipe progress.
        if 'quests' in data and isinstance(data['quests'], dict):
            q = data['quests']
            player.onboarded = bool(q.get('onboarded', False))
            tracked_set = {str(t) for t in (q.get('tracked', []) or [])}
            desired_quests = {}
            for qid, progress in (q.get('active', {}) or {}).items():
                desired_quests[str(qid)] = dict(
                    player_username=username,
                    quest_id=str(qid),
                    status='active',
                    progress=progress,
                    tracked=(str(qid) in tracked_set),
                )
            for qid in (q.get('completed', []) or []):
                desired_quests[str(qid)] = dict(
                    player_username=username,
                    quest_id=str(qid),
                    status='completed',
                    progress=None,
                    tracked=False,
                )
            _sync_child_rows(PlayerQuest, {pq.quest_id: pq for pq in player.quest_entries}, desired_quests)

        # Pets — Godot sends the roster as the flat 'pets' top-level key plus
        # 'summoned_pet_ids' (see multiplayer_controller_v2.get_save_data). We
        # bundle them into one JSONB column. Only touch the column when EITHER
        # key is present in the payload, so partial saves don't clobber it.
        # When only one of the two keys arrives, preserve the other from the
        # existing row.
        if 'pets' in data or 'summoned_pet_ids' in data:
            existing_pets = player.pets or {}
            new_roster = data.get('pets', existing_pets.get('roster', []))
            new_summoned = data.get('summoned_pet_ids', existing_pets.get('summoned', []))
            player.pets = {'roster': new_roster, 'summoned': new_summoned}

        # Weapon mastery (PR 2). Opaque blob owned by Godot's
        # WeaponMasteryComponent.save_mastery. Only update if the client sent
        # it (a partial "stats"-shape save DOES include it, since mastery
        # piggybacks on the stats update path).
        if 'weapon_mastery' in data and isinstance(data['weapon_mastery'], dict):
            player.weapon_mastery = data['weapon_mastery']

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


def _ensure_cascade_fk(table):
    """Ensure {table}.player_username FK has ON DELETE CASCADE. Idempotent:
    skips when already cascade ('c'); recreates the constraint otherwise."""
    fk = f"{table}_player_username_fkey"
    try:
        row = db.session.execute(db.text(
            "SELECT confdeltype FROM pg_constraint WHERE conname = :n"
        ), {"n": fk}).fetchone()
        if row is None or row[0] == 'c':
            return  # constraint absent (fresh DB already cascades) or already cascade
        db.session.execute(db.text(f"ALTER TABLE {table} DROP CONSTRAINT {fk}"))
        db.session.execute(db.text(
            f"ALTER TABLE {table} ADD CONSTRAINT {fk} "
            f"FOREIGN KEY (player_username) REFERENCES players(username) ON DELETE CASCADE"
        ))
        db.session.commit()
        print(f"Migration: {fk} -> ON DELETE CASCADE")
    except Exception as e:
        db.session.rollback()
        print(f"Migration: failed to set cascade on {table}: {e}")


def _check_schema_drift():
    """Log (not crash) any divergence between the SQLAlchemy models and the live
    DB columns, so the 'process running an older schema than app.py' failure mode
    is loud at boot instead of silently dropping fields."""
    drift = False
    for table_name, table in db.metadata.tables.items():
        rows = db.session.execute(db.text(
            "SELECT column_name FROM information_schema.columns "
            "WHERE table_schema = 'public' AND table_name = :t"
        ), {"t": table_name}).fetchall()
        db_cols = {r[0] for r in rows}
        if not db_cols:
            app.logger.warning("SCHEMA_DRIFT: model table '%s' is missing from the DB", table_name)
            drift = True
            continue
        model_cols = {c.name for c in table.columns}
        missing = model_cols - db_cols
        extra = db_cols - model_cols
        if missing:
            app.logger.warning("SCHEMA_DRIFT: %s missing in DB: %s", table_name, sorted(missing))
            drift = True
        if extra:
            app.logger.warning("SCHEMA_DRIFT: %s extra in DB (not in model): %s", table_name, sorted(extra))
            drift = True
    if not drift:
        app.logger.info("Schema check: models and DB columns are in sync.")


def _run_migrations():
    """Add columns that may be missing from older database schemas."""
    migrations = [
        ("players", "current_mana", "ALTER TABLE players ADD COLUMN current_mana INTEGER DEFAULT 100"),
        ("players", "max_mana",     "ALTER TABLE players ADD COLUMN max_mana INTEGER DEFAULT 100"),
        ("player_buffs", "total_duration", "ALTER TABLE player_buffs ADD COLUMN total_duration FLOAT DEFAULT 0"),
        ("player_items", "variant", "ALTER TABLE player_items ADD COLUMN variant JSONB"),
        ("player_equipment", "variant", "ALTER TABLE player_equipment ADD COLUMN variant JSONB"),
        ("players", "pets",   "ALTER TABLE players ADD COLUMN pets JSONB"),
        # PR 2 of the weapon-identity-overhaul: per-discipline mastery.
        # Shape is {sword: {level, xp}, bow: {...}, staff: {...}, dagger: {...}}.
        ("players", "weapon_mastery", "ALTER TABLE players ADD COLUMN weapon_mastery JSONB"),
        # PR 4: per-weapon-discipline ability-point pools (Sword / Bow /
        # Staff / Dagger). Replaces the single-pool `ability_points` int,
        # which stays populated as a fallback for one release.
        ("players", "ability_points_per_discipline",
         "ALTER TABLE players ADD COLUMN ability_points_per_discipline JSONB"),
        # PR 7: manually-allocated attribute points (New World style). JSONB dict
        # keyed by StatType int -> spent points.
        ("players", "attribute_points",
         "ALTER TABLE players ADD COLUMN attribute_points JSONB"),
        # Persistence cleanup: per-ability upgrades column (replaces the
        # players.learned_ability_upgrades blob — backfilled + dropped below) and
        # the is_bot discriminator (backfilled from the __bots__ account below).
        ("player_abilities", "upgrades",
         "ALTER TABLE player_abilities ADD COLUMN upgrades JSONB"),
        ("players", "is_bot",
         "ALTER TABLE players ADD COLUMN is_bot BOOLEAN NOT NULL DEFAULT FALSE"),
        # Quests relocated to the player_quests table; onboarded is the only
        # per-player quest field that stays on the players row.
        ("players", "onboarded",
         "ALTER TABLE players ADD COLUMN onboarded BOOLEAN NOT NULL DEFAULT FALSE"),
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

    # ── Persistence cleanup migrations ──────────────────────────────────────

    # Relocate the players.learned_ability_upgrades blob ({ability_id: [...]})
    # into per-ability player_abilities.upgrades rows, then drop the blob.
    try:
        db.session.execute(db.text("SELECT learned_ability_upgrades FROM players LIMIT 1"))
        _has_upgrade_blob = True
    except Exception:
        db.session.rollback()
        _has_upgrade_blob = False
    if _has_upgrade_blob:
        try:
            print("Migration: backfilling player_abilities.upgrades from players.learned_ability_upgrades")
            db.session.execute(db.text(
                "UPDATE player_abilities pa "
                "SET upgrades = p.learned_ability_upgrades -> pa.ability_id "
                "FROM players p "
                "WHERE p.username = pa.player_username "
                "AND p.learned_ability_upgrades IS NOT NULL "
                "AND p.learned_ability_upgrades ? pa.ability_id"
            ))
            db.session.commit()
            print("Migration: dropping players.learned_ability_upgrades (moved onto player_abilities)")
            db.session.execute(db.text("ALTER TABLE players DROP COLUMN learned_ability_upgrades"))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Migration: learned_ability_upgrades relocation failed: {e}")

    # Relocate the players.quests blob ({active, completed, tracked, onboarded})
    # into relational player_quests rows + the players.onboarded flag, then drop
    # the blob. Splitting active/completed into rows avoids rewriting a growing
    # completed-quest list on every quest tick.
    try:
        db.session.execute(db.text("SELECT quests FROM players LIMIT 1"))
        _has_quests_blob = True
    except Exception:
        db.session.rollback()
        _has_quests_blob = False
    if _has_quests_blob:
        try:
            print("Migration: backfilling player_quests + players.onboarded from players.quests")
            db.session.execute(db.text(
                "UPDATE players SET onboarded = COALESCE((quests ->> 'onboarded')::boolean, false) "
                "WHERE quests IS NOT NULL"
            ))
            db.session.execute(db.text(
                "INSERT INTO player_quests (player_username, quest_id, status, progress, tracked) "
                "SELECT p.username, kv.key, 'active', kv.value, "
                "       COALESCE(jsonb_exists(p.quests -> 'tracked', kv.key), false) "
                "FROM players p, jsonb_each(p.quests -> 'active') kv "
                "WHERE p.quests IS NOT NULL AND jsonb_typeof(p.quests -> 'active') = 'object' "
                "ON CONFLICT (player_username, quest_id) DO NOTHING"
            ))
            db.session.execute(db.text(
                "INSERT INTO player_quests (player_username, quest_id, status, progress, tracked) "
                "SELECT p.username, ce.value #>> '{}', 'completed', NULL, false "
                "FROM players p, jsonb_array_elements(p.quests -> 'completed') ce "
                "WHERE p.quests IS NOT NULL AND jsonb_typeof(p.quests -> 'completed') = 'array' "
                "ON CONFLICT (player_username, quest_id) DO NOTHING"
            ))
            db.session.commit()
            print("Migration: dropping players.quests (moved into player_quests)")
            db.session.execute(db.text("ALTER TABLE players DROP COLUMN quests"))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Migration: quests relocation failed: {e}")

    # Backfill the is_bot discriminator from the shared __bots__ account.
    try:
        db.session.execute(db.text(
            "UPDATE players SET is_bot = TRUE "
            "WHERE is_bot = FALSE "
            "AND account_id = (SELECT id FROM accounts WHERE username = '__bots__')"
        ))
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        print(f"Migration: is_bot backfill failed: {e}")

    # Drop party_id — ephemeral runtime party state, never read back on load.
    try:
        db.session.execute(db.text("SELECT party_id FROM players LIMIT 1"))
    except Exception:
        db.session.rollback()
    else:
        try:
            print("Migration: dropping players.party_id (ephemeral runtime state)")
            db.session.execute(db.text("ALTER TABLE players DROP COLUMN party_id"))
            db.session.commit()
        except Exception as e:
            db.session.rollback()
            print(f"Migration: failed to drop players.party_id: {e}")

    # player_buffs lacked the per-(player, buff) unique constraint its sibling
    # tables have; add it (dedupe defensively first, though none are expected).
    try:
        _has_uq = db.session.execute(db.text(
            "SELECT 1 FROM pg_constraint WHERE conname = 'uq_playerbuff_id'"
        )).fetchone()
        if not _has_uq:
            db.session.execute(db.text(
                "DELETE FROM player_buffs a USING player_buffs b "
                "WHERE a.id < b.id AND a.player_username = b.player_username "
                "AND a.buff_id = b.buff_id"
            ))
            db.session.execute(db.text(
                "ALTER TABLE player_buffs ADD CONSTRAINT uq_playerbuff_id "
                "UNIQUE (player_username, buff_id)"
            ))
            db.session.commit()
            print("Migration: added uq_playerbuff_id on player_buffs")
    except Exception as e:
        db.session.rollback()
        print(f"Migration: failed to add uq_playerbuff_id: {e}")

    # account_id powers the character-select query but Postgres doesn't
    # auto-index FK columns. Idempotent; matches the name the model declares.
    try:
        db.session.execute(db.text(
            "CREATE INDEX IF NOT EXISTS idx_players_account_id ON players(account_id)"
        ))
        db.session.commit()
    except Exception as e:
        db.session.rollback()
        print(f"Migration: failed to create idx_players_account_id: {e}")

    # Give every child FK ON DELETE CASCADE so deleting a player (or any
    # out-of-ORM delete) cleans up its rows at the DB level instead of erroring.
    for _tbl in ("player_items", "player_equipment", "player_abilities",
                 "player_hotbar", "player_buffs", "player_quests"):
        _ensure_cascade_fk(_tbl)


def init_db():
    """Initialize database with retry logic for Docker startup"""
    retries = 5
    while retries > 0:
        try:
            with app.app_context():
                db.create_all()
                _run_migrations()
                _ensure_bot_account()
                _check_schema_drift()
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
