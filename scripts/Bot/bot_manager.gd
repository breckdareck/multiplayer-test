extends Node

const BotBrain = preload("res://scripts/Bot/bot_brain.gd")
const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")
const BotDebugDraw = preload("res://scripts/Bot/bot_debug_draw.gd")
const BotCommandDispatcher = preload("res://scripts/Bot/bot_command_dispatcher.gd")

var bot_counter: int = 0
var active_bots: Dictionary = {}
var bot_config: Dictionary = {}
var _config_path: String = "res://config/bot_config.json"
var _used_names: Dictionary = {}
var _bot_def_map: Dictionary = {}  # { bot_id: bot_def Dictionary from config }
var _inspect_window: BotInspectWindow = null
## Server-side `/bot` command parser. Each sub-command is a focused method on
## the dispatcher so this autoload can stay focused on lifecycle and caching.
## Constructed in _ready() on the server only — never use on a client.
var _dispatcher: BotCommandDispatcher = null

## Emitted (on any peer) when a requested bot data snapshot arrives.
signal bot_snapshot_received(bot_id: int, snapshot: Dictionary)

const NAME_PREFIXES: Array[String] = [
	"Shadow", "Iron", "Storm", "Frost", "Fire", "Dark", "Silver", "Golden",
	"Brave", "Swift", "Wild", "Stone", "Moon", "Star", "Thunder", "Ice",
	"Crimson", "Azure", "Jade", "Ember", "Night", "Dawn", "Dusk", "Ash",
	"Blood", "Bone", "Wind", "Sky", "Sun", "Sea", "Tide", "Rain",
	"Mist", "Cloud", "Snow", "Hollow", "Grim", "Bright", "Pale", "Black",
	"Steel", "Copper", "Bronze", "Onyx", "Ruby", "Cinder", "Briar", "Oak",
	"Wolf", "Raven", "Drake", "Phoenix", "Tempest", "Bramble", "Glimmer", "Whisper",
	"Hex", "Rune", "Dread", "Lone",
]
const NAME_SUFFIXES: Array[String] = [
	"blade", "heart", "wind", "fang", "strike", "wolf", "hawk", "shield",
	"born", "walker", "fury", "soul", "flame", "guard", "fall", "forge",
	"bane", "claw", "storm", "song", "breaker", "thorn", "ridge", "vale",
	"mane", "bow", "hammer", "spire", "gale", "crest", "brand", "edge",
	"mark", "light", "tear", "kin", "ward", "gaze", "scar", "stalker",
	"runner", "slayer", "hunter", "weaver", "smith", "mantle", "bloom", "root",
	"seeker", "dancer", "mender", "scribe", "watcher", "rider", "glaive", "peak",
	"hollow", "reach", "mire", "fen",
]


func _ready() -> void:
	if not multiplayer.is_server():
		return
	_dispatcher = BotCommandDispatcher.new(self)
	# Defer bot spawning until the server and maps are ready.
	MultiplayerManager.server_has_started.connect(_on_server_started)
	# Recreate the debug overlay on the host's new map_instance after a map
	# change — the previous one was freed along with the old map.
	MapManager.player_spawned.connect(_on_player_spawned_for_debug_draw)


func _on_server_started() -> void:
	load_config(_config_path)
	if bot_config.get("auto_spawn", false):
		# Wait a few frames for the first map to load before spawning bots.
		await get_tree().create_timer(2.0).timeout
		_auto_spawn_bots()


func load_config(path: String) -> void:
	if not FileAccess.file_exists(path):
		#print("BotManager: No config file found at %s — using defaults." % path)
		bot_config = {}
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		bot_config = parsed
		#print("BotManager: Loaded config with %d bot definitions." % bot_config.get("bots", []).size())
	else:
		push_warning("BotManager: Failed to parse config at %s" % path)
		bot_config = {}


func _auto_spawn_bots() -> void:
	var bots_array: Array = bot_config.get("bots", [])
	var spawned_maps: Dictionary = {}
	# Stagger spawns so each bot's scene instantiation + initialization lands
	# in its own frame window. Spawning every bot in a single frame causes a
	# noticeable freeze at server start (worst with local save, where data
	# loading is synchronous and adds no natural delay between spawns).
	var stagger: float = bot_config.get("spawn_stagger", 0.5)
	for bot_def in bots_array:
		var raw_name: String = bot_def.get("name", "")
		var bot_name := raw_name if not raw_name.is_empty() and raw_name.to_lower() != "random" else generate_bot_name()
		var class_str: String = bot_def.get("class", "SWORDSMAN")
		var class_type: int = _class_string_to_type(class_str)
		var map_id: String = bot_def.get("map", bot_config.get("default_map", MapManager.DEFAULT_MAP))
		var bot_id := spawn_bot(bot_name, class_type, map_id)
		_bot_def_map[bot_id] = bot_def
		if not spawned_maps.has(map_id):
			spawned_maps[map_id] = []
		spawned_maps[map_id].append(bot_id)
		if stagger > 0.0:
			await get_tree().create_timer(stagger).timeout

	await get_tree().create_timer(3.0).timeout
	for map_id in spawned_maps:
		_form_squad_on_map(map_id, spawned_maps[map_id])


func spawn_bot(bot_name: String, class_type: int, map_id: String = "") -> int:
	if not multiplayer.is_server():
		push_warning("BotManager: spawn_bot called on client — ignored.")
		return 0

	if bot_name.is_empty():
		push_warning("BotManager: spawn_bot called with an empty name — ignored.")
		return 0

	if _is_name_taken(bot_name):
		push_warning("BotManager: bot name '%s' is already active — ignored." % bot_name)
		return 0

	if map_id.is_empty():
		map_id = bot_config.get("default_map", MapManager.DEFAULT_MAP)

	var bot_id := _get_next_bot_id()

	active_bots[bot_id] = {
		"username": bot_name,
		"class_type": class_type,
		"map_id": map_id,
		"brain": null,
	}

	#print("BotManager: Spawning bot '%s' (ID %d, class %s) on map '%s'" % [bot_name, bot_id, Constants.ClassType.find_key(class_type), map_id])

	_used_names[bot_name] = true
	PlayerManager.add_bot(bot_id, bot_name, class_type, map_id)
	return bot_id


func despawn_bot(bot_id: int) -> void:
	if bot_id not in active_bots:
		push_warning("BotManager: Bot ID %d not found." % bot_id)
		return

	var info = active_bots[bot_id]
	#print("BotManager: Despawning bot '%s' (ID %d)" % [info.username, bot_id])

	if PartyManager.get_player_party_id(bot_id) != -1:
		PartyManager.leave_party(bot_id)

	# The brain lives under BotManager, so free it explicitly — it is not a
	# child of the character node that remove_player tears down.
	var brain = info.get("brain")
	if is_instance_valid(brain):
		brain.queue_free()

	_used_names.erase(info.username)
	_bot_def_map.erase(bot_id)
	PlayerManager.remove_player(bot_id)
	active_bots.erase(bot_id)


func despawn_all_bots() -> void:
	for bot_id in active_bots.keys():
		despawn_bot(bot_id)


func is_bot(peer_id: int) -> bool:
	return peer_id < 0


## Returns true if the given username belongs to an active bot.
## Used by SaveManager, which keys players by username rather than peer ID.
func is_bot_username(username: String) -> bool:
	for bot_id in active_bots:
		if active_bots[bot_id].username == username:
			return true
	return false


func get_bot_ids() -> Array:
	return active_bots.keys()


func _get_next_bot_id() -> int:
	bot_counter -= 1
	return bot_counter


func _on_bot_spawned(bot_id: int) -> void:
	var player_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(player_node):
		push_error("BotManager: Could not find player node for bot %d after spawn." % bot_id)
		return

	# Send the bot's class/level sprite to clients already on its map — a bot's
	# appearance is never streamed via the node-addressed sprite RPC.
	MapManager.broadcast_player_appearance(bot_id)

	# A bot has no client and never opens a window — drop the entire UI subtree
	# (HUD, mobile buttons, debug panel, hotbar, buffbar, and the draggable
	# windows). Safe because inventory/equipment data lives in the components
	# (SlotData), not the windows. Only free once the inventory's SlotData has
	# been built (it is, by this point — load_player_inventory ran during spawn);
	# the guard is belt-and-braces against an unexpected spawn ordering.
	var inv = player_node.inventory_component
	var canvas_layer := player_node.get_node_or_null("CanvasLayer")
	if is_instance_valid(canvas_layer) and is_instance_valid(inv) and not inv.slots_data.is_empty():
		canvas_layer.queue_free()

	# A bot has no display — free its Camera2D so it can't compete with the
	# host's camera inside the map's shared SubViewport (the host is server+
	# client, so bot characters spawn in the same viewport as the host's body).
	var bot_camera := player_node.get_node_or_null("Camera2D")
	if is_instance_valid(bot_camera):
		bot_camera.queue_free()

	# The brain is parented to BotManager — not the character node — so it
	# survives the character being freed and recreated on every map change,
	# keeping its travel timers, patrol progress and cooldowns intact. On a map
	# change we just re-point the existing brain at the new body; only the bot's
	# first spawn constructs one.
	var brain: BotBrain = active_bots.get(bot_id, {}).get("brain")
	if is_instance_valid(brain):
		brain.attach_to_player(player_node)
	else:
		brain = BotBrain.new()
		brain.name = "BotBrain_%d" % abs(bot_id)
		add_child(brain)
		var behavior_cfg: Dictionary = bot_config.get("behavior", {}).duplicate()
		var bot_def := get_bot_definition(bot_id)
		if bot_def.has("patrol_route"):
			behavior_cfg["patrol_route"] = bot_def["patrol_route"]
		else:
			# Bots spawned via `/bot spawn` have no bot_def, so no configured
			# patrol_route. Without a route, `_should_change_map` on an unbanded
			# map (town) returns false — and since the first shop check sends
			# every fresh bot to town to "restock" (the discovery-trip assumption
			# in bot_economy._can_afford_potion), an unrouted bot lands in town
			# and is stuck there forever. Default to every banded map in
			# level order so manually-spawned bots have a way back out.
			behavior_cfg["patrol_route"] = _default_patrol_route()
		brain.init(player_node, bot_id, behavior_cfg)
		if bot_id in active_bots:
			active_bots[bot_id]["brain"] = brain

	if bot_id in active_bots:
		var current_map := MapManager.get_player_map(bot_id)
		if not current_map.is_empty():
			active_bots[bot_id]["map_id"] = current_map

	#print("BotManager: Bot %d brain attached and running." % bot_id)


# --- Client-side bot data sync (on-demand snapshots) ---

## [Client -> Server] Request a full data snapshot of a bot. The server
## replies via receive_bot_snapshot to the requester only.
@rpc("any_peer", "call_local", "reliable")
func request_bot_snapshot(bot_id: int) -> void:
	if not multiplayer.is_server():
		return
	var requester := multiplayer.get_remote_sender_id()
	if requester == 0:
		requester = multiplayer.get_unique_id()  # local (host) call
	receive_bot_snapshot.rpc_id(requester, bot_id, _gather_bot_snapshot(bot_id))


## [Server -> Client] Delivers a bot snapshot; listeners use bot_snapshot_received.
@rpc("authority", "call_local", "reliable")
func receive_bot_snapshot(bot_id: int, snapshot: Dictionary) -> void:
	bot_snapshot_received.emit(bot_id, snapshot)


## Server-side: collects a bot's full state into an RPC-serializable Dictionary.
func _gather_bot_snapshot(bot_id: int) -> Dictionary:
	var node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(node):
		return {}

	var snap: Dictionary = {
		"name": node.username,
		"class": node.class_component.current_class if is_instance_valid(node.class_component) else 0,
		"level": node.level_component.level if is_instance_valid(node.level_component) else 1,
		"hp": node.health_component.current_health if is_instance_valid(node.health_component) else 0,
		"max_hp": node.health_component.max_health if is_instance_valid(node.health_component) else 0,
		"mp": node.mana_component.current_mana if is_instance_valid(node.mana_component) else 0,
		"max_mp": node.mana_component.max_mana if is_instance_valid(node.mana_component) else 0,
		"gold": node.player_inventory.monies_amount if is_instance_valid(node.player_inventory) else 0,
		"map": MapManager.get_player_map(bot_id),
		"action": "",
	}

	var brain := get_bot_brain(bot_id)
	if brain:
		snap["action"] = brain.current_action

	# Equipment — keyed by str(equipment key); {} for an empty slot.
	var eq: Dictionary = {}
	if is_instance_valid(node.equipment_component):
		for key in node.equipment_component.slots_data:
			var esd: SlotData = node.equipment_component.slots_data[key]
			eq[str(key)] = esd.item.to_dictionary() if esd and esd.item else {}
	snap["equipment"] = eq

	# Inventory — non-empty slots only.
	var inv: Array = []
	if is_instance_valid(node.inventory_component):
		var slot_list: Array = node.inventory_component.get_slots()
		for i in slot_list.size():
			if slot_list[i].item:
				inv.append({"slot_index": i, "item": slot_list[i].item.to_dictionary()})
	snap["inventory"] = inv

	# Stats — total/base/bonus per StatType.
	var stats: Dictionary = {}
	if is_instance_valid(node.stats_component):
		for stat_type in node.stats_component.stats:
			var stat: StatData = node.stats_component.stats[stat_type]
			stats[stat_type] = {
				"total": stat.total_value,
				"base": stat.base_value,
				"bonus": stat.combined_bonus_value,
			}
	snap["stats"] = stats

	return snap


func _form_squad_on_map(_map_id: String, bot_ids: Array) -> void:
	if bot_ids.size() < 2:
		return

	var leader_id: int = bot_ids[0]
	var party_id := PartyManager.create_party(leader_id)
	if party_id == -1:
		return

	for i in range(1, bot_ids.size()):
		PartyManager.send_invite(leader_id, bot_ids[i])

	#print("BotManager: Formed squad (party %d) on map '%s' with %d bots." % [party_id, map_id, bot_ids.size()])


func get_bot_definition(bot_id: int) -> Dictionary:
	return _bot_def_map.get(bot_id, {})


## The persistent BotBrain node for a bot, or null. The brain is parented to
## BotManager (not the bot's character node), so it survives map changes.
func get_bot_brain(bot_id: int) -> BotBrain:
	var brain = active_bots.get(bot_id, {}).get("brain")
	return brain if is_instance_valid(brain) else null


## Cached platform-navigation graph per map. Map geometry is static, so a graph
## is built once and shared by every bot on that map (and survives the map node
## being recreated by a channel switch — the graph stores positions, not refs).
var _nav_graphs: Dictionary = {}
## The navigation debug overlay node, created lazily by `/bot debugdraw`. Lives
## as a child of the host's current map_instance so it shares that map's
## SubViewport / World2D / camera transform — a Node2D under /root would draw
## into the root viewport (no camera) and end up off-screen.
var _debug_draw: Node2D = null
## Persisted across overlay recreations. The host's map_instance is freed on
## every map change, taking _debug_draw with it; we rebuild on the new map
## from these cached toggles so the user's settings survive the switch.
var _debug_draw_enabled: bool = false
var _debug_draw_show_graph: bool = true
var _debug_draw_show_paths: bool = true
var _debug_draw_show_bot_info: bool = true
## Probe columns advanced per frame for in-progress nav-graph builds — keeps the
## thousands of build raycasts from hitching a single frame.
const NAV_BUILD_COLUMNS_PER_FRAME: int = 12

## The nav graph for a map. The first request kicks off an incremental build
## (amortized in _process) and returns null; null is also returned while a build
## is still running, so the caller falls back to direct navigation until ready.
func get_nav_graph(map_id: String, map_node: Node2D, max_jump: float, jump_reach: float) -> BotNavGraph:
	var cached: BotNavGraph = _nav_graphs.get(map_id)
	if cached != null:
		return cached if cached.built else null
	var graph := BotNavGraph.new()
	if not graph.begin_build(map_node, max_jump, jump_reach):
		return null  # physics not live yet — a later request retries
	_nav_graphs[map_id] = graph
	return null


func _process(_delta: float) -> void:
	if not multiplayer.is_server():
		return
	_step_nav_graph_builds()
	_update_watch_camera()


## Drives in-progress nav-graph builds a slice at a time, and cleans up builds
## that produced nothing or were aborted by the map being freed.
func _step_nav_graph_builds() -> void:
	if _nav_graphs.is_empty():
		return
	for map_id in _nav_graphs:
		var graph: BotNavGraph = _nav_graphs[map_id]
		if graph.built:
			continue
		if graph.is_building():
			graph.build_step(NAV_BUILD_COLUMNS_PER_FRAME)
			# A finished build with no surfaces is useless — drop it so a later
			# request rebuilds (covers a probe that ran before physics settled).
			if graph.built and graph.points.size() == 0:
				_nav_graphs.erase(map_id)
		else:
			# Build aborted (map freed mid-build) — drop it so it retries.
			_nav_graphs.erase(map_id)
		break  # one graph per frame is plenty


## Camera-follow a bot for debugging. watch_bot(0) stops and restores the host
## camera. Host-only — peer 1's player owns the active viewport camera there.
var _watched_bot: int = 0
var _watch_saved_cam_pos: Vector2 = Vector2.ZERO
var _watch_cam_saved: bool = false

func watch_bot(bot_id: int) -> void:
	if bot_id == _watched_bot:
		return
	if bot_id == 0:
		_restore_watch_camera()
	_watched_bot = bot_id


## ID of the bot the debug camera is following, or 0.
func get_watched_bot() -> int:
	return _watched_bot


func _restore_watch_camera() -> void:
	if not _watch_cam_saved:
		return
	var host := PlayerManager.get_player_node(1)
	if is_instance_valid(host) and is_instance_valid(host.camera):
		host.camera.position = _watch_saved_cam_pos
		# Reinstate the current map's camera bounds (they were widened to let the
		# follow camera move freely). _apply_map_camera_bounds re-reads the active
		# MapBase, so it handles the case where the host changed maps mid-watch.
		if host.has_method("_apply_map_camera_bounds"):
			host._apply_map_camera_bounds(host.camera)
	_watch_cam_saved = false


func _update_watch_camera() -> void:
	if _watched_bot == 0:
		return
	if not active_bots.has(_watched_bot):
		watch_bot(0)  # bot despawned — stop following
		return
	var bot := PlayerManager.get_player_node(_watched_bot)
	var host := PlayerManager.get_player_node(1)
	if not is_instance_valid(bot) or not is_instance_valid(host) or not is_instance_valid(host.camera):
		return
	if not _watch_cam_saved:
		_watch_saved_cam_pos = host.camera.position
		_watch_cam_saved = true
	# Widen the camera limits every frame: the per-map MapBase bounds otherwise
	# clamp the follow camera, and a mid-watch map change would re-apply them.
	host.camera.limit_left = -10000000
	host.camera.limit_top = -10000000
	host.camera.limit_right = 10000000
	host.camera.limit_bottom = 10000000
	host.camera.global_position = bot.global_position


## The cached nav graph for a map (built or still building), for debug tooling.
func debug_nav_graph(map_id: String) -> BotNavGraph:
	return _nav_graphs.get(map_id)


## The debug-draw overlay node, or null if it hasn't been created yet.
func get_debug_draw() -> Node:
	return _debug_draw if is_instance_valid(_debug_draw) else null


# --- Per-frame enemy cache. Every bot scans the global "Enemies" group; this
# caches the alive-enemies-per-map list once per frame so N bots on a map share
# a single scan instead of each re-querying and re-filtering. ---
var _enemy_cache: Dictionary = {}      ## map_id -> Array of live EnemyBase
var _enemy_cache_frame: int = -1

## Alive enemies on a map, cached for the current frame. Bots apply their own
## per-bot filters (blacklist, distance) on top of this shared list.
func get_enemies_on_map(map_id: String, map_node: Node) -> Array:
	var frame := Engine.get_process_frames()
	if frame != _enemy_cache_frame:
		_enemy_cache.clear()
		_enemy_cache_frame = frame
	if _enemy_cache.has(map_id):
		return _enemy_cache[map_id]

	var list: Array = []
	if is_instance_valid(map_node):
		for node in get_tree().get_nodes_in_group("Enemies"):
			if node is not EnemyBase or not is_instance_valid(node):
				continue
			if not map_node.is_ancestor_of(node):
				continue
			if node.health_component and node.health_component.is_dead:
				continue
			list.append(node)
	_enemy_cache[map_id] = list
	return list


func get_map_difficulty(map_id: String) -> Dictionary:
	return bot_config.get("map_difficulty", {}).get(map_id, {})


## Patrol route fallback for bots spawned without a configured route: every map
## that has a difficulty band, sorted by min_level so the bot walks the ladder
## from low to high rather than dictionary insertion order.
func _default_patrol_route() -> Array:
	var entries: Array = []
	var difficulties: Dictionary = bot_config.get("map_difficulty", {})
	for map_id in difficulties:
		entries.append({"map_id": map_id, "min_level": int(difficulties[map_id].get("min_level", 0))})
	entries.sort_custom(func(a, b): return a.min_level < b.min_level)
	var route: Array = []
	for e in entries:
		route.append(e.map_id)
	return route


func generate_bot_name() -> String:
	for _attempt in 30:
		var candidate = NAME_PREFIXES.pick_random() + NAME_SUFFIXES.pick_random()
		if not _is_name_taken(candidate):
			_used_names[candidate] = true
			return candidate
	# Tie the fallback to the bot counter, which monotonically decrements on
	# every spawn — guaranteed unique even if the random pool is exhausted.
	var fallback := "Bot_%d" % abs(bot_counter - 1)
	while _is_name_taken(fallback):
		fallback += "_x"
	_used_names[fallback] = true
	return fallback


## True when a bot with this name (case-insensitive) is currently active.
## Checks active_bots directly rather than _used_names so the answer matches
## what `/bot list` shows, even if _used_names ever drifts out of sync.
func _is_name_taken(bot_name: String) -> bool:
	var lower := bot_name.to_lower()
	for info in active_bots.values():
		if String(info.get("username", "")).to_lower() == lower:
			return true
	return false


func _class_string_to_type(class_str: String) -> int:
	match class_str.to_upper():
		"SWORDSMAN": return Constants.ClassType.SWORDSMAN
		"ARCHER": return Constants.ClassType.ARCHER
		"MAGE": return Constants.ClassType.MAGE
		"ROGUE": return Constants.ClassType.ROGUE
		_: return Constants.ClassType.SWORDSMAN


## Dispatches a parsed /bot command. Forwards to the BotCommandDispatcher,
## which owns every sub-command handler. `requester_id` is the peer that issued
## the command (server peer id for a host call); it lets subcommands like
## `inspect` route UI back to the requesting client rather than always the host.
func handle_command(args: Array, requester_id: int = 0) -> String:
	if _dispatcher == null:
		# Client side, or pre-_ready — the autoload still exists so this can be
		# reached, but there's nothing to dispatch to.
		return ""
	return _dispatcher.handle_command(args, requester_id)


## Creates the overlay node under the host's current map_instance, or moves it
## there if it lives under a stale parent. Sub-layer toggles are restored from
## the BotManager-side cache so they persist across map changes.
func _ensure_debug_draw_node() -> void:
	var parent: Node = MapManager.current_map_instance
	if not is_instance_valid(parent):
		return
	if is_instance_valid(_debug_draw) and _debug_draw.get_parent() == parent:
		_debug_draw.enabled = true
		return
	if is_instance_valid(_debug_draw):
		_debug_draw.queue_free()
	_debug_draw = BotDebugDraw.new()
	_debug_draw.name = "BotDebugDraw"
	_debug_draw.show_graph = _debug_draw_show_graph
	_debug_draw.show_paths = _debug_draw_show_paths
	_debug_draw.show_bot_info = _debug_draw_show_bot_info
	parent.add_child(_debug_draw)
	_debug_draw.enabled = true


func _on_player_spawned_for_debug_draw(player_id: int) -> void:
	if player_id != 1 or not _debug_draw_enabled:
		return
	_ensure_debug_draw_node()


## Updates a sub-layer toggle. Writes through to the live overlay AND the cache
## so the choice survives the next host map change (which recreates the node).
func set_debug_draw_layer(layer: String, value: bool) -> void:
	match layer:
		"graph": _debug_draw_show_graph = value
		"paths": _debug_draw_show_paths = value
		"info":  _debug_draw_show_bot_info = value
		_: return
	if not is_instance_valid(_debug_draw):
		return
	match layer:
		"graph": _debug_draw.show_graph = value
		"paths": _debug_draw.show_paths = value
		"info":  _debug_draw.show_bot_info = value


## [Server -> Client] Tells the requesting client to open its own bot inspect window.
@rpc("authority", "call_remote", "reliable")
func open_bot_inspect_window(bot_id: int) -> void:
	open_inspect_window(bot_id)


func open_inspect_window(bot_id: int) -> void:
	if not is_instance_valid(_inspect_window):
		_inspect_window = BotInspectWindow.create()
		# Add to the host player's MoveableWindows container
		var host_id := multiplayer.get_unique_id()
		var host_node := PlayerManager.get_player_node(host_id)
		if is_instance_valid(host_node):
			var moveable_container = host_node.get_node_or_null("CanvasLayer/MoveableWindows")
			if moveable_container:
				moveable_container.add_child(_inspect_window)
			else:
				host_node.get_node("CanvasLayer").add_child(_inspect_window)
		else:
			get_tree().root.add_child(_inspect_window)
	_inspect_window.show_bot(bot_id)
