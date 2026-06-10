extends Node

const BotBrain = preload("res://scripts/Bot/bot_brain.gd")
const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")
const BotDebugDraw = preload("res://scripts/Bot/bot_debug_draw.gd")

var bot_counter: int = 0
var active_bots: Dictionary = {}
var bot_config: Dictionary = {}
var _config_path: String = "res://config/bot_config.json"
var _used_names: Dictionary = {}
var _bot_def_map: Dictionary = {}  # { bot_id: bot_def Dictionary from config }
var _inspect_window: BotInspectWindow = null

# --- Ambient population (ADR 0011): personality archetypes + identity roster ---
## Archetype table (chattiness + per-event line pools), data not code.
var _personalities: Dictionary = {}
## Shared banter topics: each entry pairs ONE opener with replies that actually
## answer it — exchanges are coherent by construction, unlike the old
## independent per-archetype open/reply pools (any open could draw any reply).
var _banter_topics: Array = []
var _personalities_path: String = "res://config/bot_personalities.json"
## Server-side identity roster: persists the personality a random bot rolled so
## it stays recognizable across sessions. Deliberately NOT a backend column —
## see docs/adr/0011-bot-ambient-population.md.
var _roster: Dictionary = {}
var _roster_path: String = "res://saves/bot_roster.json"
var _roster_loaded: bool = false
## Bots whose spawn found NO existing save row — they get a one-time level/gold
## seed in _on_bot_spawned so a cold-start server has a leveled population
## instead of twenty newborns. Set by PlayerManager.add_bot.
var _fresh_bots: Dictionary = {}
## Login/logout churn timer (ADR 0012) — the population changes over a session.
var _churn_timer: float = 0.0
## Bot-to-bot banter timer (ADR 0012) — overheard conversation for an audience.
var _banter_timer: float = 0.0
const BANTER_INTERVAL_MIN: float = 60.0
const BANTER_INTERVAL_MAX: float = 140.0
## The two bots must be near each other to read as a conversation.
const BANTER_PAIR_RANGE: float = 350.0

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
	# Defer bot spawning until the server and maps are ready.
	MultiplayerManager.server_has_started.connect(_on_server_started)
	# Recreate the debug overlay on the host's new map_instance after a map
	# change — the previous one was freed along with the old map.
	MapManager.player_spawned.connect(_on_player_spawned_for_debug_draw)


func _on_server_started() -> void:
	load_config(_config_path)
	_load_personalities()
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

	# Stamp last_seen so churn re-login and offline catch-up know when this
	# identity was last in the world.
	_touch_roster(info.username, info.class_type, String(info.get("personality", "")))

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
	_stress_active = false
	_stress_bot_ids.clear()
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

	# ADR 0009 Stage B: the body no longer carries a CanvasLayer UI subtree (it was
	# lifted into the persistent per-client LocalPlayerUI layer, which is never
	# created for a bot). So the old "free the bot's CanvasLayer" hack is gone — a
	# bot body spawns lean, with no UI to drop.

	# A bot has no display — free its Camera2D so it can't compete with the
	# host's camera inside the map's shared SubViewport (the host is server+
	# client, so bot characters spawn in the same viewport as the host's body).
	var bot_camera := player_node.get_node_or_null("Camera2D")
	if is_instance_valid(bot_camera):
		bot_camera.queue_free()

	# Resolve the bot's personality once (config > roster > persisted roll),
	# then stamp the full roster identity (class + last_seen) so churn and
	# offline catch-up know this name. The PREVIOUS last_seen is captured
	# first — the stamp would otherwise zero the downtime catch-up measures.
	var first_session_spawn: bool = bot_id in active_bots and not active_bots[bot_id].has("personality")
	var prev_last_seen: int = 0
	if first_session_spawn:
		if not _roster_loaded:
			_load_roster()
		prev_last_seen = int(_roster.get(active_bots[bot_id]["username"], {}).get("last_seen", 0))
		active_bots[bot_id]["personality"] = _resolve_personality_key(
			active_bots[bot_id]["username"], get_bot_definition(bot_id))
		_touch_roster(active_bots[bot_id]["username"], active_bots[bot_id]["class_type"],
				String(active_bots[bot_id]["personality"]))

	# Level pumps run BEFORE the brain attaches — they fire dozens of level-up
	# signals, and pre-brain means no speech hook hears them.
	if _fresh_bots.has(bot_id):
		_fresh_bots.erase(bot_id)
		_seed_fresh_bot(bot_id)
	elif first_session_spawn and prev_last_seen > 0:
		_apply_offline_catchup(bot_id, prev_last_seen)

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
	brain.personality = get_bot_personality(bot_id)

	if bot_id in active_bots:
		var current_map := MapManager.get_player_map(bot_id)
		if not current_map.is_empty():
			active_bots[bot_id]["map_id"] = current_map

	#print("BotManager: Bot %d brain attached and running." % bot_id)


## [Server] Re-point a bot's brain at its character after a map-change REPARENT
## (ADR 0008). The body is the SAME live node (never freed), so this only resets
## the brain's transient targets / nav path for the new map while preserving
## travel, patrol and cooldown progress. Unlike _on_bot_spawned, there is no UI
## or camera to free — the node persisted intact.
func handle_bot_reparented(bot_id: int) -> void:
	var node := PlayerManager.get_player_node(bot_id)
	var brain: BotBrain = active_bots.get(bot_id, {}).get("brain")
	if is_instance_valid(brain) and is_instance_valid(node):
		brain.attach_to_player(node)
	if bot_id in active_bots:
		var current_map := MapManager.get_player_map(bot_id)
		if not current_map.is_empty():
			active_bots[bot_id]["map_id"] = current_map


# --- Personality archetypes + identity roster (ADR 0011) ---

func _load_personalities() -> void:
	_personalities = {}
	_banter_topics = []
	if not FileAccess.file_exists(_personalities_path):
		return
	var file := FileAccess.open(_personalities_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_personalities = parsed.get("archetypes", {})
		_banter_topics = parsed.get("banter", [])
	else:
		push_warning("BotManager: Failed to parse %s" % _personalities_path)


func _load_roster() -> void:
	_roster_loaded = true
	_roster = {}
	if not FileAccess.file_exists(_roster_path):
		return
	var file := FileAccess.open(_roster_path, FileAccess.READ)
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		_roster = parsed


func _save_roster() -> void:
	DirAccess.make_dir_recursive_absolute("res://saves")
	var file := FileAccess.open(_roster_path, FileAccess.WRITE)
	if file == null:
		push_warning("BotManager: Could not write roster to %s" % _roster_path)
		return
	file.store_string(JSON.stringify(_roster, "  "))
	file.close()


## The personality archetype KEY for a bot: an authored `personality` in its
## config entry wins; otherwise the roster's persisted roll; otherwise roll one
## now and persist it so this name keeps its personality across sessions.
func _resolve_personality_key(bot_name: String, bot_def: Dictionary) -> String:
	if _personalities.is_empty():
		return ""
	var authored: String = bot_def.get("personality", "")
	if not authored.is_empty() and _personalities.has(authored):
		return authored
	if not _roster_loaded:
		_load_roster()
	var rostered: String = _roster.get(bot_name, {}).get("personality", "")
	if not rostered.is_empty() and _personalities.has(rostered):
		return rostered
	var keys: Array = _personalities.keys()
	var rolled: String = keys.pick_random()
	_roster[bot_name] = {"personality": rolled}
	_save_roster()
	return rolled


## The full archetype Dictionary ({chattiness, lines}) a bot speaks with, plus
## its key under "key". Empty Dictionary when personalities are unavailable.
func get_bot_personality(bot_id: int) -> Dictionary:
	var key: String = active_bots.get(bot_id, {}).get("personality", "")
	if key.is_empty() or not _personalities.has(key):
		return {}
	var archetype: Dictionary = _personalities[key].duplicate()
	archetype["key"] = key
	return archetype


## Swaps a live bot's personality and persists the choice in the roster. Note:
## a config-authored "personality" on the bot's entry still wins on the NEXT
## spawn — this is a live/runtime override for testing and for random bots.
func set_bot_personality(bot_id: int, key: String) -> bool:
	if not _personalities.has(key) or not active_bots.has(bot_id):
		return false
	active_bots[bot_id]["personality"] = key
	var brain := get_bot_brain(bot_id)
	if brain != null:
		brain.personality = get_bot_personality(bot_id)
	_touch_roster(active_bots[bot_id]["username"], active_bots[bot_id]["class_type"], key)
	return true


## "5m ago"-style relative timestamp for roster output.
func _format_ago(unix: int) -> String:
	if unix <= 0:
		return "never"
	var secs: int = int(Time.get_unix_time_from_system()) - unix
	if secs < 60:
		return "%ds ago" % maxi(secs, 0)
	if secs < 3600:
		return "%dm ago" % (secs / 60)
	if secs < 86400:
		return "%dh ago" % (secs / 3600)
	return "%dd ago" % (secs / 86400)


## Writes/refreshes a bot's roster identity (personality, class, last_seen).
## The roster is what lets churn re-login an identity faithfully and what
## offline catch-up measures downtime against (ADR 0012).
func _touch_roster(bot_name: String, class_type: int, personality_key: String) -> void:
	if not _roster_loaded:
		_load_roster()
	var entry: Dictionary = _roster.get(bot_name, {})
	if not personality_key.is_empty():
		entry["personality"] = personality_key
	entry["class"] = Constants.ClassType.find_key(class_type)
	entry["last_seen"] = Time.get_unix_time_from_system()
	_roster[bot_name] = entry
	_save_roster()


# --- Reputation (ADR 0012): per-bot, per-player familiarity in the roster ---

## Bumps how well a bot knows a player (parties shared, trades). Drives the
## tiered greeting pools — the cross-session "Bob remembers me" payoff.
func add_reputation(bot_id: int, player_username: String, amount: int) -> void:
	if not active_bots.has(bot_id) or player_username.is_empty():
		return
	if not _roster_loaded:
		_load_roster()
	var bot_name: String = active_bots[bot_id].username
	var entry: Dictionary = _roster.get(bot_name, {})
	var rep: Dictionary = entry.get("rep", {})
	rep[player_username] = int(rep.get(player_username, 0)) + amount
	entry["rep"] = rep
	_roster[bot_name] = entry
	_save_roster()


func get_reputation(bot_id: int, player_username: String) -> int:
	var bot_name: String = active_bots.get(bot_id, {}).get("username", "")
	if bot_name.is_empty():
		return 0
	if not _roster_loaded:
		_load_roster()
	return int(_roster.get(bot_name, {}).get("rep", {}).get(player_username, 0))


# --- Login/logout churn (ADR 0012) ---

func _step_churn(delta: float) -> void:
	var cfg: Dictionary = bot_config.get("churn", {})
	if not cfg.get("enabled", false):
		return
	_churn_timer -= delta
	if _churn_timer > 0.0:
		return
	_churn_timer = randf_range(float(cfg.get("interval_min", 180.0)), float(cfg.get("interval_max", 420.0)))
	_churn_tick(cfg)


## One churn event: log an offline identity in, or an online bot off. The
## feed notice goes to EVERY real player — login churn is global server
## texture, not map-scoped chatter.
func _churn_tick(cfg: Dictionary) -> void:
	var min_online: int = int(cfg.get("min_online", 2))
	var max_online: int = int(cfg.get("max_online", 8))
	var offline: Array = _offline_identities()
	var logout_pool: Array = _logout_candidates()
	var can_login: bool = active_bots.size() < max_online and not offline.is_empty()
	var can_logout: bool = active_bots.size() > min_online and not logout_pool.is_empty()
	if not can_login and not can_logout:
		return
	var do_login: bool = can_login if not (can_login and can_logout) else randf() < 0.5

	if do_login:
		var pick: Dictionary = offline.pick_random()
		var bot_id := spawn_bot(pick.name, pick.class_type, "")
		if bot_id == 0:
			return
		# Re-link the config definition (patrol route etc.) for authored names.
		for bot_def in bot_config.get("bots", []):
			if String(bot_def.get("name", "")) == pick.name:
				_bot_def_map[bot_id] = bot_def
				break
		_broadcast_system_to_players("%s has logged in." % pick.name, Color(0.6, 0.85, 0.6))
	else:
		var out_id: int = logout_pool.pick_random()
		var out_name: String = active_bots[out_id].username
		despawn_bot(out_id)
		_broadcast_system_to_players("%s has logged off." % out_name, Color(0.65, 0.65, 0.65))


## Identities that could "log in": authored config bots + every roster name,
## minus whoever is already online.
func _offline_identities() -> Array:
	var out: Array = []
	var seen: Dictionary = {}
	for bot_def in bot_config.get("bots", []):
		var bot_name: String = bot_def.get("name", "")
		if bot_name.is_empty() or bot_name.to_lower() == "random" \
				or _is_name_taken(bot_name) or seen.has(bot_name):
			continue
		seen[bot_name] = true
		out.append({"name": bot_name, "class_type": _class_string_to_type(bot_def.get("class", "SWORDSMAN"))})
	if not _roster_loaded:
		_load_roster()
	for bot_name in _roster:
		if _is_name_taken(bot_name) or seen.has(bot_name):
			continue
		seen[bot_name] = true
		out.append({"name": bot_name, "class_type": _class_string_to_type(String(_roster[bot_name].get("class", "SWORDSMAN")))})
	return out


## Online bots that may churn out: never a real player's groupmate, never a
## commanded companion, never a stress-test bot.
func _logout_candidates() -> Array:
	var out: Array = []
	for bot_id in active_bots:
		if bot_id in _stress_bot_ids:
			continue
		var party_id := PartyManager.get_player_party_id(bot_id)
		if party_id != -1 and PartyManager._party_has_real_player(party_id):
			continue
		var brain := get_bot_brain(bot_id)
		if brain != null and not brain.companion_mode.is_empty():
			continue
		# Mid-invite bots stay online — churning one out dissolves the party
		# the player is about to accept into.
		if brain != null and brain._pending_player_invite_timer > 0.0:
			continue
		out.append(bot_id)
	return out


## System line to every connected real player.
func _broadcast_system_to_players(text: String, color: Color) -> void:
	for pid in PlayerManager.active_players:
		if not is_bot(pid):
			ChatManager.notify_peer(pid, text, color)


# --- Bot-to-bot banter (ADR 0012) ---

func _step_banter(delta: float) -> void:
	_banter_timer -= delta
	if _banter_timer > 0.0:
		return
	_banter_timer = randf_range(BANTER_INTERVAL_MIN, BANTER_INTERVAL_MAX)
	_banter_tick()


## Scripts one overheard exchange: two near-each-other bots on a map that has
## a real-player audience — one opens, the other answers after the speech gap
## has cleared. No audience -> no banter; it exists to be overheard. Returns a
## status line so `/bot banter` can report what happened.
func _banter_tick() -> String:
	var by_map: Dictionary = {}
	for bot_id in active_bots:
		var map_id := MapManager.get_player_map(bot_id)
		if map_id.is_empty() or MapManager.get_real_players_on_map(map_id).is_empty():
			continue
		if not by_map.has(map_id):
			by_map[map_id] = []
		by_map[map_id].append(bot_id)

	var candidate_maps: Array = []
	for map_id in by_map:
		if by_map[map_id].size() >= 2:
			candidate_maps.append(map_id)
	if candidate_maps.is_empty():
		return "No map has both an audience and 2+ bots."

	var bots: Array = by_map[candidate_maps.pick_random()]
	bots.shuffle()
	for i in bots.size():
		var node_a := PlayerManager.get_player_node(bots[i])
		if not is_instance_valid(node_a):
			continue
		for j in range(i + 1, bots.size()):
			var node_b := PlayerManager.get_player_node(bots[j])
			if not is_instance_valid(node_b):
				continue
			if node_a.global_position.distance_to(node_b.global_position) > BANTER_PAIR_RANGE:
				continue
			_run_banter(bots[i], bots[j], node_a.username, node_b.username)
			return "Banter: %s -> %s." % [node_a.username, node_b.username]
	return "No two bots within %dpx of each other." % int(BANTER_PAIR_RANGE)


## One scripted exchange from the shared topic table: A opens, B answers with a
## reply written FOR that opener. Delivered straight through bot_say (budget
## applies); the reply waits out the global speech gap so both lines clear it.
func _run_banter(id_a: int, id_b: int, name_a: String, name_b: String) -> void:
	if _banter_topics.is_empty():
		return
	var topic: Dictionary = _banter_topics.pick_random()
	var map_name: String = MapManager._map_display_name(MapManager.get_player_map(id_a))
	var open_text: String = String(topic.get("open", "")).format({"player": name_b, "map": map_name})
	if open_text.is_empty() or not ChatManager.bot_say(id_a, open_text):
		return
	await get_tree().create_timer(ChatManager.BOT_SPEECH_GLOBAL_GAP + randf_range(1.0, 2.5)).timeout
	var replies: Array = topic.get("replies", [])
	if replies.is_empty():
		return
	var reply_text: String = String(replies.pick_random()).format({"player": name_a, "map": map_name})
	ChatManager.bot_say(id_b, reply_text)


# --- Level-up congratulations (ADR 0012 texture) ---

## How close a bot must be to the leveler to notice the ding.
const GRATS_RANGE: float = 500.0

## A character leveled up where bots could see it — a nearby bot may answer
## with a "grats" line. Called from BotBrain._on_leveled_up when a BOT's own
## level_up line was actually delivered (`spoke` true), and from
## LevelingComponent for PLAYER dings (the level-up flash + sound are visible
## map-wide, so a grats needs no preceding chat line).
func queue_grats(leveler_id: int, level: int, spoke: bool) -> void:
	if not multiplayer.is_server():
		return
	# Sometimes, not every ding — milestone levels always get the cheer.
	if level % 10 != 0 and randf() < 0.5:
		return
	_deliver_grats(leveler_id, level, spoke)


func _deliver_grats(leveler_id: int, level: int, spoke: bool) -> void:
	# After the leveler's own line clears the speech budget (bot levelers), or
	# a natural beat after the ding (player levelers).
	var delay: float = ChatManager.BOT_SPEECH_GLOBAL_GAP + randf_range(0.8, 2.2) \
			if spoke else randf_range(1.5, 3.0)
	await get_tree().create_timer(delay).timeout

	var leveler := PlayerManager.get_player_node(leveler_id)
	if not is_instance_valid(leveler):
		return
	var map_id := MapManager.get_player_map(leveler_id)
	if map_id.is_empty():
		return
	var candidates: Array = []
	for bot_id in active_bots:
		if bot_id == leveler_id:
			continue
		if MapManager.get_player_map(bot_id) != map_id:
			continue
		var node := PlayerManager.get_player_node(bot_id)
		if not is_instance_valid(node):
			continue
		if node.global_position.distance_to(leveler.global_position) > GRATS_RANGE:
			continue
		candidates.append(bot_id)
	if candidates.is_empty():
		return
	var brain := get_bot_brain(candidates.pick_random())
	if brain != null:
		brain.try_speak("grats", {"player": leveler.username, "level": level}, true)


# --- Cold-start seeding (ADR 0011) ---

## Flags a bot whose data load found no save row. Called by PlayerManager.add_bot
## before the spawn handshake; consumed once in _on_bot_spawned.
func mark_bot_fresh(bot_id: int) -> void:
	_fresh_bots[bot_id] = true


## One-time seed for a brand-new bot (no save row): level it into a difficulty
## band so the population reads as a lived-in server, and grant band-appropriate
## gold so the existing restock/equip logic can gear it up on its first town
## trip. Runs AFTER JoinHandshake (components live, load complete), and goes
## through pump_bot_to_level — the same EXP+mastery path as /bot set_level — so
## the ability/attribute point-reconcile invariant holds.
func _seed_fresh_bot(bot_id: int) -> void:
	var player_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.level_component):
		return

	var bot_def := get_bot_definition(bot_id)
	var target_level: int = int(bot_def.get("seed_level", 0))
	if target_level <= 0:
		# Pick a band: the spawn map's if it has one, else a random banded map
		# from the patrol route (config bots start in town, which is unbanded).
		var band := get_map_difficulty(MapManager.get_player_map(bot_id))
		if band.is_empty():
			var banded: Array = []
			for map_id in bot_def.get("patrol_route", _default_patrol_route()):
				if not get_map_difficulty(map_id).is_empty():
					banded.append(map_id)
			if not banded.is_empty():
				band = get_map_difficulty(banded.pick_random())
		if band.is_empty():
			return  # nowhere to anchor a seed — stay level 1
		target_level = randi_range(int(band.get("min_level", 1)), int(band.get("max_level", 1)))

	var cap: int = int(bot_config.get("seed_max_level", 0))
	if cap > 0:
		target_level = mini(target_level, cap)
	if target_level <= player_node.level_component.level:
		return

	pump_bot_to_level(player_node, target_level)
	if is_instance_valid(player_node.player_inventory):
		player_node.player_inventory.monies_amount += target_level * 40


## A returning bot "kept playing" while it was offline (ADR 0012): downtime
## since the roster's last_seen converts to levels through the same
## EXP+mastery pump as seeding, so the point-reconcile invariant holds. The
## world keeps living between host sessions.
func _apply_offline_catchup(bot_id: int, last_seen_unix: int) -> void:
	var cfg: Dictionary = bot_config.get("offline_progression", {})
	if not cfg.get("enabled", false):
		return
	var player_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.level_component):
		return
	var hours: float = maxf(0.0, (Time.get_unix_time_from_system() - last_seen_unix) / 3600.0)
	var gained: int = mini(int(hours * float(cfg.get("levels_per_hour", 0.25))), int(cfg.get("max_catchup", 8)))
	if gained <= 0:
		return
	var target: int = player_node.level_component.level + gained
	var cap: int = int(bot_config.get("seed_max_level", 0))
	if cap > 0:
		target = mini(target, cap)
	pump_bot_to_level(player_node, target)
	if is_instance_valid(player_node.player_inventory):
		player_node.player_inventory.monies_amount += gained * 40


## Levels a bot's character to `level` by pumping EXP, and raises its
## primary-discipline mastery to match (one mastery level per character level,
## capped) — character EXP only grants attribute points; ability points come
## from WEAPON MASTERY (mastery_level_changed -> ability-point grant), so
## without the mastery pump a leveled bot would have a full attribute build but
## no skills. One level's XP per call: grant_mastery_xp_server emits once per
## call, so a single lump would jump levels but grant only one ability point.
## Shared by /bot set_level and cold-start seeding. Returns a mastery summary.
func pump_bot_to_level(player_node: MultiplayerPlayerV2, level: int) -> String:
	while player_node.level_component.level < level:
		var before: int = player_node.level_component.level
		player_node.level_component.add_exp(player_node.level_component.get_exp_to_next_level())
		if player_node.level_component.level == before:
			break  # level cap — exp no longer levels; don't spin
	var mastery_msg := ""
	var wm = player_node.weapon_mastery_component
	if is_instance_valid(wm):
		var disc: int = wm.primary_discipline
		var target_mastery: int = mini(level, WeaponMasteryComponent.MASTERY_CAP)
		var start_mastery: int = wm.get_mastery_level(disc)
		while wm.get_mastery_level(disc) < target_mastery:
			wm.grant_mastery_xp_server(disc, wm.get_xp_to_next_level(disc))
		mastery_msg = " (mastery %d -> %d)" % [start_mastery, wm.get_mastery_level(disc)]
	return mastery_msg


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
		"class": node.weapon_mastery_component.primary_discipline if is_instance_valid(node.weapon_mastery_component) else 0,
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
		snap["companion"] = brain.companion_mode
		snap["metrics"] = brain.get_metrics().duplicate()
		snap["patrol_route"] = brain.patrol_route.duplicate()
		snap["patrol_index"] = brain.patrol_index

	# Identity + social layer (ADR 0011/0012) for the inspect window.
	snap["personality"] = String(active_bots.get(bot_id, {}).get("personality", ""))
	var archetype := get_bot_personality(bot_id)
	snap["chattiness"] = float(archetype.get("chattiness", 0.0))
	if not _roster_loaded:
		_load_roster()
	snap["rep"] = _roster.get(node.username, {}).get("rep", {}).duplicate()

	# Per-discipline weapon mastery levels.
	var masteries: Dictionary = {}
	if is_instance_valid(node.weapon_mastery_component):
		for disc in [Constants.ClassType.SWORD, Constants.ClassType.BOW,
				Constants.ClassType.STAFF, Constants.ClassType.DAGGER]:
			masteries[disc] = node.weapon_mastery_component.get_mastery_level(disc)
	snap["masteries"] = masteries

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


## The (max jump height, full jump reach) the bots on this server navigate with —
## the single source of truth for building a nav graph that matches their real
## reach. Reads any active bot's computed jump profile; falls back to the
## navigator's own defaults when no bot exists yet. ALL graph-build triggers must
## use this so the per-map cached graph is identical regardless of which caller
## (a bot, the debug overlay, the navgraph command) builds it first.
func _bot_jump_params() -> Vector2:
	for bid in active_bots:
		var b = get_bot_brain(bid)
		if b and is_instance_valid(b._navigator):
			return Vector2(b._navigator._max_jump_height, b._navigator._jump_reach)
	# Fallback when no bot exists yet — match the navigator's computed profile for
	# the real player tuning (jump_velocity -230, move_speed 100) so a graph built
	# before any bot spawns isn't seeded with too-generous jump limits.
	return Vector2(28.0, 47.0)


# --- /bot stress: cycle N bots through a portal to load-test the map-change path ---
var _stress_active: bool = false
var _stress_bot_ids: Array[int] = []
var _stress_map_a: String = ""
var _stress_map_b: String = ""
var _stress_idx: int = 0
var _stress_accum: float = 0.0
var _stress_interval: float = 0.15  # seconds between one bot's hop
## When true, the stress bots take the RECREATE path (free + re-instantiate +
## JoinHandshake) instead of the reparent fast path — read by
## MapManager.request_map_change. Lets the stress test measure the server-side
## rebuild cost a REMOTE CLIENT incurs per portal, which compounds at 50x.
var stress_force_recreate: bool = false


func _process(delta: float) -> void:
	# has_multiplayer_peer() first: post-disconnect the peer is null and
	# is_server() calls get_unique_id() internally, which errors with no peer.
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server():
		return
	_step_nav_graph_builds()
	_update_watch_camera()
	_step_churn(delta)
	_step_banter(delta)
	if _stress_active:
		_step_stress(delta)


## One bot hops to the opposite stress map per _stress_interval (round-robin), so
## the portal/map-change machinery gets a steady "one after another" stream.
func _step_stress(delta: float) -> void:
	if _stress_bot_ids.is_empty():
		_stress_active = false
		return
	_stress_accum += delta
	if _stress_accum < _stress_interval:
		return
	_stress_accum = 0.0
	var tries := 0
	while tries < _stress_bot_ids.size():
		var bot_id: int = _stress_bot_ids[_stress_idx % _stress_bot_ids.size()]
		_stress_idx += 1
		tries += 1
		if not is_instance_valid(PlayerManager.get_player_node(bot_id)):
			continue  # still spawning / despawned — try the next
		var cur: String = MapManager.get_player_map(bot_id)
		var dest: String = _stress_map_b if cur == _stress_map_a else _stress_map_a
		MapManager.request_map_change(bot_id, dest)
		return


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
## view. Host-only.
##
## Every map lives in its own SubViewport with an isolated World2D (ADR 0007),
## so the host's camera can never LOOK at a bot on another map — a camera only
## sees its own world. Watching therefore (a) locally composites the BOT's map
## (the same _set_local_map_visible switch a host map change uses; purely
## visual, the host keeps simulating on its own now-hidden map) and (b) drives
## a dedicated follow camera that lives inside the bot's SubViewport.
var _watched_bot: int = 0
var _watch_camera: Camera2D = null
## The map this watch session is currently compositing locally ("" = none).
var _watch_shown_map: String = ""
## The host map this watch session has hidden ("" = none) — re-hidden if the
## host itself changes maps mid-watch (its arrival re-shows its new map).
var _watch_hidden_host_map: String = ""

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
	if is_instance_valid(_watch_camera):
		_watch_camera.queue_free()
	_watch_camera = null
	# Put the host's own map back on screen and hand the view back to its camera.
	if not _watch_shown_map.is_empty() and _watch_shown_map != MapManager.current_map_id:
		MapManager._set_local_map_visible(_watch_shown_map, false)
	if not MapManager.current_map_id.is_empty():
		MapManager._set_local_map_visible(MapManager.current_map_id, true)
	_watch_shown_map = ""
	_watch_hidden_host_map = ""
	var host := PlayerManager.get_player_node(1)
	if is_instance_valid(host) and is_instance_valid(host.camera):
		host.camera.make_current()
		if host.has_method("_apply_map_camera_bounds"):
			host._apply_map_camera_bounds(host.camera)


func _update_watch_camera() -> void:
	if _watched_bot == 0:
		return
	if not active_bots.has(_watched_bot):
		watch_bot(0)  # bot despawned — stop following
		return
	var bot := PlayerManager.get_player_node(_watched_bot)
	if not is_instance_valid(bot):
		return
	var bot_map := MapManager.get_player_map(_watched_bot)
	if bot_map.is_empty():
		return

	# Composite the bot's map locally (and keep up when the bot hops maps).
	if _watch_shown_map != bot_map:
		if not _watch_shown_map.is_empty() and _watch_shown_map != MapManager.current_map_id:
			MapManager._set_local_map_visible(_watch_shown_map, false)
		if MapManager.current_map_id != bot_map:
			MapManager._set_local_map_visible(MapManager.current_map_id, false)
			_watch_hidden_host_map = MapManager.current_map_id
		MapManager._set_local_map_visible(bot_map, true)
		_watch_shown_map = bot_map

	# The host changing maps mid-watch re-shows ITS new map — re-hide it so the
	# watched map stays the one on screen.
	if MapManager.current_map_id != bot_map and MapManager.current_map_id != _watch_hidden_host_map:
		MapManager._set_local_map_visible(MapManager.current_map_id, false)
		_watch_hidden_host_map = MapManager.current_map_id

	# Follow camera inside the bot's own SubViewport/World2D. Recreated when
	# the bot crosses into a different viewport (reparent map hop).
	if not is_instance_valid(_watch_camera) or _watch_camera.get_viewport() != bot.get_viewport():
		if is_instance_valid(_watch_camera):
			_watch_camera.queue_free()
		_watch_camera = Camera2D.new()
		_watch_camera.name = "BotWatchCamera"
		var host := PlayerManager.get_player_node(1)
		if is_instance_valid(host) and is_instance_valid(host.camera):
			_watch_camera.zoom = host.camera.zoom
		bot.get_viewport().add_child(_watch_camera)
		# Land on the bot immediately — physics interpolation would otherwise
		# swoop the view in from (0,0) on the first frame.
		_watch_camera.global_position = bot.global_position
		_watch_camera.reset_physics_interpolation()
	if not _watch_camera.is_current():
		_watch_camera.make_current()
	_watch_camera.global_position = bot.global_position


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
			# Invincible training dummies are excluded so bots never target,
			# count, or path toward them — they're a player-only practice target.
			if node.health_component and node.health_component.invincible:
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
	# Accept both the legacy starting-discipline names (still used by bot_config.json
	# and any externally-typed /bot spawn commands) and the new weapon-keyed names.
	match class_str.to_upper():
		"SWORDSMAN", "SWORD": return Constants.ClassType.SWORD
		"ARCHER", "BOW": return Constants.ClassType.BOW
		"MAGE", "STAFF": return Constants.ClassType.STAFF
		"ROGUE", "DAGGER": return Constants.ClassType.DAGGER
		_: return Constants.ClassType.SWORD


## Dispatches a parsed /bot command. `requester_id` is the peer that issued the
## command (server peer id for a host call); it lets subcommands like `inspect`
## route UI back to the requesting client rather than always the host.
func handle_command(args: Array, requester_id: int = 0) -> String:
	if args.is_empty():
		return "Usage: /bot <spawn|despawn|despawn_all|list|roster|teleport|set_level|personality|say|emote|rep|party|follow|stay|free|churn|banter|travel|stress|inspect|trade|navgraph|navpath|debugdraw|stats|watch|reload_config>"

	var sub_command: String = args[0].to_lower()
	match sub_command:
		"spawn":
			if args.size() < 3:
				return "Usage: /bot spawn <name|random> <class> [map]"
			var bot_name: String = args[1]
			if bot_name.to_lower() == "random":
				bot_name = generate_bot_name()
			elif _is_name_taken(bot_name):
				return "Bot name '%s' is already active. Pick another, or use 'random'." % bot_name
			var class_type: int = _class_string_to_type(args[2])
			var map_id: String = args[3] if args.size() > 3 else ""
			var bot_id := spawn_bot(bot_name, class_type, map_id)
			if bot_id == 0:
				return "Failed to spawn bot '%s' (see server log)." % bot_name
			return "Spawned bot '%s' with ID %d" % [bot_name, bot_id]

		"despawn":
			if args.size() < 2:
				return "Usage: /bot despawn <name|id>"
			var target: String = args[1]
			var bot_id := _find_bot_by_name_or_id(target)
			if bot_id == 0:
				return "Bot '%s' not found." % target
			despawn_bot(bot_id)
			return "Despawned bot %d." % bot_id

		"despawn_all":
			var count := active_bots.size()
			despawn_all_bots()
			return "Despawned %d bot(s)." % count

		"list":
			if active_bots.is_empty():
				return "No active bots."
			var lines: PackedStringArray = []
			for bot_id in active_bots:
				var info = active_bots[bot_id]
				var player_node := PlayerManager.get_player_node(bot_id)
				var level_str := "?"
				if is_instance_valid(player_node) and is_instance_valid(player_node.level_component):
					level_str = str(player_node.level_component.level)
				lines.append("  [%d] %s (%s) Lv.%s on '%s'" % [
					bot_id, info.username,
					Constants.ClassType.find_key(info.class_type),
					level_str, info.map_id])
			return "Active bots:\n" + "\n".join(lines)

		"teleport":
			if args.size() < 3:
				return "Usage: /bot teleport <name|id> <map>"
			var target: String = args[1]
			var bot_id := _find_bot_by_name_or_id(target)
			if bot_id == 0:
				return "Bot '%s' not found." % target
			var map_id: String = args[2]
			active_bots[bot_id].map_id = map_id
			MapManager.request_map_change(bot_id, map_id)
			return "Teleported bot %d to map '%s'." % [bot_id, map_id]

		"set_level":
			if args.size() < 3:
				return "Usage: /bot set_level <name|id> <level>"
			var target: String = args[1]
			var bot_id := _find_bot_by_name_or_id(target)
			if bot_id == 0:
				return "Bot '%s' not found." % target
			var level = args[2].to_int()
			if level < 1:
				return "Level must be >= 1."
			var player_node := PlayerManager.get_player_node(bot_id)
			if not is_instance_valid(player_node) or not is_instance_valid(player_node.level_component):
				return "Bot %d player node not ready." % bot_id
			var current := player_node.level_component.level
			var mastery_msg := pump_bot_to_level(player_node, level)
			return "Bot %d leveled from %d to %d.%s" % [bot_id, current, player_node.level_component.level, mastery_msg]

		"party":
			return _handle_party_command(args.slice(1))

		"follow", "stay", "free":
			return _handle_companion_command(sub_command, args.slice(1), requester_id)

		"roster":
			return _handle_roster_command(args.slice(1))

		"personality":
			return _handle_personality_command(args.slice(1))

		"say":
			return _handle_say_command(args.slice(1))

		"emote":
			return _handle_emote_command(args.slice(1))

		"rep":
			return _handle_rep_command(args.slice(1))

		"churn":
			return _handle_churn_command(args.slice(1))

		"banter":
			return _banter_tick()

		"travel":
			return _handle_travel_command(args.slice(1))

		"stress":
			return _handle_stress_command(args.slice(1), requester_id)

		"inspect":
			return _handle_inspect_command(args.slice(1), requester_id)

		"trade":
			return _handle_trade_command(args.slice(1))

		"reload_config":
			load_config(_config_path)
			_load_personalities()
			return "Bot config reloaded (%d bot definitions, %d personality archetypes)." % [
				bot_config.get("bots", []).size(), _personalities.size()]

		"navgraph":
			return _handle_navgraph_command(args.slice(1))

		"navpath":
			return _handle_navpath_command(args.slice(1))

		"debugdraw":
			return _handle_debugdraw_command(args.slice(1))

		"stats":
			return _handle_stats_command(args.slice(1))

		"watch":
			return _handle_watch_command(args.slice(1))

		_:
			return "Unknown bot command '%s'. Use: spawn, despawn, despawn_all, list, roster, teleport, set_level, personality, say, emote, rep, party, follow, stay, free, churn, banter, travel, inspect, trade, navgraph, navpath, debugdraw, stats, watch, reload_config" % sub_command


## /bot roster [forget <name>] — the persistent identity book (ADR 0011/0012):
## every name the server has ever rolled, with class, personality, last_seen,
## reputation footprint, and whether it is online right now.
func _handle_roster_command(args: Array) -> String:
	if not _roster_loaded:
		_load_roster()
	if not args.is_empty() and args[0].to_lower() == "forget":
		if args.size() < 2:
			return "Usage: /bot roster forget <name>"
		var target: String = args[1]
		for roster_name in _roster:
			if String(roster_name).to_lower() == target.to_lower():
				_roster.erase(roster_name)
				_save_roster()
				return "Forgot roster identity '%s' (next spawn re-rolls)." % roster_name
		return "No roster entry for '%s'." % target
	if _roster.is_empty():
		return "Roster is empty — identities are written on first spawn."
	var lines: PackedStringArray = ["Roster (%d identities, saves/bot_roster.json):" % _roster.size()]
	var names: Array = _roster.keys()
	names.sort()
	for roster_name in names:
		var e: Dictionary = _roster[roster_name]
		var rep: Dictionary = e.get("rep", {})
		var best_friend := ""
		var best_score := 0
		for player_name in rep:
			if int(rep[player_name]) > best_score:
				best_score = int(rep[player_name])
				best_friend = player_name
		var rep_str := "knows %d player(s)%s" % [rep.size(),
			" — best: %s (%d)" % [best_friend, best_score] if not best_friend.is_empty() else ""] \
			if not rep.is_empty() else "knows nobody yet"
		lines.append("  %s %-14s %-9s %-9s seen %-8s %s" % [
			"●" if _is_name_taken(roster_name) else "○", roster_name,
			String(e.get("class", "?")), String(e.get("personality", "?")),
			_format_ago(int(e.get("last_seen", 0))), rep_str])
	lines.append("  (● online  ○ offline · 'forget <name>' re-rolls an identity)")
	return "\n".join(lines)


## /bot personality <name|id> [archetype] — view or live-swap a bot's voice.
func _handle_personality_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot personality <name|id> [%s]" % " | ".join(PackedStringArray(_personalities.keys()))
	var bot_id := _find_bot_by_name_or_id(args[0])
	if bot_id == 0:
		return "Bot '%s' not found." % args[0]
	var current: String = String(active_bots[bot_id].get("personality", "(unset)"))
	if args.size() == 1:
		var archetype := get_bot_personality(bot_id)
		return "%s: personality '%s' (chattiness %.2f). Archetypes: %s" % [
			active_bots[bot_id].username, current,
			float(archetype.get("chattiness", 0.0)),
			", ".join(PackedStringArray(_personalities.keys()))]
	var key: String = args[1].to_lower()
	if not set_bot_personality(bot_id, key):
		return "Unknown archetype '%s'. Use: %s" % [key, ", ".join(PackedStringArray(_personalities.keys()))]
	return "%s: personality '%s' -> '%s' (persisted; a config-authored personality still wins on respawn)." % [
		active_bots[bot_id].username, current, key]


## /bot say <name|id> <event|text...> — force speech. A known event key pulls
## a line from the bot's pools (the real pipeline, budget included); anything
## else is spoken verbatim. Either way it only lands if a real player shares
## the bot's map — same rule as organic speech.
func _handle_say_command(args: Array) -> String:
	if args.size() < 2:
		return "Usage: /bot say <name|id> <event|text...> (events: greet, level_up, death, rare_loot, boss_kill, ...)"
	var bot_id := _find_bot_by_name_or_id(args[0])
	if bot_id == 0:
		return "Bot '%s' not found." % args[0]
	var brain := get_bot_brain(bot_id)
	if brain == null:
		return "Bot %d has no active brain." % bot_id
	var rest: Array = args.slice(1)
	var archetype := get_bot_personality(bot_id)
	if rest.size() == 1 and archetype.get("lines", {}).has(rest[0]):
		brain.try_speak(rest[0], {}, true)
		return "Forced '%s' line from %s (delivers only if a player is on its map)." % [rest[0], active_bots[bot_id].username]
	var text: String = " ".join(PackedStringArray(rest))
	if ChatManager.bot_say(bot_id, text):
		return "%s says: %s" % [active_bots[bot_id].username, text]
	return "Not delivered (speech budget, or no real player on the bot's map)."


## /bot emote <name|id> <sit|wave|laugh|cry>
func _handle_emote_command(args: Array) -> String:
	if args.size() < 2:
		return "Usage: /bot emote <name|id> <sit|wave|laugh|cry>"
	var bot_id := _find_bot_by_name_or_id(args[0])
	if bot_id == 0:
		return "Bot '%s' not found." % args[0]
	var emote: String = args[1].to_lower()
	if not emote.begins_with("/"):
		emote = "/" + emote
	if not ChatManager.EMOTES.has(emote):
		return "Unknown emote '%s'. Use: sit, wave, laugh, cry." % args[1]
	if ChatManager.bot_emote(bot_id, emote):
		return "%s %s" % [active_bots[bot_id].username, ChatManager.EMOTES[emote]["text"]]
	return "Not delivered (emote gap, or no real player on the bot's map)."


## /bot rep <name|id> [player [delta]] — view or adjust familiarity scores.
func _handle_rep_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot rep <name|id> [player [delta]]"
	var bot_id := _find_bot_by_name_or_id(args[0])
	if bot_id == 0:
		return "Bot '%s' not found." % args[0]
	var bot_name: String = active_bots[bot_id].username
	if args.size() >= 3 and String(args[2]).is_valid_int():
		add_reputation(bot_id, args[1], String(args[2]).to_int())
		return "%s rep for '%s' -> %d." % [bot_name, args[1], get_reputation(bot_id, args[1])]
	if args.size() == 2:
		var score := get_reputation(bot_id, args[1])
		return "%s knows '%s' at %d (%s)." % [bot_name, args[1], score, _rep_tier_label(score)]
	if not _roster_loaded:
		_load_roster()
	var rep: Dictionary = _roster.get(bot_name, {}).get("rep", {})
	if rep.is_empty():
		return "%s knows nobody yet." % bot_name
	var lines: PackedStringArray = ["%s's reputation:" % bot_name]
	for player_name in rep:
		var score: int = int(rep[player_name])
		lines.append("  %-14s %3d  (%s)" % [player_name, score, _rep_tier_label(score)])
	return "\n".join(lines)


func _rep_tier_label(score: int) -> String:
	if score >= 10:
		return "friend"
	if score >= 3:
		return "familiar"
	return "stranger"


## /bot churn <status|on|off|now> — inspect or drive the login/logoff cycler.
func _handle_churn_command(args: Array) -> String:
	var cfg: Dictionary = bot_config.get("churn", {})
	var sub: String = args[0].to_lower() if not args.is_empty() else "status"
	match sub:
		"status":
			return "Churn %s — online %d (floor %d / cap %d), offline pool %d, next event in ~%ds." % [
				"ON" if cfg.get("enabled", false) else "OFF",
				active_bots.size(), int(cfg.get("min_online", 2)), int(cfg.get("max_online", 8)),
				_offline_identities().size(), int(maxf(_churn_timer, 0.0))]
		"on", "off":
			if not bot_config.has("churn"):
				bot_config["churn"] = {}
			bot_config["churn"]["enabled"] = (sub == "on")
			return "Churn %s (runtime only — reload_config restores the file's setting)." % sub.to_upper()
		"now":
			_churn_timer = randf_range(float(cfg.get("interval_min", 180.0)), float(cfg.get("interval_max", 420.0)))
			_churn_tick(cfg)
			return "Churn event forced."
	return "Usage: /bot churn <status|on|off|now>"


## /bot follow|stay|free <name|id|all> — player-issued companion commands
## (ADR 0011). Party-leader-only, so a bystander can't order someone else's
## groupmates around. "all" commands every bot in the requester's party. These
## set a mode flag on the brain — no trinity roles, no new RPC surface.
func _handle_companion_command(mode: String, args: Array, requester_id: int) -> String:
	if args.is_empty():
		return "Usage: /bot %s <name|id|all>" % mode
	if requester_id == 0 or is_bot(requester_id):
		return "Companion commands must come from a player."
	var requester_party := PartyManager.get_player_party_id(requester_id)
	if requester_party == -1:
		return "You must be in a party with the bot to command it."
	if PartyManager.get_party_leader(requester_party) != requester_id:
		return "Only the party leader can command bots."

	var targets: Array[int] = []
	if args[0].to_lower() == "all":
		for member_id in PartyManager.get_party_members(requester_id):
			if is_bot(member_id):
				targets.append(member_id)
		if targets.is_empty():
			return "No bots in your party."
	else:
		var single_id := _find_bot_by_name_or_id(args[0])
		if single_id == 0:
			return "Bot '%s' not found." % args[0]
		if PartyManager.get_player_party_id(single_id) != requester_party:
			return "Bot '%s' is not in your party." % active_bots[single_id].username
		targets.append(single_id)

	var applied: PackedStringArray = []
	for bot_id in targets:
		var brain := get_bot_brain(bot_id)
		if brain == null:
			continue
		brain.set_companion_mode("" if mode == "free" else mode)
		applied.append(active_bots[bot_id].username)
	if applied.is_empty():
		return "No bot brains available to command."
	match mode:
		"follow":
			return "%s now following you." % ", ".join(applied)
		"stay":
			return "%s holding position." % ", ".join(applied)
		_:
			return "%s released to roam." % ", ".join(applied)


## Reports a bot's lifetime behaviour metrics.
func _handle_stats_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot stats <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	var brain := get_bot_brain(bot_id_val)
	if brain == null:
		return "Bot %d has no active brain." % bot_id_val
	var m: Dictionary = brain.get_metrics()
	return "Bot %d — kills %d, deaths %d (enemy %d / hazard %d), stuck %d, travel-abandons %d, loot %d, sale-gold %d" % [
		bot_id_val, m.kills, m.deaths, m.deaths_to_enemy, m.deaths_to_hazard,
		m.stuck_recoveries, m.travel_abandons, m.loot_collected, m.gold_from_sales]


## Camera-follows a bot (host view). `/bot watch off` stops.
func _handle_watch_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot watch <name|id|off>"
	if args[0].to_lower() == "off":
		watch_bot(0)
		return "Stopped watching."
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	watch_bot(bot_id_val)
	return "Camera now following bot %d." % bot_id_val


## Toggles the host-side bot navigation debug overlay (see bot_debug_draw.gd).
func _handle_debugdraw_command(args: Array) -> String:
	var want: bool
	if args.is_empty():
		want = not _debug_draw_enabled
	else:
		match args[0].to_lower():
			"on", "true", "1":
				want = true
			"off", "false", "0":
				want = false
			_:
				return "Usage: /bot debugdraw [on|off]"

	_debug_draw_enabled = want
	if want:
		_ensure_debug_draw_node()
		# Kick off a graph build for the host's map so it's visible even with
		# no bots around to trigger one.
		var map_node := MapManager.get_player_map_node(1)
		var map_id: String = MapManager.get_player_map(1)
		if is_instance_valid(map_node) and not map_id.is_empty():
			# Build with the SAME jump profile the bots use, not hardcoded values:
			# the graph is cached by whichever caller builds it first, so a mismatch
			# here (e.g. a too-small jump_reach) would prune valid jump edges and
			# degrade the very graph the bots then navigate on.
			var jp := _bot_jump_params()
			get_nav_graph(map_id, map_node, jp.x, jp.y)
	elif is_instance_valid(_debug_draw):
		_debug_draw.enabled = false

	return "Bot navigation debug draw %s (host view)." % ("ON" if want else "OFF")


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


## Debug: builds the platform-navigation graph for a bot's current map and
## reports its size, plus a sample path from the bot to a portal. The graph is
## not yet wired into bot movement — this is for inspecting stage-1 output.
func _handle_navgraph_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot navgraph <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	var map_node := MapManager.get_player_map_node(bot_id_val)
	if not is_instance_valid(map_node):
		return "Bot %d has no live map node." % bot_id_val

	# Build the diagnostic graph with the SAME jump profile the live gameplay
	# graph uses, so the reported jump-edge count matches what bots navigate on.
	var jp := _bot_jump_params()
	var max_jump := jp.x
	var jump_reach := jp.y
	var brain := get_bot_brain(bot_id_val)
	if brain and is_instance_valid(brain._navigator):
		max_jump = brain._navigator._max_jump_height
		jump_reach = brain._navigator._jump_reach

	var graph := BotNavGraph.new()
	if not graph.build(map_node, max_jump, jump_reach):
		return "Failed to build nav graph for bot %d's map." % bot_id_val

	var s := graph.get_stats()
	var lines: PackedStringArray = []
	lines.append("Nav graph for bot %d (map '%s'):" % [bot_id_val, map_node.name])
	lines.append("  bounds: %s" % str(s.bounds))
	lines.append("  surfaces: %d   points: %d" % [s.segments, s.points])
	lines.append("  edges: %d (walk %d, jump %d, drop %d, gap %d)" % [
		s.edges, s.walk, s.jump, s.drop, s.gap])

	var player_node := PlayerManager.get_player_node(bot_id_val)
	var portal := _find_any_portal(map_node)
	if is_instance_valid(player_node) and is_instance_valid(portal):
		var path := graph.find_path(player_node.global_position, portal.global_position)
		lines.append("  sample path bot -> %s: %d waypoints" % [portal.name, path.size()])
	return "\n".join(lines)


## Debug: reports a bot's live graph-navigation state — current action, goal,
## and whether it's following a planned waypoint path or navigating directly.
func _handle_navpath_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot navpath <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	var brain := get_bot_brain(bot_id_val)
	if brain == null:
		return "Bot %d has no active brain." % bot_id_val

	var nav = brain._navigator
	var p = brain.player
	var lines: PackedStringArray = []
	lines.append("Bot %d nav state:" % bot_id_val)
	lines.append("  action: %s   pos: %s" % [brain.current_action, str(Vector2i(p.global_position)) if is_instance_valid(p) else "?"])
	if is_instance_valid(brain.target_enemy):
		lines.append("  target enemy at %s" % str(Vector2i(brain.target_enemy.global_position)))
	if is_instance_valid(brain.target_loot):
		lines.append("  target loot at %s" % str(Vector2i(brain.target_loot.global_position)))
	lines.append("  nav goal: %s" % str(Vector2i(nav._nav_goal)) if nav._nav_goal.is_finite() else "  nav goal: none")
	lines.append("  on_floor: %s  in_ladder: %s  climbing: %s" % [
		p.is_on_floor() if is_instance_valid(p) else "?", p.is_in_ladder_zone() if is_instance_valid(p) else "?", nav.is_climbing()])
	var path: PackedInt64Array = nav._nav_path
	if path.is_empty():
		lines.append("  waypoint path: none (direct navigation / no route)")
	else:
		lines.append("  waypoint path: %d points, at index %d" % [path.size(), nav._nav_index])
		# Show the current hop's edge kind + target so we can see what it's trying.
		var graph := nav._get_nav_graph()
		if graph != null and nav._nav_index >= 1 and nav._nav_index < path.size():
			var prev: int = path[nav._nav_index - 1]
			var cur: int = path[nav._nav_index]
			if graph.has_point(prev) and graph.has_point(cur):
				var kinds := ["WALK", "JUMP", "DROP", "GAP", "CLIMB"]
				var k: int = graph.edge_kind(prev, cur)
				lines.append("  current hop: %s -> %s  edge=%s" % [
					str(Vector2i(graph.point_position(prev))), str(Vector2i(graph.point_position(cur))),
					kinds[k] if k >= 0 and k < kinds.size() else "?(%d)" % k])
	return "\n".join(lines)


## First node carrying a `target_map_id` (a portal) found under `node`.
func _find_any_portal(node: Node) -> Node:
	if "target_map_id" in node:
		return node
	for child in node.get_children():
		var found := _find_any_portal(child)
		if found:
			return found
	return null


func _handle_inspect_command(args: Array, requester_id: int = 0) -> String:
	if args.is_empty():
		return "Usage: /bot inspect <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]

	var player_node := PlayerManager.get_player_node(bot_id_val)
	if not is_instance_valid(player_node):
		return "Bot %d player node not ready." % bot_id_val

	# The inspect window pulls its data over RPC, so it can live on any peer —
	# open it on the requesting client when the command did not come from the host.
	if requester_id == 0 or requester_id == multiplayer.get_unique_id():
		open_inspect_window(bot_id_val)
	else:
		open_bot_inspect_window.rpc_id(requester_id, bot_id_val)
	return "Inspecting bot '%s'." % active_bots[bot_id_val].username


## [Server -> Client] Tells the requesting client to open its own bot inspect window.
@rpc("authority", "call_remote", "reliable")
func open_bot_inspect_window(bot_id: int) -> void:
	open_inspect_window(bot_id)


func open_inspect_window(bot_id: int) -> void:
	if not is_instance_valid(_inspect_window):
		_inspect_window = BotInspectWindow.create()
		# Mount in the host's persistent LocalPlayerUI MoveableWindows (ADR 0009
		# Stage B) — falls back to /root if the UI layer isn't up yet.
		var moveable_container = MapManager.get_local_ui_moveable_windows()
		if is_instance_valid(moveable_container):
			moveable_container.add_child(_inspect_window)
		else:
			get_tree().root.add_child(_inspect_window)
	_inspect_window.show_bot(bot_id)


func _handle_trade_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot trade <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]

	# The trade is initiated server-side for the requesting player
	# We need to know who's requesting — this comes via ChatManager RPC
	# For now, return instructions since the actual trade needs to be initiated
	# through the TradeManager RPC from the client
	return "To trade with bot '%s', use: /trade %s" % [active_bots[bot_id_val].username, active_bots[bot_id_val].username]


## /bot stress <count> [interval] | /bot stress off
## Spawns <count> bots on the requester's current map and cycles them, one per
## `interval` seconds (round-robin), through the portal to an adjacent map and
## back — a continuous "one after another through a portal" load test of the
## server-side map-change path (reparent, visibility recompute, spawn/despawn
## broadcasts, enemy activation). NOTE: bots take the REPARENT path (like the
## host), not the remote-client recreate path — see /bot stress notes.
func _handle_stress_command(args: Array, requester_id: int) -> String:
	if not multiplayer.is_server():
		return "host-only."
	if not args.is_empty() and args[0].to_lower() == "off":
		_stress_active = false
		stress_force_recreate = false
		var n := _stress_bot_ids.size()
		return "Stress stopped. %d bots still active — '/bot despawn_all' to clear." % n
	# Parse: numeric tokens are count then interval; "recreate" forces the
	# server-side rebuild path (a remote client's per-portal cost) instead of
	# reparent, so you can A/B the two at scale.
	stress_force_recreate = false
	var nums: Array = []
	for a in args:
		if a.to_lower() == "recreate":
			stress_force_recreate = true
		elif a.is_valid_float():
			nums.append(float(a))
	var count: int = int(nums[0]) if nums.size() > 0 else 50
	count = clampi(count, 1, 200)
	if nums.size() > 1:
		_stress_interval = clampf(nums[1], 0.02, 5.0)
	# Cycle between the requester's current map and a portal-adjacent map.
	var map_a: String = MapManager.get_player_map(requester_id)
	if map_a.is_empty():
		map_a = MapManager.DEFAULT_MAP
	var neighbors: Array = MapManager.get_map_connections(map_a)
	if neighbors.is_empty():
		return "Map '%s' has no portal-adjacent map to cycle through." % map_a
	_stress_map_a = map_a
	_stress_map_b = neighbors[0]
	var classes := [Constants.ClassType.SWORD, Constants.ClassType.BOW,
			Constants.ClassType.STAFF, Constants.ClassType.DAGGER]
	_stress_bot_ids.clear()
	for i in count:
		var cls: int = classes[randi() % classes.size()]
		var id: int = spawn_bot(generate_bot_name(), cls, map_a)
		if id != 0:
			_stress_bot_ids.append(id)
	_stress_idx = 0
	_stress_accum = 0.0
	_stress_active = true
	var mode := "RECREATE (server rebuild — remote-client cost)" if stress_force_recreate else "reparent (host/bot fast path)"
	return "Stress: %d bots, %s <-> %s every %.2fs, path=%s. '/bot stress off' to stop, '/bot despawn_all' to clear." % [
		_stress_bot_ids.size(), _stress_map_a, _stress_map_b, _stress_interval, mode]


func _handle_travel_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot travel <info> <name|id>"

	match args[0].to_lower():
		"info":
			if args.size() < 2:
				return "Usage: /bot travel info <name|id>"
			var bot_id_val := _find_bot_by_name_or_id(args[1])
			if bot_id_val == 0:
				return "Bot '%s' not found." % args[1]
			var info = active_bots[bot_id_val]
			var current_map := MapManager.get_player_map(bot_id_val)
			var difficulty := get_map_difficulty(current_map)
			var bot_def := get_bot_definition(bot_id_val)
			var patrol: Array = bot_def.get("patrol_route", [])
			var player_node := PlayerManager.get_player_node(bot_id_val)
			var level_str := "?"
			if is_instance_valid(player_node) and is_instance_valid(player_node.level_component):
				level_str = str(player_node.level_component.level)
			var diff_str := "none"
			if not difficulty.is_empty():
				diff_str = "Lv.%d-%d" % [difficulty.get("min_level", 0), difficulty.get("max_level", 0)]
			var patrol_str := str(patrol) if not patrol.is_empty() else "none"
			return "Bot %d (%s): map='%s' (%s), level=%s, patrol=%s" % [bot_id_val, info.username, current_map, diff_str, level_str, patrol_str]
		_:
			return "Unknown travel command. Use: info"


func _handle_party_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot party <list|info|kick>"

	match args[0].to_lower():
		"list":
			var lines: PackedStringArray = []
			for bot_id in active_bots:
				var info = active_bots[bot_id]
				var party_id := PartyManager.get_player_party_id(bot_id)
				if party_id == -1:
					lines.append("  [%d] %s — no party" % [bot_id, info.username])
				else:
					var leader_id := PartyManager.get_party_leader(party_id)
					var members := PartyManager.get_party_members(bot_id)
					var role := "leader" if leader_id == bot_id else "member"
					lines.append("  [%d] %s — party %d (%s, %d members)" % [bot_id, info.username, party_id, role, members.size()])
			if lines.is_empty():
				return "No active bots."
			return "Bot party status:\n" + "\n".join(lines)

		"info":
			if args.size() < 2:
				return "Usage: /bot party info <name|id>"
			var bot_id := _find_bot_by_name_or_id(args[1])
			if bot_id == 0:
				return "Bot '%s' not found." % args[1]
			var party_id := PartyManager.get_player_party_id(bot_id)
			if party_id == -1:
				return "Bot %d is not in a party." % bot_id
			var members := PartyManager.get_party_members(bot_id)
			var leader_id := PartyManager.get_party_leader(party_id)
			var member_names: PackedStringArray = []
			for mid in members:
				var name_str: String
				if mid in active_bots:
					name_str = active_bots[mid].username
				else:
					var pinfo = PlayerManager.get_player_info(mid)
					name_str = pinfo.get("username", str(mid))
				if mid == leader_id:
					name_str += " (leader)"
				member_names.append(name_str)
			return "Bot %d party %d: %s" % [bot_id, party_id, ", ".join(member_names)]

		"kick":
			if args.size() < 2:
				return "Usage: /bot party kick <name|id>"
			var bot_id := _find_bot_by_name_or_id(args[1])
			if bot_id == 0:
				return "Bot '%s' not found." % args[1]
			if PartyManager.get_player_party_id(bot_id) == -1:
				return "Bot %d is not in a party." % bot_id
			PartyManager.leave_party(bot_id)
			return "Bot %d removed from party." % bot_id

		_:
			return "Unknown party command. Use: list, info, kick"


func _find_bot_by_name_or_id(target: String) -> int:
	if target.is_valid_int():
		var id := target.to_int()
		if id in active_bots:
			return id
	for bot_id in active_bots:
		if active_bots[bot_id].username.to_lower() == target.to_lower():
			return bot_id
	return 0
