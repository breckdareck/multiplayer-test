extends Node

const BotBrain = preload("res://scripts/Bot/bot_brain.gd")

var bot_counter: int = 0
var active_bots: Dictionary = {}
var bot_config: Dictionary = {}
var _config_path: String = "res://config/bot_config.json"
var _used_names: Dictionary = {}
var _bot_def_map: Dictionary = {}  # { bot_id: bot_def Dictionary from config }
var _inspect_window: BotInspectWindow = null

const NAME_PREFIXES: Array[String] = [
	"Shadow", "Iron", "Storm", "Frost", "Fire", "Dark", "Silver", "Golden",
	"Brave", "Swift", "Wild", "Stone", "Moon", "Star", "Thunder", "Ice",
	"Crimson", "Azure", "Jade", "Ember", "Night", "Dawn", "Dusk", "Ash",
]
const NAME_SUFFIXES: Array[String] = [
	"blade", "heart", "wind", "fang", "strike", "wolf", "hawk", "shield",
	"born", "walker", "fury", "soul", "flame", "guard", "fall", "forge",
	"bane", "claw", "storm", "song", "breaker", "thorn", "ridge", "vale",
]


func _ready() -> void:
	if not multiplayer.is_server():
		return
	# Defer bot spawning until the server and maps are ready.
	MultiplayerManager.server_has_started.connect(_on_server_started)


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

	var old_brain = player_node.get_node_or_null("BotBrain")
	if old_brain:
		old_brain.queue_free()

	var brain := BotBrain.new()
	brain.name = "BotBrain"
	player_node.add_child(brain)

	var behavior_cfg: Dictionary = bot_config.get("behavior", {}).duplicate()
	var bot_def := get_bot_definition(bot_id)
	if bot_def.has("patrol_route"):
		behavior_cfg["patrol_route"] = bot_def["patrol_route"]
	brain.init(player_node, bot_id, behavior_cfg)

	if bot_id in active_bots:
		active_bots[bot_id]["brain"] = brain
		var current_map := MapManager.get_player_map(bot_id)
		if not current_map.is_empty():
			active_bots[bot_id]["map_id"] = current_map

	#print("BotManager: Bot %d brain attached and running." % bot_id)


func _form_squad_on_map(map_id: String, bot_ids: Array) -> void:
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


func get_map_difficulty(map_id: String) -> Dictionary:
	return bot_config.get("map_difficulty", {}).get(map_id, {})


func generate_bot_name() -> String:
	for _attempt in 30:
		var name = NAME_PREFIXES.pick_random() + NAME_SUFFIXES.pick_random()
		if not _used_names.has(name):
			_used_names[name] = true
			return name
	var fallback := "Bot_%d" % abs(bot_counter)
	_used_names[fallback] = true
	return fallback


func _class_string_to_type(class_str: String) -> int:
	match class_str.to_upper():
		"SWORDSMAN": return Constants.ClassType.SWORDSMAN
		"ARCHER": return Constants.ClassType.ARCHER
		"MAGE": return Constants.ClassType.MAGE
		"ROGUE": return Constants.ClassType.ROGUE
		_: return Constants.ClassType.SWORDSMAN


func handle_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot <spawn|despawn|despawn_all|list|teleport|set_level|party|travel|reload_config>"

	var sub_command: String = args[0].to_lower()
	match sub_command:
		"spawn":
			if args.size() < 3:
				return "Usage: /bot spawn <name|random> <class> [map]"
			var bot_name: String = args[1]
			if bot_name.to_lower() == "random":
				bot_name = generate_bot_name()
			var class_type: int = _class_string_to_type(args[2])
			var map_id: String = args[3] if args.size() > 3 else ""
			var bot_id := spawn_bot(bot_name, class_type, map_id)
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
			while player_node.level_component.level < level:
				player_node.level_component.add_exp(player_node.level_component.get_exp_to_next_level())
			return "Bot %d leveled from %d to %d." % [bot_id, current, player_node.level_component.level]

		"party":
			return _handle_party_command(args.slice(1))

		"travel":
			return _handle_travel_command(args.slice(1))

		"inspect":
			return _handle_inspect_command(args.slice(1))

		"trade":
			return _handle_trade_command(args.slice(1))

		"reload_config":
			load_config(_config_path)
			return "Bot config reloaded (%d bot definitions)." % bot_config.get("bots", []).size()

		_:
			return "Unknown bot command '%s'. Use: spawn, despawn, despawn_all, list, teleport, set_level, party, travel, inspect, trade, reload_config" % sub_command


func _handle_inspect_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot inspect <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]

	var player_node := PlayerManager.get_player_node(bot_id_val)
	if not is_instance_valid(player_node):
		return "Bot %d player node not ready." % bot_id_val

	open_inspect_window(bot_id_val)
	return "Inspecting bot '%s'." % active_bots[bot_id_val].username


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
