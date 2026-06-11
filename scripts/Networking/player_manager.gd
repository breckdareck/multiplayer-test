# player_manager.gd - UPDATED with Map Support
extends Node

var character_scene = preload("res://scenes/Player/player.tscn")
var active_players: Dictionary = {}
# Cache of player_id -> player Node to avoid scanning all maps on every lookup.
# Populated on spawn, validated on read, erased on despawn/cleanup.
var _node_cache: Dictionary = {}
# State carried in-memory across a map change (player_id -> save-data dict),
# set by MapManager.request_map_change so the respawn skips a backend reload.
var _carried_state: Dictionary = {}
# Guards the double-spawn on map change: set when _on_player_spawned consumes
# carried state, checked so a redundant second spawn (host's client ACK)
# doesn't stale-reload over the freshly-carried node. See _on_player_spawned.
var _loaded_from_carry: Dictionary = {}
var _load_http_request: HTTPRequest
var _load_in_progress: bool = false
# Computed property so a runtime change via UserConfig.set_backend_api_url(...)
# takes effect immediately on the next request. Previously this was cached at
# _ready, so switching the URL in-game (e.g. dev pointing at a port-shifted
# backend) had no effect until the next process restart.
var _api_url: String:
	get: return UserConfig.get_backend_api_url() + "/player"


func _ready() -> void:
	
	# Connect to MapManager's player_spawned so we can finish initialization
	# after the server-side spawn is completed.
	if MapManager:
		MapManager.player_spawned.connect(_on_player_spawned)

	# Persistent HTTPRequest for load operations (reused across calls)
	_load_http_request = HTTPRequest.new()
	_load_http_request.name = "LoadHTTPRequest"
	add_child(_load_http_request)
	_load_http_request.timeout = 5.0


func has_player(id: int) -> bool:
	return id in active_players


func add_host_player():
	"""Add the host player (ID 1) in listen server mode"""
	call_deferred("add_player", 1)


func add_bot(bot_id: int, username: String, class_type: int, map_id: String) -> void:
	if not multiplayer.is_server():
		return
	active_players[bot_id] = {
		"id": bot_id,
		"character_type": class_type,
		"spawn_time": Time.get_unix_time_from_system(),
		"synced": false,
		"party_id": -1,
		"last_map": map_id,
		"username": username,
		"is_bot": true,
	}

	var player_data: Dictionary = await _load_player_data_async(username)
	# No save row -> a brand-new bot. Flag it so BotManager seeds its level/gold
	# after the spawn handshake (ADR 0011 cold-start seeding).
	if player_data.is_empty():
		BotManager.mark_bot_fresh(bot_id)
	var spawn_map: String = player_data.get("last_map", map_id)
	if spawn_map.is_empty():
		spawn_map = map_id
	active_players[bot_id]["last_map"] = spawn_map

	MapManager.request_map_change(bot_id, spawn_map)


func add_player(id: int):
	if multiplayer.is_server() and id != 1:
		var current_count = active_players.size()
		if current_count >= ServerManager.max_players:
			#print("PlayerManager: Server full (%d/%d), rejecting player %d" % [current_count, ServerManager.max_players, id])
			MultiplayerManager._notify_client_kicked.rpc_id(id, "Server is full (%d/%d)." % [current_count, ServerManager.max_players])
			get_tree().create_timer(0.5).timeout.connect(func(): multiplayer.multiplayer_peer.disconnect_peer(id))
			return
	#print("Player %d joined - preparing to spawn character" % id)
	NetworkUtils.log_network_event("PLAYER_JOIN", "Peer %d connected (%d/%d players)" % [id, active_players.size() + 1, ServerManager.max_players])

	active_players[id] = {
		"id": id,
		"character_type": - 1,
		"spawn_time": Time.get_unix_time_from_system(),
		"synced": false,
		"party_id": - 1,
		"last_map": "" # Track last map for respawn
	}
	
	# Request character selection from client
	rpc_id(id, "_client_send_initial_info", id)


func remove_player(id: int):
	if id not in active_players:
		#print("PlayerManager: Peer %d disconnected (was not an active player)" % id)
		NetworkUtils.log_network_event("PLAYER_LEAVE", "Peer %d disconnected (no active character)" % id)
		return
	var _leaving_username: String = active_players[id].get("username", "")
	var _leaving_class_id: int = active_players[id].get("character_type", -1)
	var _leaving_class: String = Constants.ClassType.find_key(_leaving_class_id) if _leaving_class_id >= 0 else "unknown"
	var _leaving_label: String = _leaving_username if not _leaving_username.is_empty() else "<unidentified>"
	#print("Player %d left - removing character" % id)
	NetworkUtils.log_network_event("PLAYER_LEAVE", "Character '%s' (%s, peer %d) disconnecting (%d players remaining)" % [_leaving_label, _leaving_class, id, max(0, active_players.size() - 1)])
	
	# Full save before disconnect — delegate to SaveManager for consistency
	if multiplayer.is_server() and id in active_players:
		var current_map = MapManager.get_player_map(id)
		if current_map:
			active_players[id]["last_map"] = current_map

		var username = active_players[id].get("username", "")
		var player_node = get_player_node(id)
		if is_instance_valid(player_node) and not username.is_empty():
			# Ensure SaveManager has this player registered with full data
			SaveManager.register_player(username, player_node)
			# Mark all categories dirty so flush captures everything
			SaveManager.queue_save(username, "all", player_node)
			# Flush immediately — blocks until save completes or falls back to file
			await SaveManager.flush_save(username)
			SaveManager.unregister_player(username)
			#print("PlayerManager: Saved player '%s' via SaveManager on disconnect." % username)
		elif not username.is_empty():
			# Player node already gone — fall back to quick save with what we have
			#print("PlayerManager: WARNING - Player %d node not found for full save, using quick save" % id)
			var quick_data = _get_quick_save_data(id)
			if not quick_data.is_empty():
				_save_player_data_to_file(quick_data)

	# Notify map manager to clean up
	MapManager.handle_player_disconnect(id)
	
	# Notify PartyManager
	if PartyManager:
		PartyManager._on_player_disconnected(id)

	# Tear down any trade the disconnecting player was involved in
	if TradeManager:
		TradeManager.handle_player_disconnect(id)
	
	# Remove from active players
	if id in active_players:
		active_players.erase(id)
	_node_cache.erase(id)
	_carried_state.erase(id)
	_loaded_from_carry.erase(id)


func save_all_players() -> void:
	"""Flush saves for all active players. Call BEFORE closing the multiplayer peer."""
	if not multiplayer.is_server():
		return
	for player_id in active_players.keys():
		var uname: String = active_players[player_id].get("username", "")
		var player_node = get_player_node(player_id)
		if is_instance_valid(player_node) and not uname.is_empty():
			SaveManager.register_player(uname, player_node)
			SaveManager.queue_save(uname, "all", player_node)
			await SaveManager.flush_save(uname)
			#print("PlayerManager: Flushed save for player '%s' during shutdown." % uname)


## Returns the starter weapon NAME (matches ResourceManager.get_item_by_name)
## for a given weapon discipline. Bow/Dagger had no entry-tier "Wooden" item
## in resources/Items/Weapons, so they fall back to the cheapest existing item
## (Worn Warbow / Bronze Dagger) until proper Wooden_Bow / Wooden_Dagger items
## are authored. Beginner and the 4 tier-2 advancement classes inherit from
## their tier-1 parent so they spawn with the right discipline weapon.
static func _starter_weapon_for(class_type: int) -> String:
	match class_type:
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE:
			return "Wooden Staff"
		Constants.ClassType.BOW, Constants.ClassType.RANGER:
			return "Worn Warbow"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN:
			return "Bronze Dagger"
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER, Constants.ClassType.BEGINNER, _:
			return "Wooden Sword"


## Returns the generated-armour FAMILY name for a discipline, used to pick the
## level-1 "Worn <family> <slot>" starter set. Mirrors _starter_weapon_for.
static func _starter_armor_family(class_type: int) -> String:
	match class_type:
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE:
			return "Arcanist"
		Constants.ClassType.BOW, Constants.ClassType.RANGER:
			return "Pathfinder"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN:
			return "Nightshade"
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER, Constants.ClassType.BEGINNER, _:
			return "Vanguard"


func cleanup():
	"""Remove all networked entities and reset player tracking"""
	#print("Cleaning up all players and entities")
	active_players.clear()
	_node_cache.clear()


# This function is called on the client to gather character selection info
# and send it to the server.
@rpc("call_local", "any_peer") # This RPC is called by the server on the client
func _client_send_initial_info(id: int):
	#print("PlayerManager: Client %d preparing to send initial info." % id)
	
	# Try to get character data from NetworkManager metadata first (new flow)
	var username: String = NetworkManager.get_meta("selected_character_name", "")
	var selected_char: int = NetworkManager.get_meta("selected_character_class", 0)
	
	# Fall back to menu_container if metadata not found (backward compatibility)
	if username.is_empty():
		var menu_container = get_tree().get_current_scene().get_node_or_null("%MenuContainer")
		if menu_container:
			if "selected_character" in menu_container:
				selected_char = menu_container.selected_character
			if menu_container.has_method("get_username"):
				username = menu_container.get_username()
	
	# Final fallback to default if still empty
	if username.is_empty():
		username = "Player" + str(id)
	
	#print("PlayerManager: Client sending character: %s & username: %s from PID: %d" % [Constants.ClassType.find_key(selected_char), username, id])
	# Send the gathered info to the server (ID 1)
	rpc_id(1, "_receive_initial_info", id, selected_char, username)


@rpc("call_local", "any_peer")
func _receive_initial_info(id: int, character_type: int, username: String):
	"""Called on server with all info needed to spawn a player."""
	if not multiplayer.is_server():
		return
	
	#print("PlayerManager: Server received character: %s & username: %s from PID: %d" % [Constants.ClassType.find_key(character_type), username, id])
	NetworkUtils.log_network_event("PLAYER_IDENTIFIED", "Peer %d -> character '%s' (%s)" % [id, username, Constants.ClassType.find_key(character_type)])

	if id in active_players:
		active_players[id]["character_type"] = character_type
		active_players[id]["username"] = username
	
	# Load player data (includes last map)
	var player_data: Dictionary = await _load_player_data_async(username)

	
	# Determine spawn map
	var spawn_map = player_data.get("last_map", MapManager.DEFAULT_MAP)
	if spawn_map.is_empty():
		spawn_map = MapManager.DEFAULT_MAP
	
	active_players[id]["last_map"] = spawn_map
	
	# Request map spawn through MapManager
	# For the host (player 1) we await so initialization continues immediately.
	if id == 1 and multiplayer.is_server():
		await MapManager.request_map_change(id, spawn_map)
		# Now initialize the player character that was spawned
		await _initialize_spawned_player(id, character_type, username, player_data)
		return

	# For remote players we store the loaded player data and request the map.
	# Initialization will continue when MapManager emits `player_spawned`.
	active_players[id]["character_type"] = character_type
	active_players[id]["username"] = username
	MapManager.request_map_change(id, spawn_map)
	return


func _initialize_spawned_player(id: int, character_type: int, username: String, player_data: Dictionary):
	"""Initialize a player that has been spawned by MapManager"""
	
	var player_instance = null
	var max_wait_frames = 30 # Wait up to 30 frames (half a second at 60fps)
	var current_wait_frames = 0

	while not is_instance_valid(player_instance) and current_wait_frames < max_wait_frames:
		player_instance = get_player_node(id)
		if not is_instance_valid(player_instance):
			await get_tree().process_frame
			current_wait_frames += 1
	
	if not is_instance_valid(player_instance):
		push_error("PlayerManager: Timed out finding spawned player %d to initialize after %d frames!" % [id, max_wait_frames])
		return
	
	#print("PlayerManager: Found player %d instance, starting initialization" % id)

	player_instance.player_id = id
	player_instance.name = str(id)
	# Refresh the node cache — covers both initial spawn and map changes.
	_node_cache[id] = player_instance

	# Bring the character to life via the Join Handshake — the per-character
	# bring-up sequence (load → init → sync → notify). PlayerManager owns the
	# spawn LIFECYCLE (find node, cache, active_players bookkeeping); the
	# handshake owns the bring-up CONTRACT. See scripts/Networking/join_handshake.gd.
	await JoinHandshake.new(self, player_instance, id, character_type, username, player_data).run()


func _load_player_data_from_file(username: String) -> Dictionary:
	var data := PlayerPersistence.read_save_file(username)
	return PlayerSaveSchema.normalize_loaded(data)


func _load_player_data_async(username: String) -> Dictionary:
	if NetworkManager.use_local_save:
		#print("PlayerManager: Local Save enabled. Loading from file for ", username)
		return _load_player_data_from_file(username)

	# Wait if another load is already in progress (reusing persistent HTTPRequest)
	while _load_in_progress:
		await get_tree().process_frame

	_load_in_progress = true

	# First attempt. BackendHttp owns the wire protocol (headers / JSON / parse);
	# this function keeps its own single-flight policy (_load_in_progress) + the
	# retry-then-local-file fallback.
	var resp: Dictionary = await BackendHttp.post_json(_load_http_request, _api_url + "/load", {"username": username})
	if not resp.started:
		_load_in_progress = false
		return _load_player_data_from_file(username)
	if resp.code == 200 and resp.json != null:
		_load_in_progress = false
		if resp.json.is_empty():
			return {}  # API reached, no existing save → brand-new character
		return PlayerSaveSchema.normalize_loaded(resp.json)

	# Retry once after a short delay.
	await get_tree().create_timer(1.0).timeout
	var retry: Dictionary = await BackendHttp.post_json(_load_http_request, _api_url + "/load", {"username": username})
	_load_in_progress = false
	if retry.started and retry.code == 200 and retry.json != null:
		if retry.json.is_empty():
			return {}
		return PlayerSaveSchema.normalize_loaded(retry.json)

	# API unavailable after retry — fall back to the local save file.
	return _load_player_data_from_file(username)


func _save_player_data_to_file(data: Dictionary):
	"""Save player data to file (fallback) — read-merge-write to the canonical
	res://saves path. Delegates to the shared PlayerPersistence helper so the
	path and merge semantics match NetworkManager / SaveManager exactly. (This
	previously wrote a bare `player_%s.json` to the process CWD — a stray,
	wrong-directory save that never lined up with the real saves folder.)"""
	PlayerPersistence.write_save_file_merged(data)


func _get_quick_save_data(player_id: int) -> Dictionary:
	"""Get minimal save data for disconnect"""
	if not player_id in active_players:
		return {}
	
	var player_info = active_players[player_id]
	var player_node = get_player_node(player_id)
	
	var data = {
		"username": player_info.get("username", ""),
		"last_map": MapManager.get_player_map(player_id),
		"party_id": player_info.get("party_id", -1)
	}
	
	if player_node:
		if player_node.health_component:
			data["current_health"] = player_node.health_component.current_health
			data["max_health"] = player_node.health_component.max_health
		if player_node.level_component:
			data["level"] = player_node.level_component.level
			data["experience"] = player_node.level_component.experience
	
	return data


func _is_cached_node_valid(node: Variant) -> bool:
	"""A cached node is usable only if it still exists and is attached to the
	scene tree (a node removed during a map change reports is_inside_tree() == false)."""
	return is_instance_valid(node) \
		and not node.is_queued_for_deletion() \
		and node.is_inside_tree()


func get_player_node(player_id: int) -> MultiplayerPlayerV2:
	"""Find player node across all maps. Uses a node cache to avoid scanning
	every active map on each call (this runs 100+ times/sec on the server)."""
	# Fast path: return cached node if still valid.
	var cached: Variant = _node_cache.get(player_id)
	if cached != null:
		if _is_cached_node_valid(cached):
			return cached
		# Stale entry — drop it and fall through to a full scan.
		_node_cache.erase(player_id)

	if not multiplayer.is_server():
		# Client only has current map
		var current_map = MapManager.current_map_instance
		if current_map:
			var players_node = current_map.get_node_or_null("Players")
			if players_node and players_node.has_node(str(player_id)):
				var node = players_node.get_node(str(player_id))
				if is_instance_valid(node) and not node.is_queued_for_deletion():
					_node_cache[player_id] = node
					return node
	else:
		# Server checks all active maps
		for map_id in MapManager.active_maps.keys():
			var map_instance = MapManager.active_maps[map_id].scene_instance
			if not is_instance_valid(map_instance):
				continue
			var players_node = map_instance.get_node_or_null("Players")
			if players_node and players_node.has_node(str(player_id)):
				var node = players_node.get_node(str(player_id))
				if is_instance_valid(node) and not node.is_queued_for_deletion():
					_node_cache[player_id] = node
					return node

	return null


func get_active_players() -> Dictionary:
	return active_players.duplicate()


func get_player_count() -> int:
	return active_players.size()


func get_player_info(id: int) -> Dictionary:
	return active_players.get(id, {})


func get_player_id_from_name(username: String) -> int:
	for player_id in active_players:
		if active_players[player_id].get("username") == username:
			return player_id
	return -1


## Resolves the calling peer of a client-intent RPC to its player node + name.
## MUST be called from inside the RPC handler body — it reads
## `multiplayer.get_remote_sender_id()`, which only returns the real sender
## while the RPC stack is live (same constraint as TradeManager._sender()).
##
## Folds the copy-pasted server-intent prelude into one place: the sender-id
## read, the host `0 → 1` normalization (a host call has sender id 0 and is
## the server, peer 1), the player-node lookup, the validity guard, and the
## username read. Returns an empty Dictionary `{}` when the caller has no
## valid player node, so callers guard with `if resolved.is_empty(): return`.
## On success returns `{ "peer_id": int, "node": MultiplayerPlayerV2,
## "username": String }`.
func resolve_intent() -> Dictionary:
	var caller := multiplayer.get_remote_sender_id()
	if caller == 0:
		caller = 1
	var node := get_player_node(caller)
	if not is_instance_valid(node):
		return {}
	return {
		"peer_id": caller,
		"node": node,
		"username": node.username,
	}


## Resolves a name (case-insensitive for bots, exact for players) to a peer id,
## consulting BotManager for bots. Returns -1 if no player OR bot matches.
## Used by party/trade name-based intents that accept either a player or a bot.
func resolve_by_name(player_name: String) -> int:
	var pid := get_player_id_from_name(player_name)
	if pid != -1:
		return pid
	# Delegate the bot name/id lookup to BotManager rather than re-scanning
	# active_bots here. _find_bot_by_name_or_id returns 0 when not found.
	var bot_id := BotManager._find_bot_by_name_or_id(player_name)
	if bot_id != 0:
		return bot_id
	return -1


## Player-ONLY name resolution (excludes bots). Returns the peer id, or -1.
## QuestManager uses this — quests are never granted to bots. `active_players`
## holds bots too (negative ids), so filter them out explicitly.
func resolve_player_only(player_name: String) -> int:
	var pid := get_player_id_from_name(player_name)
	if pid != -1 and BotManager.is_bot(pid):
		return -1
	return pid


## Stores a player's live state, captured at map-change time, so the imminent
## respawn can restore it without a save-backend round-trip. Called by
## MapManager.request_map_change just before the old character node is freed.
func set_carried_state(player_id: int, data: Dictionary) -> void:
	_carried_state[player_id] = data


func _on_player_spawned(player_id: int) -> void:
	"""Called by MapManager when a server-side player spawn has completed.
	Continue initialization for the player (clients only were deferred).
	"""
	if not player_id in active_players:
		#print("PlayerManager: _on_player_spawned called for unknown player %d" % player_id)
		return

	var info = active_players[player_id]
	var username = info.get("username", "Player")

	# On a map change the player's live state was carried over in memory — use
	# it directly and skip the save-backend round-trip. An initial spawn has no
	# carried state, so fall back to a real load from file/API.
	#
	# Map change fires _on_player_spawned TWICE for the host: once from
	# MapManager.player_spawned (carries live state) and again from the host's
	# own client spawn-ACK (client_player_spawned). The first consumes the
	# carried state; without a guard the second would do a STALE backend
	# reload that clobbers freshly-earned points + purchased upgrades. So:
	# when we consume carried state, mark it; a subsequent spawn for the same
	# player that finds no carried state skips the redundant reload entirely.
	var player_data: Dictionary
	if _carried_state.has(player_id):
		player_data = _carried_state[player_id]
		_carried_state.erase(player_id)
		_loaded_from_carry[player_id] = true
	elif _loaded_from_carry.get(player_id, false):
		# Already initialized from carried state this spawn cycle — the node
		# is live and correct. Don't reload stale data over it.
		_loaded_from_carry.erase(player_id)
		return
	else:
		player_data = await _load_player_data_async(username)

	# Prefer character_type from player_data — `info.character_type` is set
	# from the client's character pick at join time and is never refreshed
	# when the class changes mid-session (job advancement). The carried
	# state (from get_save_data("all")) and the backend load both include
	# the current value, so trust them when present. Without this the
	# next map change reverts an advanced player back to their base class.
	var character_type: int = player_data.get("character_type", info.get("character_type", -1))
	info["character_type"] = character_type

	# Continue initialization
	call_deferred("_initialize_spawned_player", player_id, character_type, username, player_data)


@rpc("any_peer", "call_local", "reliable")
func player_input(input_type: String, data: Variant = null):
	"""Handles input actions from clients safely."""
	if not multiplayer.is_server(): return

	var peer_id = multiplayer.get_remote_sender_id()
	if BotManager.is_bot(peer_id):
		return

	var player_node = get_player_node(peer_id)

	if not is_instance_valid(player_node):
		# Player might be dead or changing maps - ignore
		return

	match input_type:
		"jump": player_node.do_jump = true
		"drop": player_node.do_drop = true
		"attack": player_node.do_attack = true
		"pickup": player_node.do_pickup = data
		"portal": player_node.do_portal_interact = true
		"staff_cycle_element":
			# PR 7 — Staff signature: cycle the active element (FIRE -> ICE ->
			# LIGHTNING). The component is server-authoritative and syncs the new
			# element to the owning client. The input branch that sends this is
			# already gated on the STAFF discipline client-side; the component's
			# own is_server guard is the authoritative gate.
			var sec = player_node.get("staff_element_component")
			if sec != null and is_instance_valid(sec):
				sec.cycle_element()
		"dagger_shadowmeld":
			# PR 7 — Dagger signature: toggle Shadowmeld stealth on/off. The
			# component is server-authoritative and decides enter-vs-exit (and
			# enforces the enter cooldown). The input branch that sends this is
			# already gated on the DAGGER discipline client-side; the component's
			# own is_server guard is the authoritative gate.
			var smc = player_node.get("shadowmeld_component")
			if smc != null and is_instance_valid(smc):
				smc.toggle_shadowmeld()
		"weapon_swap":
			# PR 3: route weapon-swap intent through the player node's
			# request_weapon_swap_server RPC. The player node owns the
			# equipment component reference and the cleanup/death gate.
			if player_node.has_method("request_weapon_swap_server"):
				player_node.request_weapon_swap_server()
		"channel_release":
			# Hold-channel (Sky Volley / Stormcall): the client let go of the
			# hotbar key — flag the release; the attack state consumes it
			# server-side (after the minimum hold) and ends the channel early.
			# Harmless when no channel is running (the flag is cleared on the
			# next channel start).
			if "channel_release_requested" in player_node:
				player_node.channel_release_requested = true
