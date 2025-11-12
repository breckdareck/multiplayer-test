# player_manager.gd - UPDATED with Map Support
extends Node

var character_scene = preload("res://scenes/Player/player.tscn")
var active_players: Dictionary = {}


func _ready() -> void:
	# Connect to MapManager's player_spawned so we can finish initialization
	# after the server-side spawn is completed.
	if MapManager:
		MapManager.player_spawned.connect(_on_player_spawned)


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
		"character_type": -1,
		"spawn_time": Time.get_unix_time_from_system(),
		"synced": false,
		"party_id": -1,
		"last_map": "" # Track last map for respawn
	}
	
	# Request character selection from client
	rpc_id(id, "_request_character_selection", id)


func remove_player(id: int):
	print("Player %d left - removing character" % id)
	NetworkUtils.log_network_event("PLAYER_LEAVE", "Player ID: %d" % id)
	
	# Save their current map before disconnect
	if multiplayer.is_server() and id in active_players:
		var current_map = MapManager.get_player_map(id)
		if current_map:
			active_players[id]["last_map"] = current_map
			# Quick save before disconnect
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


@rpc("call_local", "any_peer")
func _request_character_selection(id: int):
	"""Called on client to request their character selection"""
	var menu_container = get_tree().get_current_scene().get_node_or_null("%MenuContainer")
	var selected_char: int = 0
	var username: String = "Player"
	
	if menu_container and "selected_character" in menu_container:
		selected_char = menu_container.selected_character
		username = menu_container.get_username()
	
	print("PlayerManager: Client sending character: %s & username: %s from PID: %d" % [Constants.ClassType.find_key(selected_char), username, id])
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
	var player_data: Dictionary = _load_player_data_from_file(username)
	
	# Determine spawn map
	var spawn_map = player_data.get("last_map", MapManager.DEFAULT_MAP)
	if spawn_map.is_empty():
		spawn_map = MapManager.DEFAULT_MAP
	
	active_players[id]["last_map"] = spawn_map
	
	# Request map spawn through MapManager
	# For the host (player 1) we await so initialization continues immediately.
	if id == 1 and multiplayer.is_server():
		await MapManager.request_spawn_on_map(id, spawn_map)
		# Now initialize the player character that was spawned
		await _initialize_spawned_player(id, character_type, username, player_data)
		return

	# For remote players we store the loaded player data and request the map.
	# Initialization will continue when MapManager emits `player_spawned`.
	active_players[id]["player_data"] = player_data
	active_players[id]["character_type"] = character_type
	active_players[id]["username"] = username
	MapManager.request_spawn_on_map(id, spawn_map)
	return


func _initialize_spawned_player(id: int, character_type: int, username: String, player_data: Dictionary):
	"""Initialize a player that has been spawned by MapManager"""
	
	# Wait a frame to ensure the player node is fully added to the tree
	await get_tree().process_frame
	
	var player_instance = get_player_node(id)
	if not player_instance:
		push_error("Could not find spawned player %d to initialize! (After waiting 1 frame)" % id)
		# Try one more time with a longer wait
		await get_tree().process_frame
		player_instance = get_player_node(id)
		if not player_instance:
			push_error("STILL could not find spawned player %d after 2 frames!" % id)
			return
	
	print("PlayerManager: Found player %d instance, starting initialization" % id)
	
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
	
	# Set default equipment if no save
	if not player_data:
		player_instance.equipment_component.weapon_slot.item = ResourceManager.get_item_by_name("Iron Sword")
		player_instance.equipment_component.chest_slot.item = ResourceManager.get_item_by_name("White Shirt")
		player_instance.equipment_component.legs_slot.item = ResourceManager.get_item_by_name("Blue Jean Shorts")
		player_instance.equipment_component.feet_slot.item = ResourceManager.get_item_by_name("Leather Sandals")
	
	# Set health
	if player_instance.health_component:
		player_instance.health_component.current_health = player_data.get("current_health", 100)
	
	# Recalculate stats
	if player_instance.stats_component:
		await get_tree().process_frame
		player_instance.stats_component.set_loading_mode(false)
		player_instance.stats_component._recalculate_stats_server("PlayerSpawn")
	
	# Reconnect signals
	if player_instance.ability_component:
		player_instance.ability_component.reconnect_level_signals()
	
	# Sync to client
	if id != 1 and player_instance.ability_component:
		await get_tree().process_frame
		player_instance.ability_component.sync_all_abilities_to_client(id)
	
	if player_instance.health_component:
		player_instance.health_component.current_health = player_data.get("current_health", 100)
	
	if id != 1 and player_instance.buff_component:
		await get_tree().process_frame
		player_instance.buff_component.sync_all_buffs_to_client(id)
	
	if id in active_players:
		active_players[id]["synced"] = true
	
	# Set username and class over network
	player_instance.set_username.rpc(username)
	player_instance.class_component.change_class_rpc(character_type)


func _load_player_data_from_file(username: String) -> Dictionary:
	var file_path = "player_%s.json" % username
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		data["party_id"] = data.get("party_id", -1)
		data["last_map"] = data.get("last_map", "")
		return data
	return {}


func _save_player_data_to_file(data: Dictionary):
	"""Save player data to file"""
	var username = data.get("username", "")
	if username.is_empty():
		return
	
	var file_path = "player_%s.json" % username
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))
		file.close()


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
				if is_instance_valid(node):
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
				if is_instance_valid(node):
					return node
	
	return null


func get_active_players() -> Dictionary:
	return active_players.duplicate()


func get_player_count() -> int:
	return active_players.size()


func get_player_info(id: int) -> Dictionary:
	return active_players.get(id, {})


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
	var player_data = info.get("player_data", {})

	# Continue initialization
	call_deferred("_initialize_spawned_player", player_id, character_type, username, player_data)
