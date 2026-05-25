extends Node
## PetManager — server-authoritative ownership of player pets.
##
## See docs/adr/0001-pet-system-architecture.md for the architectural rationale.
##   - Owner-bound, per-character (not account-shared).
##   - The owner's client drives auto-loot and auto-pot trigger loops via
##     existing server-validated RPCs; PetManager runs the auto-buff timer.
##   - Bots cannot own pets (no client).
##
## Phase 2 adds: PetData registry, pet entity spawn/despawn, egg hatch flow,
## and re-spawn on map / channel change.

const PET_SCENE: PackedScene = preload("res://scenes/Pet/pet.tscn")
const PET_DATA_FOLDER: String = "res://resources/PetSystem/Pets/"

# ── Save-format constants (canonical pet record keys) ─────────────────────
const KEY_PETS := "pets"
const KEY_SUMMONED := "summoned_pet_ids"

const KEY_ID := "id"
const KEY_PET_DATA_ID := "pet_data_id"
const KEY_NAME := "name"
const KEY_HUNGER := "hunger"
const KEY_LEARNED := "learned_commands"
const KEY_ACTIVE_BUFF := "active_buff_ability_id"
const KEY_INVENTORY := "pet_inventory"
const KEY_AUTOPOT_CONFIG := "autopot_config"

const KEY_AUTOPOT_HP := "autopot_hp_slot"
const KEY_AUTOPOT_MP := "autopot_mp_slot"
const KEY_STORAGE := "storage_slots"
const STORAGE_SLOT_COUNT := 3

const KEY_HP_THRESHOLD := "hp_threshold"
const KEY_MP_THRESHOLD := "mp_threshold"

const CMD_AUTO_POT := "auto_pot"
const CMD_ITEM_POUCH := "item_pouch"
const CMD_MESO_MAGNET := "meso_magnet"
const CMD_AUTOBUFF := "autobuff"

# v1: only 1 pet active at a time. Increase to support multi-pet later.
const MAX_ACTIVE_PETS: int = 1

# Signals — clients listen for UI hooks.
signal pet_hatched(pet_uuid: String, pet_name: String, pet_data_id: String)
signal pet_summoned(pet_uuid: String)
signal pet_unsummoned(pet_uuid: String)
signal pet_roster_changed()

# ── Server-side state ─────────────────────────────────────────────────────
## username -> { pets: Array[Dictionary], summoned_pet_ids: Array[String] }
var _rosters: Dictionary = {}

## pet_uuid -> { pet_node, owner_username, owner_peer_id, map_id, pet_data_id }
var _active_pets: Dictionary = {}

## pet_data_id -> PetData (loaded from PET_DATA_FOLDER on _ready).
var _pet_data_cache: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════════════
# LIFECYCLE
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_load_pet_data_registry()

	# MapManager re-emits player_spawned on every (re)spawn — initial login,
	# channel switch, and map change all route through it. That's the right
	# hook for resurrecting summoned pets in the new context.
	if MapManager and not MapManager.player_spawned.is_connected(_on_player_spawned_on_map):
		MapManager.player_spawned.connect(_on_player_spawned_on_map)

	if multiplayer:
		if not multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
			multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _load_pet_data_registry() -> void:
	var dir := DirAccess.open(PET_DATA_FOLDER)
	if not dir:
		# Folder may not exist yet on fresh repos — that's fine, no pets yet.
		return
	dir.list_dir_begin()
	while true:
		var file := dir.get_next()
		if file.is_empty():
			break
		if dir.current_is_dir():
			continue
		if not (file.ends_with(".tres") or file.ends_with(".res")):
			continue
		var path := PET_DATA_FOLDER + file
		var res = load(path)
		if res is PetData:
			_pet_data_cache[res.pet_id] = res


func get_pet_data(pet_data_id: String) -> PetData:
	return _pet_data_cache.get(pet_data_id)


func get_all_pet_data_ids() -> Array:
	return _pet_data_cache.keys()


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD INTEGRATION
# ═══════════════════════════════════════════════════════════════════════════

func get_save_data(username: String) -> Dictionary:
	if not _rosters.has(username):
		return {KEY_PETS: [], KEY_SUMMONED: []}
	var roster: Dictionary = _rosters[username]
	var pets_copy: Array = []
	for pet in roster.get(KEY_PETS, []):
		pets_copy.append(_clone_record(pet))
	var summoned_copy: Array = (roster.get(KEY_SUMMONED, []) as Array).duplicate()
	return {
		KEY_PETS: pets_copy,
		KEY_SUMMONED: summoned_copy,
	}


func load_pets(username: String, data: Dictionary) -> void:
	var pets: Array = data.get(KEY_PETS, [])
	var summoned: Array = data.get(KEY_SUMMONED, [])

	var clean_pets: Array = []
	for pet in pets:
		if pet is Dictionary and pet.get(KEY_ID, "") != "":
			clean_pets.append(_normalize_record(pet))

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


func clear_player(username: String) -> void:
	_rosters.erase(username)


# ═══════════════════════════════════════════════════════════════════════════
# ROSTER QUERIES
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


func is_pet_summoned(username: String, pet_uuid: String) -> bool:
	return get_summoned_ids(username).has(pet_uuid)


# ═══════════════════════════════════════════════════════════════════════════
# HATCH / SUMMON / UNSUMMON
# ═══════════════════════════════════════════════════════════════════════════

## Server-only. Called by Effect_HatchPet when a player uses a Pet Egg.
func hatch_pet_server(username: String, pet_data_id: String, default_name: String) -> void:
	if not multiplayer.is_server():
		return
	var pet_data := get_pet_data(pet_data_id)
	if not pet_data:
		push_warning("PetManager: hatch_pet_server unknown pet_data_id '%s'" % pet_data_id)
		return

	var owner_peer := _find_peer_id_for_username(username)
	if owner_peer == 0:
		push_warning("PetManager: hatch_pet_server unknown username '%s'" % username)
		return
	if BotManager.is_bot(owner_peer):
		return

	if not _rosters.has(username):
		_rosters[username] = {KEY_PETS: [], KEY_SUMMONED: []}
	var roster: Dictionary = _rosters[username]

	var record := make_pet_record(pet_data_id, default_name)
	roster[KEY_PETS].append(record)
	var pet_uuid: String = record[KEY_ID]

	# v1: 1 active at a time — unsummon existing pets first.
	for existing_id in (roster[KEY_SUMMONED] as Array).duplicate():
		_unsummon_internal(username, existing_id)

	roster[KEY_SUMMONED].append(pet_uuid)
	_spawn_pet_internal(username, pet_uuid)

	notify_pet_hatched_rpc.rpc_id(owner_peer, pet_uuid, default_name, pet_data_id)
	pet_roster_changed.emit()
	_queue_save(username)


## Server-only. Player-initiated summon (from pet UI in Phase 3).
@rpc("any_peer", "call_local", "reliable")
func request_summon_pet_server(pet_uuid: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var username: String = player.username
	if not _rosters.has(username):
		return
	if find_pet(username, pet_uuid).is_empty():
		return  # Not in this player's roster — reject.

	var roster: Dictionary = _rosters[username]
	if not roster[KEY_SUMMONED].has(pet_uuid):
		if (roster[KEY_SUMMONED] as Array).size() >= MAX_ACTIVE_PETS:
			for existing_id in (roster[KEY_SUMMONED] as Array).duplicate():
				_unsummon_internal(username, existing_id)
		roster[KEY_SUMMONED].append(pet_uuid)
	_spawn_pet_internal(username, pet_uuid)
	pet_roster_changed.emit()
	_queue_save(username)


@rpc("any_peer", "call_local", "reliable")
func request_unsummon_pet_server(pet_uuid: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var username: String = player.username
	if not _rosters.has(username):
		return
	if find_pet(username, pet_uuid).is_empty():
		return

	_unsummon_internal(username, pet_uuid)
	pet_roster_changed.emit()
	_queue_save(username)


@rpc("any_peer", "call_local", "reliable")
func request_release_pet_server(pet_uuid: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var username: String = player.username
	if not _rosters.has(username):
		return
	var record := find_pet(username, pet_uuid)
	if record.is_empty():
		return

	# Despawn if summoned, then drop from the roster permanently.
	_unsummon_internal(username, pet_uuid)
	var roster: Dictionary = _rosters[username]
	for i in range((roster[KEY_PETS] as Array).size() - 1, -1, -1):
		if roster[KEY_PETS][i].get(KEY_ID, "") == pet_uuid:
			roster[KEY_PETS].remove_at(i)
	pet_roster_changed.emit()
	_queue_save(username)


@rpc("any_peer", "call_local", "reliable")
func request_rename_pet_server(pet_uuid: String, new_name: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var username: String = player.username
	if not _rosters.has(username):
		return
	var record := find_pet(username, pet_uuid)
	if record.is_empty():
		return
	var clean_name := new_name.strip_edges().left(20)
	if clean_name.is_empty():
		return
	record[KEY_NAME] = clean_name
	pet_roster_changed.emit()
	_queue_save(username)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL — SPAWN / DESPAWN
# ═══════════════════════════════════════════════════════════════════════════

func _spawn_pet_internal(username: String, pet_uuid: String) -> void:
	if _active_pets.has(pet_uuid):
		return

	var record := find_pet(username, pet_uuid)
	if record.is_empty():
		return
	var pet_data_id: String = record.get(KEY_PET_DATA_ID, "")
	var pet_data := get_pet_data(pet_data_id)
	if not pet_data:
		push_warning("PetManager: _spawn_pet_internal missing pet_data '%s'" % pet_data_id)
		return

	var owner_peer := _find_peer_id_for_username(username)
	if owner_peer == 0:
		return
	if BotManager.is_bot(owner_peer):
		return

	var owner_node := PlayerManager.get_player_node(owner_peer)
	if not is_instance_valid(owner_node):
		return
	var map_node := MapManager.get_player_map_node(owner_peer)
	if not is_instance_valid(map_node):
		return

	var pet_node: Pet = PET_SCENE.instantiate() as Pet
	if not pet_node:
		return
	pet_node.name = _pet_node_name(pet_uuid)
	pet_node.setup(pet_data, owner_peer, pet_uuid, username)
	pet_node.set_multiplayer_authority(owner_peer)
	map_node.add_child(pet_node, true)
	pet_node.global_position = owner_node.global_position + pet_data.follow_offset

	# Per-peer visibility: only players currently on this map see the pet.
	var sync := pet_node.get_node_or_null("MultiplayerSynchronizer") as MultiplayerSynchronizer
	if sync:
		sync.public_visibility = false

	var map_id: String = MapManager.get_player_map(owner_peer)
	for peer_id in MapManager.get_real_players_on_map(map_id):
		if peer_id == 1:
			continue
		spawn_pet_client.rpc_id(peer_id, pet_uuid, pet_data_id, owner_peer, username, map_node.name, pet_node.global_position)
		if sync:
			sync.set_visibility_for(peer_id, true)

	_active_pets[pet_uuid] = {
		"pet_node": pet_node,
		"owner_username": username,
		"owner_peer_id": owner_peer,
		"map_id": map_id,
		"pet_data_id": pet_data_id,
	}
	pet_summoned.emit(pet_uuid)


func _unsummon_internal(username: String, pet_uuid: String) -> void:
	_despawn_pet_entity(pet_uuid)
	if _rosters.has(username):
		(_rosters[username][KEY_SUMMONED] as Array).erase(pet_uuid)
	pet_unsummoned.emit(pet_uuid)


func _despawn_pet_entity(pet_uuid: String) -> void:
	if not _active_pets.has(pet_uuid):
		return
	var info: Dictionary = _active_pets[pet_uuid]
	var pet_node: Node = info.get("pet_node")
	_active_pets.erase(pet_uuid)

	# Tell all remote clients to despawn. Local server-side node is freed below.
	despawn_pet_client.rpc(pet_uuid)

	if is_instance_valid(pet_node):
		if pet_node.has_method("cleanup_before_removal"):
			pet_node.cleanup_before_removal()
		pet_node.queue_free()


@rpc("authority", "call_remote", "reliable")
func spawn_pet_client(pet_uuid: String, pet_data_id: String, owner_peer: int, owner_username: String, map_node_name: String, initial_pos: Vector2) -> void:
	if multiplayer.is_server():
		return
	var pet_data := get_pet_data(pet_data_id)
	if not pet_data:
		push_warning("PetManager: spawn_pet_client missing pet_data '%s'" % pet_data_id)
		return

	# Maps live under /root/Maps as SubViewportContainer -> SubViewport -> map_root.
	var map_node := _find_map_node(map_node_name)
	if not map_node:
		push_warning("PetManager: spawn_pet_client couldn't find map node '%s'" % map_node_name)
		return

	# If we already created the local copy (race with synchronizer), skip.
	var existing := map_node.get_node_or_null(_pet_node_name(pet_uuid))
	if existing:
		return

	var pet_node: Pet = PET_SCENE.instantiate() as Pet
	pet_node.name = _pet_node_name(pet_uuid)
	pet_node.setup(pet_data, owner_peer, pet_uuid, owner_username)
	pet_node.set_multiplayer_authority(owner_peer)
	map_node.add_child(pet_node, true)
	pet_node.global_position = initial_pos


@rpc("authority", "call_remote", "reliable")
func despawn_pet_client(pet_uuid: String) -> void:
	if multiplayer.is_server():
		return
	var target_name := _pet_node_name(pet_uuid)
	for map_node in get_tree().get_nodes_in_group("map_base"):
		var pet := map_node.get_node_or_null(target_name)
		if pet:
			pet.queue_free()
			return


## Client-side notification fired right after the player's own egg hatches.
## The UI hooks pet_hatched to open a rename dialog (Phase 3).
@rpc("authority", "call_remote", "reliable")
func notify_pet_hatched_rpc(pet_uuid: String, pet_name: String, pet_data_id: String) -> void:
	pet_hatched.emit(pet_uuid, pet_name, pet_data_id)


# ═══════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS
# ═══════════════════════════════════════════════════════════════════════════

func _on_player_spawned_on_map(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	if BotManager.is_bot(player_id):
		return

	var player := PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player):
		return
	var username: String = player.username
	if username.is_empty() or not _rosters.has(username):
		return

	# Despawn any existing pet entities for this player (they're on the old map).
	var to_despawn: Array = []
	for pet_uuid in _active_pets:
		if _active_pets[pet_uuid].get("owner_username", "") == username:
			to_despawn.append(pet_uuid)
	for pet_uuid in to_despawn:
		_despawn_pet_entity(pet_uuid)

	# Re-spawn summoned pets on the new map.
	for pet_uuid in (_rosters[username][KEY_SUMMONED] as Array).duplicate():
		_spawn_pet_internal(username, pet_uuid)


func _on_peer_disconnected(peer_id: int) -> void:
	if not multiplayer.is_server():
		return
	# Despawn this peer's pets but keep the roster intact for reconnect.
	var to_despawn: Array = []
	for pet_uuid in _active_pets:
		if _active_pets[pet_uuid].get("owner_peer_id", 0) == peer_id:
			to_despawn.append(pet_uuid)
	for pet_uuid in to_despawn:
		_despawn_pet_entity(pet_uuid)


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

static func _pet_node_name(pet_uuid: String) -> String:
	return "Pet_%s" % pet_uuid.replace("-", "")


func _find_map_node(map_node_name: String) -> Node:
	# Maps live under /root/Maps/<container>/SubViewport/<MapName>.
	# Walk the tree to find the named node.
	var maps_root := get_node_or_null("/root/Maps")
	if not maps_root:
		return null
	for child in maps_root.get_children():
		var sub := child.get_node_or_null("SubViewport") if child is SubViewportContainer else child
		if not sub:
			continue
		var map := sub.get_node_or_null(map_node_name)
		if map:
			return map
		# Fallback: any direct child whose name matches.
		for grandchild in sub.get_children():
			if grandchild.name == map_node_name:
				return grandchild
	return null


func _find_peer_id_for_username(username: String) -> int:
	if not PlayerManager or not PlayerManager.active_players:
		return 0
	for peer_id in PlayerManager.active_players.keys():
		var info = PlayerManager.active_players[peer_id]
		if info.get("username", "") == username:
			return peer_id
	return 0


func _queue_save(username: String) -> void:
	var peer := _find_peer_id_for_username(username)
	if peer == 0:
		return
	var player_node := PlayerManager.get_player_node(peer)
	if is_instance_valid(player_node) and SaveManager:
		SaveManager.queue_save(username, "pets", player_node)


# ═══════════════════════════════════════════════════════════════════════════
# RECORD HELPERS
# ═══════════════════════════════════════════════════════════════════════════

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
