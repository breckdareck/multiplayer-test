extends Node
## PetManager — server-authoritative ownership of player pets.
##
## See docs/adr/0001-pet-system-architecture.md for the full architectural
## rationale. In short:
##   - Each pet is owner-bound and tied to a player character (per-character,
##     not account-shared).
##   - The owner's client drives auto-loot and auto-pot trigger loops via
##     existing server-validated RPCs; PetManager runs the auto-buff timer.
##   - Pet records persist to the per-character save JSON via SaveManager.
##   - Bots cannot own pets (no client to run the trigger loops).
##
## This Phase-1 file is a scaffold. Spawning, follow logic, auto-actions, and
## UI integration arrive in later phases.

# ── Save-format constants (canonical pet record keys) ─────────────────────
const KEY_PETS := "pets"
const KEY_SUMMONED := "summoned_pet_ids"

# Per-pet record keys
const KEY_ID := "id"
const KEY_PET_DATA_ID := "pet_data_id"
const KEY_NAME := "name"
const KEY_HUNGER := "hunger"
const KEY_LEARNED := "learned_commands"
const KEY_ACTIVE_BUFF := "active_buff_ability_id"
const KEY_INVENTORY := "pet_inventory"
const KEY_AUTOPOT_CONFIG := "autopot_config"

# Pet inventory sub-keys
const KEY_AUTOPOT_HP := "autopot_hp_slot"
const KEY_AUTOPOT_MP := "autopot_mp_slot"
const KEY_STORAGE := "storage_slots"
const STORAGE_SLOT_COUNT := 3

# Autopot config sub-keys
const KEY_HP_THRESHOLD := "hp_threshold"
const KEY_MP_THRESHOLD := "mp_threshold"

# Known command ids (PetSkillBookData.command_id values that PetManager recognises)
const CMD_AUTO_POT := "auto_pot"
const CMD_ITEM_POUCH := "item_pouch"
const CMD_MESO_MAGNET := "meso_magnet"
const CMD_AUTOBUFF := "autobuff"


# ── Per-player roster ─────────────────────────────────────────────────────
## username -> { pets: Array[Dictionary], summoned_pet_ids: Array[String] }
## Pet records are plain Dictionaries (see KEY_* constants above).
## Server-side only — clients never read this directly.
var _rosters: Dictionary = {}

## pet_uuid -> { record, owner_username, pet_node (or null), ...runtime state }
## Only contains entries for currently summoned pets on the server. Cleared on
## despawn. Spawn/despawn logic arrives in Phase 2.
var _active_pets: Dictionary = {}


func _ready() -> void:
	# Server-only manager. Bots have no client and cannot own pets, but the
	# manager still runs server-side for human players.
	if not multiplayer.has_multiplayer_peer():
		# In single-player editor runs the multiplayer peer isn't set yet —
		# defer initialization until MultiplayerManager finishes startup.
		return


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════

## Server-side: produce the pets save payload for a given character.
## Returns { pets: [...], summoned_pet_ids: [...] }.
## Callers (multiplayer_controller_v2.get_save_data) just merge this in.
func get_save_data(username: String) -> Dictionary:
	if not _rosters.has(username):
		return {KEY_PETS: [], KEY_SUMMONED: []}
	var roster: Dictionary = _rosters[username]
	# Deep-copy the pet records so subsequent mutations don't poison the
	# in-flight save payload.
	var pets_copy: Array = []
	for pet in roster.get(KEY_PETS, []):
		pets_copy.append(_clone_record(pet))
	var summoned_copy: Array = (roster.get(KEY_SUMMONED, []) as Array).duplicate()
	return {
		KEY_PETS: pets_copy,
		KEY_SUMMONED: summoned_copy,
	}


## Server-side: load a character's pet roster from save data.
## `data` is the dict from get_save_data() — may be empty for new characters.
func load_pets(username: String, data: Dictionary) -> void:
	var pets: Array = data.get(KEY_PETS, [])
	var summoned: Array = data.get(KEY_SUMMONED, [])

	# Sanity: each pet record must be a Dictionary with at minimum an id.
	var clean_pets: Array = []
	for pet in pets:
		if pet is Dictionary and pet.get(KEY_ID, "") != "":
			clean_pets.append(_normalize_record(pet))

	# Sanity: summoned ids must reference loaded pets.
	var pet_ids := {}
	for pet in clean_pets:
		pet_ids[pet[KEY_ID]] = true
	var clean_summoned: Array = []
	for sid in summoned:
		if sid is String and pet_ids.has(sid):
			clean_summoned.append(sid)

	_rosters[username] = {
		KEY_PETS: clean_pets,
		KEY_SUMMONED: clean_summoned,
	}


## Server-side: clear the roster on disconnect / unregister.
func clear_player(username: String) -> void:
	_rosters.erase(username)


# ═══════════════════════════════════════════════════════════════════════════
# ROSTER QUERIES (server-side reads)
# ═══════════════════════════════════════════════════════════════════════════

func get_roster(username: String) -> Array:
	if not _rosters.has(username):
		return []
	return _rosters[username].get(KEY_PETS, [])


func get_summoned_ids(username: String) -> Array:
	if not _rosters.has(username):
		return []
	return _rosters[username].get(KEY_SUMMONED, [])


func find_pet(username: String, pet_uuid: String) -> Dictionary:
	for pet in get_roster(username):
		if pet.get(KEY_ID, "") == pet_uuid:
			return pet
	return {}


# ═══════════════════════════════════════════════════════════════════════════
# RECORD HELPERS
# ═══════════════════════════════════════════════════════════════════════════

## Build a fresh pet record dictionary with v1 defaults.
static func make_pet_record(pet_data_id: String, custom_name: String) -> Dictionary:
	return {
		KEY_ID: _new_uuid(),
		KEY_PET_DATA_ID: pet_data_id,
		KEY_NAME: custom_name,
		KEY_HUNGER: 100.0,
		KEY_LEARNED: [],
		KEY_ACTIVE_BUFF: "",
		KEY_INVENTORY: {
			KEY_AUTOPOT_HP: {},
			KEY_AUTOPOT_MP: {},
			KEY_STORAGE: _empty_storage(),
		},
		KEY_AUTOPOT_CONFIG: {
			KEY_HP_THRESHOLD: 0.5,
			KEY_MP_THRESHOLD: 0.5,
		},
	}


static func _empty_storage() -> Array:
	var arr: Array = []
	arr.resize(STORAGE_SLOT_COUNT)
	for i in STORAGE_SLOT_COUNT:
		arr[i] = {}
	return arr


## Fill in defaults for any keys missing from a loaded record — protects
## against forward-compatible saves and old saves that pre-date new fields.
static func _normalize_record(record: Dictionary) -> Dictionary:
	var out := record.duplicate(true)
	if not out.has(KEY_HUNGER):
		out[KEY_HUNGER] = 100.0
	if not out.has(KEY_LEARNED):
		out[KEY_LEARNED] = []
	if not out.has(KEY_ACTIVE_BUFF):
		out[KEY_ACTIVE_BUFF] = ""
	if not out.has(KEY_INVENTORY):
		out[KEY_INVENTORY] = {
			KEY_AUTOPOT_HP: {},
			KEY_AUTOPOT_MP: {},
			KEY_STORAGE: _empty_storage(),
		}
	else:
		var inv: Dictionary = out[KEY_INVENTORY]
		if not inv.has(KEY_AUTOPOT_HP):
			inv[KEY_AUTOPOT_HP] = {}
		if not inv.has(KEY_AUTOPOT_MP):
			inv[KEY_AUTOPOT_MP] = {}
		if not inv.has(KEY_STORAGE):
			inv[KEY_STORAGE] = _empty_storage()
	if not out.has(KEY_AUTOPOT_CONFIG):
		out[KEY_AUTOPOT_CONFIG] = {
			KEY_HP_THRESHOLD: 0.5,
			KEY_MP_THRESHOLD: 0.5,
		}
	return out


static func _clone_record(record: Dictionary) -> Dictionary:
	return record.duplicate(true)


static func _new_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32))
	]
