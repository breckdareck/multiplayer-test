# player_manager.gd - UPDATED with Map Support
extends Node

var character_scene = preload("res://scenes/Player/player.tscn")
var active_players: Dictionary = {}
var _load_http_request: HTTPRequest
var _load_in_progress: bool = false
var _api_url: String = ""


func _ready() -> void:
	# Load API URL from config (supports environment variable override)
	_api_url = UserConfig.get_backend_api_url() + "/player"
	print("PlayerManager: Using API URL: %s" % _api_url)
	
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


func add_player(id: int):
	print("Player %d joined - preparing to spawn character" % id)
	NetworkUtils.log_network_event("PLAYER_JOIN", "Player ID: %d" % id)
	
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
	print("Player %d left - removing character" % id)
	NetworkUtils.log_network_event("PLAYER_LEAVE", "Player ID: %d" % id)
	
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
			print("PlayerManager: Saved player '%s' via SaveManager on disconnect." % username)
		elif not username.is_empty():
			# Player node already gone — fall back to quick save with what we have
			print("PlayerManager: WARNING - Player %d node not found for full save, using quick save" % id)
			var quick_data = _get_quick_save_data(id)
			if not quick_data.is_empty():
				_save_player_data_to_file(quick_data)

	# Notify map manager to clean up
	MapManager.handle_player_disconnect(id)
	
	# Notify PartyManager
	if PartyManager:
		PartyManager._on_player_disconnected(id)
	
	# Remove from active players
	if id in active_players:
		active_players.erase(id)


func cleanup():
	"""Remove all networked entities and reset player tracking"""
	print("Cleaning up all players and entities")
	active_players.clear()


# This function is called on the client to gather character selection info
# and send it to the server.
@rpc("call_local", "any_peer") # This RPC is called by the server on the client
func _client_send_initial_info(id: int):
	print("PlayerManager: Client %d preparing to send initial info." % id)
	
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
	
	print("PlayerManager: Client sending character: %s & username: %s from PID: %d" % [Constants.ClassType.find_key(selected_char), username, id])
	# Send the gathered info to the server (ID 1)
	rpc_id(1, "_receive_initial_info", id, selected_char, username)


@rpc("call_local", "any_peer")
func _receive_initial_info(id: int, character_type: int, username: String):
	"""Called on server with all info needed to spawn a player."""
	if not multiplayer.is_server():
		return
	
	print("PlayerManager: Server received character: %s & username: %s from PID: %d" % [Constants.ClassType.find_key(character_type), username, id])
	
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
	# Cache loaded data so _on_player_spawned doesn't need to load again
	active_players[id]["_cached_player_data"] = player_data

	# Request map spawn through MapManager
	# For the host (player 1) we await so initialization continues immediately.
	if id == 1 and multiplayer.is_server():
		await MapManager.request_map_change(id, spawn_map)
		active_players[id].erase("_cached_player_data")
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
	
	print("PlayerManager: Found player %d instance, starting initialization" % id)
	
	player_instance.player_id = id
	player_instance.name = str(id)
	
	# Set up player
	if not player_instance.class_component:
		push_error("Player %d missing class_component!" % id)
	elif player_instance.class_component:
		player_instance.class_component.change_class(character_type)
	
	if not player_instance.stats_component:
		push_error("Player %d missing stats_component!" % id)
	elif player_instance.stats_component:
		player_instance.stats_component.set_loading_mode(true)
	
	if player_instance.ability_component:
		player_instance.ability_component.disconnect_level_signals()
	
	if player_instance.level_component:
		player_instance.level_component._is_loading_data = true
	
	# Load player data
	var has_save_data = not player_data.is_empty()
	if has_save_data:
		player_instance._load_data(player_data)
		active_players[id]["party_id"] = player_data.get("party_id", -1)
		player_instance.set_current_party_id(active_players[id]["party_id"])
		
		if player_instance.level_component:
			for i in range(5):
				await get_tree().process_frame
	
	# Reset loading flags
	if player_instance.level_component:
		player_instance.level_component._is_loading_data = false
	
	# Load inventory
	if player_instance.player_inventory:
		var inventory_data = player_data.get("inventory", {})
		player_instance.player_inventory.load_player_inventory_silent(inventory_data)
		# Sync money to client
		if id != 1:
			var monies = player_data.get("monies", 0)
			# Also check if monies is inside inventory data structure depending on save format
			if monies == 0 and inventory_data.has("monies"):
				monies = inventory_data.get("monies", 0)
				
			player_instance.player_inventory.set_monies_rpc.rpc_id(id, monies)

	
	# Set default equipment if no save or no inventory data, or if inventory is empty (new character)
	var inv_data_check = player_data.get("inventory", {})
	var has_items = not inv_data_check.get("slots", []).is_empty()
	var has_equipment = not inv_data_check.get("equipment", {}).is_empty()
	
	if not player_data or not player_data.has("inventory") or (not has_items and not has_equipment):
		print("PlayerManager: Adding default items for player %d" % id)
		player_instance.equipment_component.weapon_slot.item = ResourceManager.get_item_by_name("Iron Sword")
		player_instance.equipment_component.chest_slot.item = ResourceManager.get_item_by_name("White Shirt")
		player_instance.equipment_component.legs_slot.item = ResourceManager.get_item_by_name("Blue Jean Shorts")
		player_instance.equipment_component.feet_slot.item = ResourceManager.get_item_by_name("Leather Sandals")
	
	# Set health
	if player_instance.health_component:
		player_instance.health_component.current_health = player_data.get("current_health", 100)
	
	# Recalculate stats
	if player_instance.stats_component:
		player_instance.stats_component.set_loading_mode(false)
		player_instance.stats_component.mark_stats_dirty()
	
	# Reconnect signals
	if player_instance.ability_component:
		player_instance.ability_component.reconnect_level_signals()
	
	# Set username and class over network
	player_instance.set_username.rpc(username)
	player_instance.class_component.change_class_rpc(character_type)

	# Sync to client
	if id != 1:
		# Tell client to start loading mode (suppress saves)
		player_instance.set_loading_state_rpc.rpc_id(id, true)
		
		if player_instance.ability_component:
			await get_tree().process_frame
			player_instance.ability_component.sync_all_abilities_to_client(id)

	
	if player_instance.health_component:
		player_instance.health_component.current_health = player_data.get("current_health", 100)
	
	if id != 1 and player_instance.buff_component:
		await get_tree().process_frame
		player_instance.buff_component.sync_all_buffs_to_client(id)
	
	if id in active_players:
		active_players[id]["synced"] = true
	
	# Loading done

	if id != 1:
		# Tell client loading is done (enable saves)
		player_instance.set_loading_state_rpc.rpc_id(id, false)


func _load_player_data_from_file(username: String) -> Dictionary:
	var file_path = "res://saves/player_%s.json" % username
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		if data:
			data["party_id"] = data.get("party_id", -1)
			data["last_map"] = data.get("last_map", "")
			return data
	return {}


func _load_player_data_async(username: String) -> Dictionary:
	if NetworkManager.use_local_save:
		print("PlayerManager: Local Save enabled. Loading from file for ", username)
		return _load_player_data_from_file(username)

	# Wait if another load is already in progress (reusing persistent HTTPRequest)
	while _load_in_progress:
		await get_tree().process_frame

	_load_in_progress = true
	print("PlayerManager: Attempting to load data for %s from API..." % username)

	var json = JSON.stringify({"username": username})
	var headers = ["Content-Type: application/json"]
	var error = _load_http_request.request(_api_url + "/load", headers, HTTPClient.METHOD_POST, json)

	if error != OK:
		print("PlayerManager: HTTP load request failed to start for %s. Error: %d" % [username, error])
		_load_in_progress = false
		print("PlayerManager: WARNING - Loading %s from LOCAL FILE (API unavailable)" % username)
		return _load_player_data_from_file(username)

	var result = await _load_http_request.request_completed
	var response_code = result[1]
	var body = result[3]

	if response_code == 200:
		var json_result = JSON.parse_string(body.get_string_from_utf8())
		if json_result != null:
			_load_in_progress = false
			if json_result.is_empty():
				print("PlayerManager: Loaded %s via API (no existing save data)" % username)
				return {}

			print("PlayerManager: Loaded %s via API" % username)
			# Ensure default fields exist
			json_result["party_id"] = json_result.get("party_id", -1)
			json_result["last_map"] = json_result.get("last_map", "")
			return json_result

	print("PlayerManager: API load failed for %s (code: %d). Retrying..." % [username, response_code])
	await get_tree().create_timer(1.0).timeout

	# Retry once
	error = _load_http_request.request(_api_url + "/load", headers, HTTPClient.METHOD_POST, json)
	if error != OK:
		_load_in_progress = false
		print("PlayerManager: WARNING - Loading %s from LOCAL FILE (API unavailable)" % username)
		return _load_player_data_from_file(username)

	result = await _load_http_request.request_completed
	response_code = result[1]
	body = result[3]
	_load_in_progress = false

	if response_code == 200:
		var json_result = JSON.parse_string(body.get_string_from_utf8())
		if json_result != null:
			if json_result.is_empty():
				print("PlayerManager: Retry succeeded for %s (no existing save data)" % username)
				return {}

			print("PlayerManager: Retry succeeded for %s" % username)
			json_result["party_id"] = json_result.get("party_id", -1)
			json_result["last_map"] = json_result.get("last_map", "")
			return json_result

	print("PlayerManager: WARNING - Loading %s from LOCAL FILE (API unavailable after retry)" % username)
	return _load_player_data_from_file(username)


func _save_player_data_to_file(data: Dictionary):
	"""Save player data to file (Fallback) - Merges partial updates"""
	var username = data.get("username", "")
	if username.is_empty():
		return
	
	var file_path = "player_%s.json" % username
	var existing_data = {}
	
	# Read existing data first to merge
	if FileAccess.file_exists(file_path):
		var file_read = FileAccess.open(file_path, FileAccess.READ)
		if file_read:
			existing_data = JSON.parse_string(file_read.get_as_text())
			file_read.close()
			if existing_data == null: existing_data = {}
	
	# Merge new data into existing data
	existing_data.merge(data, true) # true = overwrite existing keys
	
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(existing_data))
		file.close()
		print("PlayerManager: Saved to local file for ", username)


func _save_player_data_async(data: Dictionary) -> void:
	var username = data.get("username", "")
	if username.is_empty():
		return

	if NetworkManager.use_local_save:
		print("PlayerManager: Local Save enabled. Saving to file for ", username)
		_save_player_data_to_file(data)
		return

	print("PlayerManager: Attempting to save data for %s to API..." % username)

	var request = HTTPRequest.new()
	add_child(request)
	request.timeout = 5.0

	var payload = {
		"username": username,
		"data": data
	}

	var json = JSON.stringify(payload)
	var headers = ["Content-Type: application/json"]
	var error = request.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json)

	if error != OK:
		print("PlayerManager: HTTP save request failed to start for %s. Error: %d" % [username, error])
		request.queue_free()
		print("PlayerManager: WARNING - Saved %s to LOCAL FILE (API unavailable)" % username)
		_save_player_data_to_file(data)
		return

	var result = await request.request_completed
	var response_code = result[1]

	if response_code == 200:
		print("PlayerManager: Saved %s via API" % username)
		request.queue_free()
		return

	# First attempt failed — retry once after 1 second
	print("PlayerManager: API save failed for %s (code: %d), retrying..." % [username, response_code])
	await get_tree().create_timer(1.0).timeout

	error = request.request(_api_url + "/save", headers, HTTPClient.METHOD_POST, json)
	if error != OK:
		request.queue_free()
		print("PlayerManager: WARNING - Saved %s to LOCAL FILE (API unavailable)" % username)
		_save_player_data_to_file(data)
		return

	result = await request.request_completed
	response_code = result[1]
	request.queue_free()

	if response_code == 200:
		print("PlayerManager: Retry succeeded for %s" % username)
	else:
		print("PlayerManager: WARNING - Saved %s to LOCAL FILE (API unavailable after retry, code: %d)" % [username, response_code])
		_save_player_data_to_file(data)


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


func get_player_node(player_id: int) -> MultiplayerPlayerV2:
	"""Find player node across all maps"""
	if not multiplayer.is_server():
		# Client only has current map
		var current_map = MapManager.current_map_instance
		if current_map:
			var players_node = current_map.get_node_or_null("Players")
			if players_node and players_node.has_node(str(player_id)):
				var node = players_node.get_node(str(player_id))
				if is_instance_valid(node) and not node.is_queued_for_deletion():
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


func _on_player_spawned(player_id: int) -> void:
	"""Called by MapManager when a server-side player spawn has completed.
	Continue initialization for the player (clients only were deferred).
	"""
	if not player_id in active_players:
		print("PlayerManager: _on_player_spawned called for unknown player %d" % player_id)
		return

	var info = active_players[player_id]
	var character_type = info.get("character_type", -1)
	var username = info.get("username", "Player")

	# Use cached data from _receive_initial_info instead of loading again
	var player_data: Dictionary = info.get("_cached_player_data", {})
	active_players[player_id].erase("_cached_player_data")

	# Continue initialization
	call_deferred("_initialize_spawned_player", player_id, character_type, username, player_data)


@rpc("any_peer", "call_local", "reliable")
func player_input(input_type: String, data: Variant = null):
	"""Handles input actions from clients safely."""
	if not multiplayer.is_server(): return
	
	var peer_id = multiplayer.get_remote_sender_id()
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
