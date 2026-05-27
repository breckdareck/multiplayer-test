extends RefCounted
## Parses and dispatches `/bot` chat commands. Owned by BotManager — every
## sub-command handler lives here so the autoload stays focused on bot
## lifecycle, nav-graph caching, and debug-overlay state. Server-side only;
## the only entry point is handle_command(), which BotManager forwards to.

const BotBrain = preload("res://scripts/Bot/bot_brain.gd")
const BotNavGraph = preload("res://scripts/Bot/bot_nav_graph.gd")

## The owning BotManager autoload. Handlers reach back into bot state
## (active_bots, _is_name_taken, _ensure_debug_draw_node, ...) through this
## reference — keep the coupling explicit.
var bot_manager


func _init(owner_bot_manager) -> void:
	bot_manager = owner_bot_manager


## Dispatches a parsed /bot command. `requester_id` is the peer that issued the
## command (server peer id for a host call); it lets subcommands like `inspect`
## route UI back to the requesting client rather than always the host.
func handle_command(args: Array, requester_id: int = 0) -> String:
	if args.is_empty():
		return "Usage: /bot <spawn|despawn|despawn_all|list|teleport|set_level|party|travel|inspect|trade|navgraph|navpath|debugdraw|stats|watch|reload_config>"

	var sub_command: String = args[0].to_lower()
	match sub_command:
		"spawn":
			if args.size() < 3:
				return "Usage: /bot spawn <name|random> <class> [map]"
			var bot_name: String = args[1]
			if bot_name.to_lower() == "random":
				bot_name = bot_manager.generate_bot_name()
			elif bot_manager._is_name_taken(bot_name):
				return "Bot name '%s' is already active. Pick another, or use 'random'." % bot_name
			var class_type: int = bot_manager._class_string_to_type(args[2])
			var map_id: String = args[3] if args.size() > 3 else ""
			var bot_id: int = bot_manager.spawn_bot(bot_name, class_type, map_id)
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
			bot_manager.despawn_bot(bot_id)
			return "Despawned bot %d." % bot_id

		"despawn_all":
			var count: int = bot_manager.active_bots.size()
			bot_manager.despawn_all_bots()
			return "Despawned %d bot(s)." % count

		"list":
			if bot_manager.active_bots.is_empty():
				return "No active bots."
			var lines: PackedStringArray = []
			for bot_id in bot_manager.active_bots:
				var info = bot_manager.active_bots[bot_id]
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
			bot_manager.active_bots[bot_id].map_id = map_id
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
			return _handle_inspect_command(args.slice(1), requester_id)

		"trade":
			return _handle_trade_command(args.slice(1))

		"reload_config":
			bot_manager.load_config(bot_manager._config_path)
			return "Bot config reloaded (%d bot definitions)." % bot_manager.bot_config.get("bots", []).size()

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
			return "Unknown bot command '%s'. Use: spawn, despawn, despawn_all, list, teleport, set_level, party, travel, inspect, trade, navgraph, navpath, debugdraw, stats, watch, reload_config" % sub_command


## Reports a bot's lifetime behaviour metrics.
func _handle_stats_command(args: Array) -> String:
	if args.is_empty():
		return "Usage: /bot stats <name|id>"
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	var brain: BotBrain = bot_manager.get_bot_brain(bot_id_val)
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
		bot_manager.watch_bot(0)
		return "Stopped watching."
	var bot_id_val := _find_bot_by_name_or_id(args[0])
	if bot_id_val == 0:
		return "Bot '%s' not found." % args[0]
	bot_manager.watch_bot(bot_id_val)
	return "Camera now following bot %d." % bot_id_val


## Toggles the host-side bot navigation debug overlay (see bot_debug_draw.gd).
func _handle_debugdraw_command(args: Array) -> String:
	var want: bool
	if args.is_empty():
		want = not bot_manager._debug_draw_enabled
	else:
		match args[0].to_lower():
			"on", "true", "1":
				want = true
			"off", "false", "0":
				want = false
			_:
				return "Usage: /bot debugdraw [on|off]"

	bot_manager._debug_draw_enabled = want
	if want:
		bot_manager._ensure_debug_draw_node()
		# Kick off a graph build for the host's map so it's visible even with
		# no bots around to trigger one.
		var map_node := MapManager.get_player_map_node(1)
		var map_id: String = MapManager.get_player_map(1)
		if is_instance_valid(map_node) and not map_id.is_empty():
			bot_manager.get_nav_graph(map_id, map_node, 45.0, 40.0)
	elif is_instance_valid(bot_manager._debug_draw):
		bot_manager._debug_draw.enabled = false

	return "Bot navigation debug draw %s (host view)." % ("ON" if want else "OFF")


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

	var max_jump := 45.0
	var jump_reach := 40.0
	var brain: BotBrain = bot_manager.get_bot_brain(bot_id_val)
	if brain:
		max_jump = brain._navigator._max_jump_height
		jump_reach = brain._navigator._jump_launch_offset

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
	var brain: BotBrain = bot_manager.get_bot_brain(bot_id_val)
	if brain == null:
		return "Bot %d has no active brain." % bot_id_val

	var lines: PackedStringArray = []
	lines.append("Bot %d nav state:" % bot_id_val)
	lines.append("  action: %s" % brain.current_action)
	lines.append("  nav goal: %s" % str(brain._navigator._nav_goal))
	var path: PackedInt64Array = brain._navigator._nav_path
	if path.is_empty():
		lines.append("  waypoint path: none (direct navigation / no route)")
	else:
		lines.append("  waypoint path: %d points, currently at index %d" % [
			path.size(), brain._navigator._nav_index])
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
	if requester_id == 0 or requester_id == bot_manager.multiplayer.get_unique_id():
		bot_manager.open_inspect_window(bot_id_val)
	else:
		bot_manager.open_bot_inspect_window.rpc_id(requester_id, bot_id_val)
	return "Inspecting bot '%s'." % bot_manager.active_bots[bot_id_val].username


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
	return "To trade with bot '%s', use: /trade %s" % [bot_manager.active_bots[bot_id_val].username, bot_manager.active_bots[bot_id_val].username]


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
			var info = bot_manager.active_bots[bot_id_val]
			var current_map := MapManager.get_player_map(bot_id_val)
			var difficulty: Dictionary = bot_manager.get_map_difficulty(current_map)
			var bot_def: Dictionary = bot_manager.get_bot_definition(bot_id_val)
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
			for bot_id in bot_manager.active_bots:
				var info = bot_manager.active_bots[bot_id]
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
				if mid in bot_manager.active_bots:
					name_str = bot_manager.active_bots[mid].username
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
		if id in bot_manager.active_bots:
			return id
	for bot_id in bot_manager.active_bots:
		if bot_manager.active_bots[bot_id].username.to_lower() == target.to_lower():
			return bot_id
	return 0
