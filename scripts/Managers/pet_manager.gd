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
# Pet inventory now has 3 *command* slots instead of generic storage.
# A command is "active" while its matching skill book is equipped in its slot.
const KEY_CMD_AUTO_POT := "command_auto_pot_slot"
const KEY_CMD_BUFF := "command_buff_slot"
const KEY_CMD_MAGNET := "command_magnet_slot"

const KEY_HP_THRESHOLD := "hp_threshold"
const KEY_MP_THRESHOLD := "mp_threshold"

const CMD_AUTO_POT := "auto_pot"
const CMD_AUTOBUFF := "autobuff"
const CMD_MAGNET := "magnet"  # unified item+coin auto-loot

# Books are identified by their canonical NAME, not item_id. This project
# generates UUIDs for `item_id` in `_init()` and the .tres-set value doesn't
# stick reliably; `name` is the stable identifier and ResourceManager indexes
# items by it. Confirmed by looking at existing items like Grape_Potion.tres
# which has a UUID for item_id and "Health Potion" for name.
const BOOK_AUTO_POT_NAME := "Pet Auto Pot Command"
const BOOK_AUTOBUFF_NAME := "Pet Buff Command"
const BOOK_MAGNET_NAME := "Pet Magnet Command"

# v1: only 1 pet active at a time. Increase to support multi-pet later.
const MAX_ACTIVE_PETS: int = 1

# Hunger config
const HUNGER_SAVE_THROTTLE_MS: int = 30_000      # min ms between hunger-triggered saves
const HUNGER_BROADCAST_INTERVAL_MS: int = 2_000  # min ms between hunger broadcasts (no-state-change)
const HUNGER_HUNGRY_AUTO_UNSUMMON_MS: int = 300_000  # 5 min in Hungry state with owner away -> auto-unsummon
const HUNGER_LOW_FRACTION: float = 0.25          # bubble appears at <=25%

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

# ── Client-side mirror (the local player's roster) ────────────────────────
## Pushed by the server via sync_roster_to_client_rpc whenever the roster
## changes. UI subscribes to client_roster_updated.
var _client_roster: Dictionary = {KEY_PETS: [], KEY_SUMMONED: []}
signal client_roster_updated()


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


func _process(delta: float) -> void:
	if not multiplayer or not multiplayer.has_multiplayer_peer():
		return
	if not multiplayer.is_server():
		return
	_tick_hunger(delta)
	_tick_autobuff()


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
	# Push the freshly-loaded roster to the owner client so its UI hydrates.
	_push_roster_to_owner(username)


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

	# Notify the owner client. Host is its own owner — emit the signal locally
	# (call_remote rpc_id to self is disallowed by Godot's scene rpc layer).
	if owner_peer == 1:
		pet_hatched.emit(pet_uuid, default_name, pet_data_id)
	else:
		notify_pet_hatched_rpc.rpc_id(owner_peer, pet_uuid, default_name, pet_data_id)
	pet_roster_changed.emit()
	_push_roster_to_owner(username)
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
	_push_roster_to_owner(username)
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
	_push_roster_to_owner(username)
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

	# Return pet-inventory contents to the player's main inventory before the
	# record disappears. server_add_item handles free-slot search + stacking.
	if is_instance_valid(player.inventory_component):
		_return_pet_inventory_to_player(record, player.inventory_component)

	# Despawn if summoned, then drop from the roster permanently.
	_unsummon_internal(username, pet_uuid)
	var roster: Dictionary = _rosters[username]
	for i in range((roster[KEY_PETS] as Array).size() - 1, -1, -1):
		if roster[KEY_PETS][i].get(KEY_ID, "") == pet_uuid:
			roster[KEY_PETS].remove_at(i)
	pet_roster_changed.emit()
	_push_roster_to_owner(username)
	_queue_save(username)


## Returns every non-empty pet inventory slot to the player's main inventory.
## Called on Release. Items the inventory can't accept (full bag) are lost —
## Release is destructive by design. The player gets a warning dialog before
## confirming.
func _return_pet_inventory_to_player(record: Dictionary, inv) -> void:
	var pet_inv: Dictionary = record.get(KEY_INVENTORY, {})
	for slot_key in [KEY_AUTOPOT_HP, KEY_AUTOPOT_MP, KEY_CMD_AUTO_POT, KEY_CMD_BUFF, KEY_CMD_MAGNET]:
		_return_one_pet_slot(pet_inv.get(slot_key, {}), inv)
		pet_inv[slot_key] = {}


func _return_one_pet_slot(slot_data: Dictionary, inv) -> void:
	if slot_data == null or slot_data.is_empty():
		return
	var item_id: String = slot_data.get("item_id", "")
	var stack: int = int(slot_data.get("stack", 0))
	if item_id.is_empty() or stack <= 0:
		return
	for i in stack:
		inv.server_add_item(item_id)


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
	_push_roster_to_owner(username)
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
# HUNGER TICK / FEEDING
# ═══════════════════════════════════════════════════════════════════════════

func _tick_hunger(delta: float) -> void:
	if _active_pets.is_empty():
		return
	var now_ms := Time.get_ticks_msec()
	var to_auto_unsummon: Array = []

	for pet_uuid in _active_pets.keys():
		var info: Dictionary = _active_pets[pet_uuid]
		var owner_peer: int = info.get("owner_peer_id", 0)
		var owner_username: String = info.get("owner_username", "")
		if owner_peer <= 0 or owner_username.is_empty():
			continue
		# Pause hunger if owner went offline (defence in depth — peer_disconnected
		# normally despawns first).
		if not PlayerManager.has_player(owner_peer):
			continue

		var record := find_pet(owner_username, pet_uuid)
		if record.is_empty():
			continue
		var pet_data := get_pet_data(record.get(KEY_PET_DATA_ID, ""))
		if not pet_data:
			continue

		var prev_hunger: float = record.get(KEY_HUNGER, pet_data.max_hunger)
		var prev_hungry: bool = prev_hunger <= 0.0
		var new_hunger: float = max(0.0, prev_hunger - pet_data.hunger_decay_per_sec * delta)
		record[KEY_HUNGER] = new_hunger
		var is_hungry: bool = new_hunger <= 0.0

		# State transition: just entered Hungry -> stamp the timer, push state, save now.
		if is_hungry and not prev_hungry:
			info["hungry_since_ms"] = now_ms
			_broadcast_pet_hunger_rpc.rpc(pet_uuid, new_hunger, pet_data.max_hunger, true)
			info["last_broadcast_ms"] = now_ms
			_queue_save(owner_username)
		elif not is_hungry and prev_hungry:
			info["hungry_since_ms"] = 0
			_broadcast_pet_hunger_rpc.rpc(pet_uuid, new_hunger, pet_data.max_hunger, false)
			info["last_broadcast_ms"] = now_ms
			_queue_save(owner_username)
		else:
			# No transition — throttle broadcast to once every ~2s.
			var last_bcast: int = info.get("last_broadcast_ms", 0)
			if now_ms - last_bcast >= HUNGER_BROADCAST_INTERVAL_MS:
				_broadcast_pet_hunger_rpc.rpc(pet_uuid, new_hunger, pet_data.max_hunger, is_hungry)
				info["last_broadcast_ms"] = now_ms

		# 5-min auto-unsummon if Hungry and owner has wandered far away.
		if is_hungry:
			var hungry_since: int = info.get("hungry_since_ms", 0)
			if hungry_since > 0 and now_ms - hungry_since >= HUNGER_HUNGRY_AUTO_UNSUMMON_MS:
				if _owner_far_from_pet(info):
					to_auto_unsummon.append(pet_uuid)

		# Save throttle for non-transition tick updates.
		var last_save_ms: int = info.get("last_save_ms", 0)
		if now_ms - last_save_ms >= HUNGER_SAVE_THROTTLE_MS:
			info["last_save_ms"] = now_ms
			_queue_save(owner_username)

	# Auto-unsummon after the loop so we don't mutate _active_pets while iterating.
	for pet_uuid in to_auto_unsummon:
		var info: Dictionary = _active_pets.get(pet_uuid, {})
		var owner_username: String = info.get("owner_username", "")
		if owner_username.is_empty():
			continue
		# Boot hunger to 1 so resummoning gives a small feed window.
		var record := find_pet(owner_username, pet_uuid)
		if not record.is_empty():
			record[KEY_HUNGER] = 1.0
		_unsummon_internal(owner_username, pet_uuid)
		_push_roster_to_owner(owner_username)
		_queue_save(owner_username)


func _owner_far_from_pet(info: Dictionary) -> bool:
	var pet_node: Node = info.get("pet_node")
	var owner_peer: int = info.get("owner_peer_id", 0)
	if not is_instance_valid(pet_node) or owner_peer <= 0:
		return true
	var owner_node := PlayerManager.get_player_node(owner_peer)
	if not is_instance_valid(owner_node):
		return true
	var pet_data := get_pet_data(info.get("pet_data_id", ""))
	var leash: float = pet_data.leash_radius if pet_data else 200.0
	# "Far" = 2x leash, so a player standing right next to a Hungry pet doesn't
	# trigger the polite cleanup.
	return owner_node.global_position.distance_to(pet_node.global_position) > leash * 2.0


@rpc("authority", "call_local", "reliable")
func _broadcast_pet_hunger_rpc(pet_uuid: String, hunger: float, max_hunger: float, hungry: bool) -> void:
	# Find the pet node on this peer's map tree and apply the state.
	var node_name := _pet_node_name(pet_uuid)
	for map_node in get_tree().get_nodes_in_group("map_base"):
		var pet := map_node.get_node_or_null(node_name)
		if pet and pet.has_method("apply_hunger_state"):
			pet.apply_hunger_state(hunger, max_hunger, hungry)
			return


## Server -> all peers. Triggers a short visual feedback on the pet node
## (scale pulse for loot, bubble for pot/buff/feed). Cosmetic only.
@rpc("authority", "call_local", "reliable")
func _pet_event_visual_rpc(pet_uuid: String, event_type: String) -> void:
	var node_name := _pet_node_name(pet_uuid)
	for map_node in get_tree().get_nodes_in_group("map_base"):
		var pet := map_node.get_node_or_null(node_name)
		if pet and pet.has_method("play_event_visual"):
			pet.play_event_visual(event_type)
			return


## Server-only. Player asks server to feed pet from a specific inventory slot.
@rpc("any_peer", "call_local", "reliable")
func request_feed_pet_server(pet_uuid: String, inventory_slot_index: int) -> void:
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
	if not _active_pets.has(pet_uuid):
		return  # Must be summoned to feed (MapleStory parity)
	var inventory := player.inventory_component
	if not inventory or inventory_slot_index < 0 or inventory_slot_index >= inventory.slots_data.size():
		return
	var slot = inventory.slots_data[inventory_slot_index]
	if not slot or not slot.item or not slot.item is PetFoodData:
		return

	var food: PetFoodData = slot.item as PetFoodData
	var pet_data := get_pet_data(record.get(KEY_PET_DATA_ID, ""))
	var max_h: float = pet_data.max_hunger if pet_data else 100.0

	var new_hunger: float = min(max_h, record.get(KEY_HUNGER, max_h) + food.fullness_restore)
	record[KEY_HUNGER] = new_hunger

	# Wake from Hungry state on any successful feed.
	if _active_pets.has(pet_uuid):
		_active_pets[pet_uuid]["hungry_since_ms"] = 0
		_active_pets[pet_uuid]["last_broadcast_ms"] = Time.get_ticks_msec()
	_broadcast_pet_hunger_rpc.rpc(pet_uuid, new_hunger, max_h, new_hunger <= 0.0)

	inventory.remove_item_from_stack(food, 1, "fed_to_pet")
	_pet_event_visual_rpc.rpc(pet_uuid, "fed")
	_push_roster_to_owner(username)
	_queue_save(username)


# ═══════════════════════════════════════════════════════════════════════════
# DRAG-ITEM-ONTO-PET (MapleStory parity — alternate to inventory `Use`)
# ═══════════════════════════════════════════════════════════════════════════

const DROP_ON_PET_RADIUS: float = 48.0

## Server-side. Called by GlobalDropHandler.server_request_item_drop when the
## player drops an inventory stack onto the world. If the drop lands on a
## summoned pet owned by this player AND the item is pet-targeted (PetFoodData
## or PetSkillBookData), the pet consumes it and the function returns true
## (caller should NOT create a world drop, but SHOULD remove from inventory).
func try_consume_dropped_item_on_pet(item: ItemData, player_peer: int, drop_position: Vector2) -> bool:
	if not multiplayer.is_server():
		return false
	if not item:
		return false
	if not (item is PetFoodData or item is PetSkillBookData):
		return false

	var player_node := PlayerManager.get_player_node(player_peer)
	if not is_instance_valid(player_node):
		return false
	var username: String = player_node.username
	var summoned: Array = get_summoned_ids(username)
	if summoned.is_empty():
		_show_message_to_owner(player_peer, "No pet summoned.")
		return false

	# v1: 1 summoned pet max. Pick the closest one as a defensive default.
	var pet_uuid: String = ""
	var closest_dist: float = DROP_ON_PET_RADIUS
	for uuid in summoned:
		if not _active_pets.has(uuid):
			continue
		var pet_node: Node = _active_pets[uuid].get("pet_node")
		if not is_instance_valid(pet_node):
			continue
		var d: float = pet_node.global_position.distance_to(drop_position)
		if d <= closest_dist:
			closest_dist = d
			pet_uuid = uuid
	if pet_uuid.is_empty():
		return false  # No pet within reach of drop — let it land on the floor.

	if item is PetFoodData:
		return _apply_food_to_pet(item, username, pet_uuid)
	if item is PetSkillBookData:
		return _apply_book_to_pet(item, username, pet_uuid, player_peer)
	return false


func _apply_food_to_pet(food: PetFoodData, username: String, pet_uuid: String) -> bool:
	var record := find_pet(username, pet_uuid)
	if record.is_empty():
		return false
	var pet_data := get_pet_data(record.get(KEY_PET_DATA_ID, ""))
	var max_h: float = pet_data.max_hunger if pet_data else 100.0
	var new_hunger: float = min(max_h, record.get(KEY_HUNGER, max_h) + food.fullness_restore)
	record[KEY_HUNGER] = new_hunger

	if _active_pets.has(pet_uuid):
		_active_pets[pet_uuid]["hungry_since_ms"] = 0
		_active_pets[pet_uuid]["last_broadcast_ms"] = Time.get_ticks_msec()
	_broadcast_pet_hunger_rpc.rpc(pet_uuid, new_hunger, max_h, new_hunger <= 0.0)
	_pet_event_visual_rpc.rpc(pet_uuid, "fed")
	_push_roster_to_owner(username)
	_queue_save(username)
	return true


## Places a command book in its matching pet inventory slot (Auto Pot / Buff /
## Magnet). The book is NOT consumed — it occupies the slot as long as the
## player wants the command active. Removing the book deactivates the command.
func _apply_book_to_pet(book: PetSkillBookData, username: String, pet_uuid: String, player_peer: int) -> bool:
	var record := find_pet(username, pet_uuid)
	if record.is_empty():
		return false
	var target_slot_key: String = _slot_key_for_book(book)
	if target_slot_key.is_empty():
		_show_message_to_owner(player_peer, "This book doesn't fit any pet command slot.")
		return false

	var inv: Dictionary = record.get(KEY_INVENTORY, {})
	var existing: Dictionary = _read_pet_slot(inv, target_slot_key)
	if not existing.is_empty():
		# Slot already occupied — drag through the Pet UI to swap manually.
		_show_message_to_owner(player_peer, "Pet already has that command equipped.")
		return false

	# Store the canonical name — ResourceManager indexes items by name, and
	# PetSlot.refresh looks up via that key. Instance UUIDs don't survive
	# game restarts reliably so we don't store them.
	_write_pet_slot(inv, target_slot_key, {
		"item_id": book.name,
		"stack": 1,
	})
	_pet_event_visual_rpc.rpc(pet_uuid, "taught")
	_push_roster_to_owner(username)
	_queue_save(username)
	return true


static func _slot_key_for_book(book: PetSkillBookData) -> String:
	# Match by name — see note on BOOK_*_NAME constants.
	match book.name:
		BOOK_AUTO_POT_NAME:
			return KEY_CMD_AUTO_POT
		BOOK_AUTOBUFF_NAME:
			return KEY_CMD_BUFF
		BOOK_MAGNET_NAME:
			return KEY_CMD_MAGNET
		_:
			return ""


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-LOOT (Phase 5)
# ═══════════════════════════════════════════════════════════════════════════

const AUTOLOOT_RATE_LIMIT_MS: int = 200

@rpc("any_peer", "call_local", "reliable")
func request_autoloot_server(pet_uuid: String, drop_node_name: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	if not _active_pets.has(pet_uuid):
		print("[autoloot] REJECT: pet '%s' not in _active_pets" % pet_uuid)
		return
	var info: Dictionary = _active_pets[pet_uuid]
	if info.get("owner_peer_id", 0) != caller:
		print("[autoloot] REJECT: caller %d not owner of pet (owner=%s)" % [caller, info.get("owner_peer_id", 0)])
		return

	var pet_node: Node = info.get("pet_node")
	if not is_instance_valid(pet_node):
		print("[autoloot] REJECT: pet_node invalid")
		return
	var owner_username: String = info.get("owner_username", "")
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		print("[autoloot] REJECT: pet not in roster")
		return
	if record.get(KEY_HUNGER, 100.0) <= 0.0:
		print("[autoloot] REJECT: pet is Hungry")
		return

	if not is_command_active(record, CMD_MAGNET):
		print("[autoloot] REJECT: magnet command not active")
		return

	var owner_player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(owner_player):
		print("[autoloot] REJECT: owner_player invalid")
		return

	var map_node := pet_node.get_parent()
	if not map_node:
		print("[autoloot] REJECT: pet has no parent map")
		return
	var drop: Node = map_node.get_node_or_null(drop_node_name)
	if not drop:
		var drops_container := map_node.get_node_or_null("ItemDrops")
		if drops_container:
			drop = drops_container.get_node_or_null(drop_node_name)
	if not (drop is DroppedItem):
		print("[autoloot] REJECT: drop '%s' not found or not DroppedItem (parent=%s)" % [drop_node_name, map_node.name])
		return

	if not drop.item_data:
		print("[autoloot] REJECT: drop has no item_data")
		return

	# Validate by OWNER position, not pet position. The pet is owner-client
	# authoritative; its server-side position lags by network latency (the
	# server only receives updates via MultiplayerSynchronizer). Reports
	# from the field showed server-side pet-to-drop distance was 120-180px
	# behind the client's view, blowing past any pet-tight range gate.
	#
	# The owner's character is reliably synced (player movement is the
	# canonical authoritative-replicated state). Constrain the pickup to
	# "drop is within reach of the OWNER + pet's reach" — i.e., the pet
	# could plausibly walk from the owner to the drop.
	var pet_data := get_pet_data(info.get("pet_data_id", ""))
	var autoloot: float = pet_data.autoloot_radius if pet_data else 100.0
	var leash: float = pet_data.leash_radius if pet_data else 200.0
	var pickup_range: float = autoloot + leash
	var owner_drop_dist: float = owner_player.global_position.distance_to(drop.global_position)
	if owner_drop_dist > pickup_range:
		print("[autoloot] REJECT: owner-to-drop %.1f > pickup_range %.1f (autoloot %.1f + leash %.1f)" % [owner_drop_dist, pickup_range, autoloot, leash])
		return

	if drop.has_method("_can_player_pickup") and not drop._can_player_pickup(owner_player):
		print("[autoloot] REJECT: _can_player_pickup false (eligible=%s, public=%s, drop='%s')" % [drop._eligible_player_ids if "_eligible_player_ids" in drop else "?", drop.is_public_pickup if "is_public_pickup" in drop else "?", drop.item_data.name])
		return
	if drop.has_method("_player_has_room_for_item") and not drop._player_has_room_for_item(owner_player):
		print("[autoloot] REJECT: _player_has_room_for_item false (inventory full?)")
		return

	var now_ms := Time.get_ticks_msec()
	if now_ms - int(info.get("last_autoloot_ms", 0)) < AUTOLOOT_RATE_LIMIT_MS:
		print("[autoloot] REJECT: rate-limited (last=%d now=%d delta=%d)" % [info.get("last_autoloot_ms", 0), now_ms, now_ms - int(info.get("last_autoloot_ms", 0))])
		return
	info["last_autoloot_ms"] = now_ms

	if drop.has_method("_pickup_item"):
		print("[autoloot] PICKUP firing for '%s'" % drop.item_data.name)
		drop._pickup_item(owner_player)
		_pet_event_visual_rpc.rpc(pet_uuid, "autoloot")


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-POT (Phase 6)
# ═══════════════════════════════════════════════════════════════════════════

const AUTOPOT_COOLDOWN_MS: int = 1000

@rpc("any_peer", "call_local", "reliable")
func request_autopot_server(pet_uuid: String, slot_type: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	if not _active_pets.has(pet_uuid):
		return
	var info: Dictionary = _active_pets[pet_uuid]
	if info.get("owner_peer_id", 0) != caller:
		return
	var owner_username: String = info.get("owner_username", "")
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		return
	if record.get(KEY_HUNGER, 100.0) <= 0.0:
		return
	if not is_command_active(record, CMD_AUTO_POT):
		return
	var slot_key := KEY_AUTOPOT_HP if slot_type == "hp" else KEY_AUTOPOT_MP
	var inv: Dictionary = record.get(KEY_INVENTORY, {})
	var slot_data: Dictionary = inv.get(slot_key, {})
	var item_id: String = slot_data.get("item_id", "")
	var stack: int = int(slot_data.get("stack", 0))
	if item_id.is_empty() or stack <= 0:
		return

	var owner_player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(owner_player):
		return
	var cfg: Dictionary = record.get(KEY_AUTOPOT_CONFIG, {})
	if slot_type == "hp":
		var hp := owner_player.health_component
		if not is_instance_valid(hp) or hp.max_health <= 0:
			return
		if float(hp.current_health) >= float(hp.max_health) * cfg.get(KEY_HP_THRESHOLD, 0.5):
			return
	else:
		var mp := owner_player.mana_component
		if not is_instance_valid(mp) or mp.max_mana <= 0:
			return
		if float(mp.current_mana) >= float(mp.max_mana) * cfg.get(KEY_MP_THRESHOLD, 0.5):
			return

	# Per-slot cooldown
	var cd_key := "last_autopot_hp_ms" if slot_type == "hp" else "last_autopot_mp_ms"
	var now_ms := Time.get_ticks_msec()
	if now_ms - int(info.get(cd_key, 0)) < AUTOPOT_COOLDOWN_MS:
		return
	info[cd_key] = now_ms

	# Look up the consumable and run its effect on the owner.
	var consumable_res := ResourceManager.get_item_data(item_id)
	if not (consumable_res is ConsumableData):
		return
	var consumable: ConsumableData = consumable_res as ConsumableData
	if not consumable.effect_script:
		return
	var effect_instance = consumable.effect_script.new() as BaseItemEffect
	if not effect_instance:
		return
	effect_instance.user = owner_player
	effect_instance.source_item = consumable
	effect_instance.execute()

	# Decrement the pet slot stack.
	slot_data["stack"] = stack - 1
	if slot_data["stack"] <= 0:
		inv[slot_key] = {}
		_show_message_to_owner(caller, "Pet's %s pot slot is empty!" % slot_type.to_upper())
	else:
		inv[slot_key] = slot_data

	_pet_event_visual_rpc.rpc(pet_uuid, "autopot_hp" if slot_type == "hp" else "autopot_mp")
	_push_roster_to_owner(owner_username)
	_queue_save(owner_username)


@rpc("any_peer", "call_local", "reliable")
func request_set_autopot_threshold_server(pet_uuid: String, slot_type: String, threshold: float) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	# Configuring thresholds doesn't require the pet to be currently summoned.
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var owner_username: String = player.username
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		return
	threshold = clamp(threshold, 0.0, 1.0)
	var cfg: Dictionary = record.get(KEY_AUTOPOT_CONFIG, {})
	if slot_type == "hp":
		cfg[KEY_HP_THRESHOLD] = threshold
	elif slot_type == "mp":
		cfg[KEY_MP_THRESHOLD] = threshold
	else:
		return
	record[KEY_AUTOPOT_CONFIG] = cfg
	_push_roster_to_owner(owner_username)
	_queue_save(owner_username)


# ═══════════════════════════════════════════════════════════════════════════
# PET INVENTORY TRANSFER (Phase 6 + Phase 8)
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_local", "reliable")
func request_transfer_to_pet_slot_server(pet_uuid: String, slot_key: String, source_inventory_idx: int) -> void:
	print("[PetMgr.transfer_to] RPC received. pet=%s slot=%s idx=%d is_server=%s" % [pet_uuid, slot_key, source_inventory_idx, multiplayer.is_server()])
	if not multiplayer.is_server():
		print("[PetMgr.transfer_to] not server — early return")
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	print("[PetMgr.transfer_to] caller=%d" % caller)
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		print("[PetMgr.transfer_to] REJECT: player or inventory_component invalid")
		return
	var owner_username: String = player.username
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		print("[PetMgr.transfer_to] REJECT: pet '%s' not in '%s' roster" % [pet_uuid, owner_username])
		return
	print("[PetMgr.transfer_to] pet found in roster")
	var source_inv = player.inventory_component
	print("[PetMgr.transfer_to] source_inv has %d slots_data" % source_inv.slots_data.size())
	if source_inventory_idx < 0 or source_inventory_idx >= source_inv.slots_data.size():
		print("[PetMgr.transfer_to] REJECT: idx %d out of range" % source_inventory_idx)
		return
	var source_sd = source_inv.slots_data[source_inventory_idx]
	if not source_sd or not source_sd.item:
		print("[PetMgr.transfer_to] REJECT: source slot %d empty (sd=%s, item=%s)" % [source_inventory_idx, source_sd, source_sd.item if source_sd else "n/a"])
		return
	var item: ItemData = source_sd.item
	print("[PetMgr.transfer_to] source item: name='%s' item_id='%s' class='%s'" % [item.name, item.item_id, item.get_class()])

	if not _slot_accepts_item(slot_key, item):
		print("[PetMgr.transfer_to] REJECT: _slot_accepts_item false. item.name='%s' expected_name='%s'" % [item.name, book_name_for_slot(slot_key)])
		_show_message_to_owner(caller, "That item doesn't fit this slot.")
		return

	var inv: Dictionary = record.get(KEY_INVENTORY, {})
	var existing := _read_pet_slot(inv, slot_key)
	var is_command_slot: bool = slot_key == KEY_CMD_AUTO_POT or slot_key == KEY_CMD_BUFF or slot_key == KEY_CMD_MAGNET

	if is_command_slot and not existing.is_empty():
		# Command slots hold exactly ONE book. Refuse to stack or overwrite
		# silently — the player has to right-click to unequip first.
		print("[PetMgr.transfer_to] REJECT: command slot '%s' already equipped" % slot_key)
		_show_message_to_owner(caller, "That command slot is already equipped. Right-click to unequip first.")
		return

	# Pot slots may stack the same item or swap a different one.
	var canonical_key: String = item.name
	if not is_command_slot and not existing.is_empty() and existing.get("item_id", "") != canonical_key:
		# Swap: put the existing item back into main inventory first.
		var existing_id: String = existing.get("item_id", "")
		var existing_stack: int = int(existing.get("stack", 0))
		var ex_resource := ResourceManager.get_item_data(existing_id)
		if ex_resource and existing_stack > 0:
			for i in existing_stack:
				source_inv.server_add_item(existing_id)
		_write_pet_slot(inv, slot_key, {})

	var new_stack: int = int(existing.get("stack", 0)) + item.current_stack_amount if existing.get("item_id", "") == canonical_key else item.current_stack_amount
	_write_pet_slot(inv, slot_key, {
		"item_id": canonical_key,
		"stack": new_stack,
	})

	# Remove the source from main inventory. remove_item_from_stack short-
	# circuits to 0 for non-stackable items (Slot.remove_from_stack returns 0
	# early when !can_stack), so we use clear_slot for the whole-slot move.
	# That handles both stackable and non-stackable in one path since we're
	# always moving the entire source stack to the pet slot.
	if source_inventory_idx >= 0 and source_inventory_idx < source_inv.slots.size():
		var source_slot_node: Slot = source_inv.slots[source_inventory_idx]
		if is_instance_valid(source_slot_node):
			source_inv.clear_slot(source_slot_node, "transferred_to_pet")
	print("[PetMgr.transfer_to] DONE: inventory slot %d cleared, pet slot '%s' now holds '%s'" % [source_inventory_idx, slot_key, canonical_key])
	_push_roster_to_owner(owner_username)
	_queue_save(owner_username)


@rpc("any_peer", "call_local", "reliable")
func request_transfer_from_pet_slot_server(pet_uuid: String, slot_key: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	# Unequipping a pet item doesn't require the pet to be currently summoned.
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return
	var owner_username: String = player.username
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		return

	var inv: Dictionary = record.get(KEY_INVENTORY, {})
	var slot_data := _read_pet_slot(inv, slot_key)
	var item_id: String = slot_data.get("item_id", "")
	var stack: int = int(slot_data.get("stack", 0))
	if item_id.is_empty() or stack <= 0:
		return

	# Push the held stack back to main inventory one at a time. server_add_item
	# handles stacking + free-slot search via existing inventory logic.
	for i in stack:
		player.inventory_component.server_add_item(item_id)
	_write_pet_slot(inv, slot_key, {})
	_push_roster_to_owner(owner_username)
	_queue_save(owner_username)


func _read_pet_slot(inv: Dictionary, slot_key: String) -> Dictionary:
	return inv.get(slot_key, {})


func _write_pet_slot(inv: Dictionary, slot_key: String, slot_data: Dictionary) -> void:
	inv[slot_key] = slot_data


## Server-side validation: does this slot accept this item?
##   - Autopot HP/MP slots: any ConsumableData except a pet-only consumable.
##   - Command slots: ONLY the matching PetSkillBookData (matched by name —
##     item_id is a generated UUID per the project convention).
##   - Any other slot key: reject.
func _slot_accepts_item(slot_key: String, item: ItemData) -> bool:
	if slot_key == KEY_AUTOPOT_HP or slot_key == KEY_AUTOPOT_MP:
		if not (item is ConsumableData):
			return false
		if item is PetSkillBookData or item is PetFoodData:
			return false
		return true
	var expected_name: String = book_name_for_slot(slot_key)
	if expected_name.is_empty():
		return false
	return item is PetSkillBookData and item.name == expected_name


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-BUFF (Phase 7)
# ═══════════════════════════════════════════════════════════════════════════

## Server-side buff timer. Deliberate deviation from Option B — the trigger is
## purely time-based, not client-observable, so a server-driven timer beats a
## redundant client RPC round-trip. See docs/adr/0001-pet-system-architecture.md.
##
## The cast routes through the owner's AbilityComponent.use_ability — same
## pathway as a player-driven cast — so MP cost, cooldown, and ability visuals
## all behave identically to a manual cast.
func _tick_autobuff() -> void:
	if _active_pets.is_empty():
		return
	for pet_uuid in _active_pets.keys():
		var info: Dictionary = _active_pets[pet_uuid]
		var owner_username: String = info.get("owner_username", "")
		var owner_peer: int = info.get("owner_peer_id", 0)
		if owner_username.is_empty() or owner_peer <= 0:
			continue

		var record := find_pet(owner_username, pet_uuid)
		if record.is_empty():
			continue
		if record.get(KEY_HUNGER, 100.0) <= 0.0:
			continue
		if not is_command_active(record, CMD_AUTOBUFF):
			continue
		var ability_id: String = record.get(KEY_ACTIVE_BUFF, "")
		if ability_id.is_empty():
			continue

		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability or not ability.applies_buff:
			continue
		if not ability.active_behavior or ability.active_behavior.target_type != Constants.TargetType.SELF:
			continue

		var owner_player := PlayerManager.get_player_node(owner_peer)
		if not is_instance_valid(owner_player) or not is_instance_valid(owner_player.ability_component):
			continue

		# Validate the owner actually has this ability learned.
		if int(owner_player.ability_component._ability_levels.get(ability_id, 0)) <= 0:
			continue

		# Skip if owner already has plenty of the buff remaining (avoids wasting
		# MP on a no-op refresh). AbilityComponent will also refuse on cooldown.
		if is_instance_valid(owner_player.buff_component):
			var buff_id: String = ability.applies_buff.buff_id
			if owner_player.buff_component.has_buff(buff_id):
				if owner_player.buff_component.get_buff_duration(buff_id) > 5.0:
					continue

		# Cast via the canonical pathway. use_ability() on the server runs
		# _handle_authoritative_use, which validates cooldown + MP, deducts
		# MP, applies the buff, sets the cooldown, and broadcasts visuals.
		var cast_ok: bool = owner_player.ability_component.use_ability(ability_id)
		if cast_ok:
			_pet_event_visual_rpc.rpc(pet_uuid, "autobuff")


@rpc("any_peer", "call_local", "reliable")
func request_set_active_buff_ability_server(pet_uuid: String, ability_id: String) -> void:
	if not multiplayer.is_server():
		return
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	# Setting the active buff ability doesn't require the pet to be currently summoned.
	var player := PlayerManager.get_player_node(caller)
	if not is_instance_valid(player):
		return
	var owner_username: String = player.username
	var record := find_pet(owner_username, pet_uuid)
	if record.is_empty():
		return

	# An empty string clears the slot. Otherwise validate caller owns it and
	# it's a self-target buff ability.
	if not ability_id.is_empty():
		if not is_instance_valid(player.ability_component):
			return
		if int(player.ability_component._ability_levels.get(ability_id, 0)) <= 0:
			return
		var ability: AbilityData = ResourceManager.get_ability_data(ability_id)
		if not ability or not ability.applies_buff:
			return
		if not ability.active_behavior or ability.active_behavior.target_type != Constants.TargetType.SELF:
			return

	record[KEY_ACTIVE_BUFF] = ability_id
	_push_roster_to_owner(owner_username)
	_queue_save(owner_username)


# ═══════════════════════════════════════════════════════════════════════════
# SKILL-BOOK FEEDBACK
# ═══════════════════════════════════════════════════════════════════════════

## Called by Effect_TeachPetCommand server-side after a successful command teach.
func notify_command_learned(username: String, _pet_uuid: String, command_id: String) -> void:
	if not multiplayer.is_server():
		return
	_push_roster_to_owner(username)
	_queue_save(username)
	var peer := _find_peer_id_for_username(username)
	var msg := "Pet learned: %s" % command_id
	_show_message_to_owner(peer, msg)


## Called by Effect_TeachPetCommand server-side when the book couldn't be applied.
func notify_book_use_failed(username: String, reason: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _find_peer_id_for_username(username)
	_show_message_to_owner(peer, reason)


func _show_message_to_owner(peer: int, message: String) -> void:
	if peer == 0:
		return
	if peer == 1:
		# Host has the LogManager locally.
		LogManager.add_scrolling_log(message, Color.GOLD)
		return
	_log_to_client_rpc.rpc_id(peer, message)


@rpc("authority", "call_remote", "reliable")
func _log_to_client_rpc(message: String) -> void:
	if multiplayer.is_server():
		return
	LogManager.add_scrolling_log(message, Color.GOLD)


# ═══════════════════════════════════════════════════════════════════════════
# CLIENT-SIDE ROSTER MIRROR
# ═══════════════════════════════════════════════════════════════════════════

## Server -> owner only. Pushes the latest roster so the owner client's UI
## can display owned pets, hunger, learned commands, etc. Called after every
## roster mutation and on initial load.
@rpc("authority", "call_remote", "reliable")
func sync_roster_to_client_rpc(roster: Dictionary) -> void:
	if multiplayer.is_server():
		return
	_client_roster = roster
	client_roster_updated.emit()


## Server-side: push the current roster for `username` to its owner.
## On a remote client, this travels via RPC. On the host, it short-circuits
## to a local signal so the UI doesn't depend on RPC round-trips.
func _push_roster_to_owner(username: String) -> void:
	if not multiplayer.is_server():
		return
	var peer := _find_peer_id_for_username(username)
	if peer == 0:
		return  # offline / unknown
	if BotManager.is_bot(peer):
		return
	if peer == 1:
		# Host is also a client — fire the UI signal directly. UI binds to
		# client_roster_updated regardless of host/client role.
		client_roster_updated.emit()
		return
	sync_roster_to_client_rpc.rpc_id(peer, get_save_data(username))


## Owner-side: returns the roster the UI should display. Transparent across
## host (reads server state) and client (reads the mirrored copy).
func client_get_roster() -> Array:
	if multiplayer.is_server():
		var local := PlayerManager.get_player_node(1)
		if is_instance_valid(local):
			return get_roster(local.username)
		return []
	return _client_roster.get(KEY_PETS, [])


func client_get_summoned_ids() -> Array:
	if multiplayer.is_server():
		var local := PlayerManager.get_player_node(1)
		if is_instance_valid(local):
			return get_summoned_ids(local.username)
		return []
	return _client_roster.get(KEY_SUMMONED, [])


func client_find_pet(pet_uuid: String) -> Dictionary:
	for pet in client_get_roster():
		if pet.get(KEY_ID, "") == pet_uuid:
			return pet
	return {}


func client_is_pet_summoned(pet_uuid: String) -> bool:
	return client_get_summoned_ids().has(pet_uuid)


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
		KEY_LEARNED: [],  # kept for legacy reads; commands now derived from inventory slots
		KEY_ACTIVE_BUFF: "",
		KEY_INVENTORY: {
			KEY_AUTOPOT_HP: {},
			KEY_AUTOPOT_MP: {},
			KEY_CMD_AUTO_POT: {},
			KEY_CMD_BUFF: {},
			KEY_CMD_MAGNET: {},
		},
		KEY_AUTOPOT_CONFIG: {
			KEY_HP_THRESHOLD: 0.5,
			KEY_MP_THRESHOLD: 0.5,
		},
	}


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
			KEY_CMD_AUTO_POT: {},
			KEY_CMD_BUFF: {},
			KEY_CMD_MAGNET: {},
		}
	else:
		var inv: Dictionary = out[KEY_INVENTORY]
		for k in [KEY_AUTOPOT_HP, KEY_AUTOPOT_MP, KEY_CMD_AUTO_POT, KEY_CMD_BUFF, KEY_CMD_MAGNET]:
			if not inv.has(k):
				inv[k] = {}
		# Legacy storage_slots from earlier prototype — drop it; the player keeps
		# anything in main inventory. (No live testers had storage filled.)
		inv.erase("storage_slots")
	if not out.has(KEY_AUTOPOT_CONFIG):
		out[KEY_AUTOPOT_CONFIG] = {
			KEY_HP_THRESHOLD: 0.5,
			KEY_MP_THRESHOLD: 0.5,
		}
	return out


# Active-command derivation: a command is "active" while its matching book is
# in the pet's command slot. No separate learned_commands tracking.
static func get_active_commands(record: Dictionary) -> Array:
	var active: Array = []
	var inv: Dictionary = record.get(KEY_INVENTORY, {})
	if not inv.get(KEY_CMD_AUTO_POT, {}).is_empty():
		active.append(CMD_AUTO_POT)
	if not inv.get(KEY_CMD_BUFF, {}).is_empty():
		active.append(CMD_AUTOBUFF)
	if not inv.get(KEY_CMD_MAGNET, {}).is_empty():
		active.append(CMD_MAGNET)
	return active


static func is_command_active(record: Dictionary, command_id: String) -> bool:
	return get_active_commands(record).has(command_id)


## Returns the canonical book NAME that a command slot exclusively accepts.
## (Items in this project use UUID for `item_id` and the `name` field as the
## stable identifier — that's what ResourceManager keys by, that's what
## survives duplicate.)
static func book_name_for_slot(slot_key: String) -> String:
	match slot_key:
		KEY_CMD_AUTO_POT:
			return BOOK_AUTO_POT_NAME
		KEY_CMD_BUFF:
			return BOOK_AUTOBUFF_NAME
		KEY_CMD_MAGNET:
			return BOOK_MAGNET_NAME
		_:
			return ""


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
