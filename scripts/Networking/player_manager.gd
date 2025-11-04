# player_manager.gd - AutoLoad singleton
extends Node

var character_scene = preload("res://scenes/Player/player.tscn")
var active_players: Dictionary = {}


func add_host_player():
	"""Add the host player (ID 1) in listen server mode"""
	call_deferred("add_player", 1)

func add_player(id: int):
	print("Player %d joined - preparing to spawn character" % id)
	NetworkUtils.log_network_event("PLAYER_JOIN", "Player ID: %d" % id)
	
	active_players[id] = {
		"id": id,
		"character_type": -1,  # Not selected yet
		"spawn_time": Time.get_unix_time_from_system(),
		"synced": false,
		"party_id": -1 # No party initially
	}
	
	# Sync existing entities to new player
	_sync_entities_to_player(id)
	
	# Request character selection from client
	rpc_id(id, "_request_character_selection", id)

func remove_player(id: int):
	print("Player %d left - removing character" % id)
	NetworkUtils.log_network_event("PLAYER_LEAVE", "Player ID: %d" % id)
	
	# Notify PartyManager that player disconnected
	if PartyManager:
		PartyManager._on_player_disconnected(id)
	
	# Remove from active players
	if id in active_players:
		active_players.erase(id)
	
	# Remove player node from scene
	var spawn_node = NetworkUtils.get_players_spawn_node(get_tree())
	if spawn_node and spawn_node.has_node(str(id)):
		(spawn_node.get_node(str(id)) as MultiplayerPlayerV2)._data_changed()
		spawn_node.get_node(str(id)).queue_free()


func cleanup():
	"""Remove all networked entities and reset player tracking"""
	print("Cleaning up all players and entities")
	NetworkUtils.clear_networked_entities(get_tree())
	active_players.clear()

func get_active_players() -> Dictionary:
	return active_players.duplicate()

func get_player_count() -> int:
	return active_players.size()

func has_player(id: int) -> bool:
	return id in active_players

func get_player_info(id: int) -> Dictionary:
	return active_players.get(id, {})

func get_player_node(player_id: int) -> MultiplayerPlayerV2:
	var spawn_node = NetworkUtils.get_players_spawn_node(get_tree())
	if spawn_node:
		for child in spawn_node.get_children():
			if child is MultiplayerPlayerV2 and child.player_id == player_id:
				return child
	return null # Return null if player node not found

func get_player_id_from_name(player_name: String) -> int:
	# This function should only run on the server where all player data is available.
	if not multiplayer.is_server():
		# Returning -1 on client because client may not have all player data.
		return -1

	for player_id in active_players.keys():
		var player_info = active_players[player_id]
		if player_info.get("username", "").to_lower() == player_name.to_lower():
			return player_id
	
	return -1 # Player not found

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

	var player_data: Dictionary = _load_player_data_from_file(username)
	
	_spawn_character_for_player(id, character_type, username, player_data)
	
	
func _load_player_data_from_file(username: String) -> Dictionary:
	var file_path = "player_%s.json" % username
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		var data = JSON.parse_string(file.get_as_text())
		file.close()
		data["party_id"] = data.get("party_id", -1) # Load party_id, default to -1
		return data
	return {} # Return empty dictionary if no save file exists
	

func _spawn_character_for_player(id: int, character_type: int, username: String, player_data: Dictionary):
	"""Spawn a character instance for the given player"""
	var player_instance = character_scene.instantiate() as MultiplayerPlayerV2

	player_instance.player_id = id
	player_instance.name = str(id)
	
	if player_instance.class_component:
		player_instance.class_component.change_class(character_type)
	
	player_instance.add_to_group("networked_entities")

	var spawn_node = NetworkUtils.get_players_spawn_node(get_tree())
	if spawn_node:
		spawn_node.add_child(player_instance, true)
		
		player_instance.set_username.rpc(username)
		player_instance.class_component.change_class_rpc(character_type)
		
		if player_instance.stats_component:
			player_instance.stats_component.set_loading_mode(true)
		
		# This prevents ability points from being granted during initial setup
		if player_instance.ability_component:
			player_instance.ability_component.disconnect_level_signals()
		
		# Set loading flag to prevent level up SFX during data load
		if player_instance.level_component:
			player_instance.level_component._is_loading_data = true
		
		# Load player data AFTER adding to scene
		var has_save_data = not player_data.is_empty()
		if has_save_data:
			player_instance._load_data(player_data)
			active_players[id]["party_id"] = player_data.get("party_id", -1) # Set party_id from loaded data
			player_instance.set_current_party_id(active_players[id]["party_id"]) # Pass party_id to player_instance
			
			# Wait for level component to finish loading and granting ability points
			if player_instance.level_component:
				for i in range(5):
					await get_tree().process_frame
		
		# Reset loading flag
		if player_instance.level_component:
			player_instance.level_component._is_loading_data = false
		
		# Load inventory - this now handles sync internally via PlayerInventory wrapper
		if player_instance.player_inventory:
			var inventory_data = player_data.get("inventory", {})
			player_instance.player_inventory.load_player_inventory_silent(inventory_data)
		
		if not player_data:
			player_instance.equipment_component.weapon_slot.item = ResourceManager.get_item_by_name("Iron Sword")
			player_instance.equipment_component.chest_slot.item = ResourceManager.get_item_by_name("White Shirt")
			player_instance.equipment_component.legs_slot.item = ResourceManager.get_item_by_name("Blue Jean Shorts")
			player_instance.equipment_component.feet_slot.item = ResourceManager.get_item_by_name("Leather Sandals")
		
		# Make sure health is set correctly from the save data
		if player_instance.health_component:
			player_instance.health_component.current_health = player_data.get("current_health", 100)
			
		# Recalculate stats after all equipment is loaded/set
		if player_instance.stats_component:
			await get_tree().process_frame # Ensure equipment signals have processed
			player_instance.stats_component.set_loading_mode(false)
			player_instance.stats_component._recalculate_stats_server("PlayerSpawn")
			
		# Reconnect ability component signals after all setup is complete
		if player_instance.ability_component:
			player_instance.ability_component.reconnect_level_signals()

		# IMPORTANT: Sync abilities AFTER data is fully loaded
		if id != 1 and player_instance.ability_component:
			await get_tree().process_frame
			player_instance.ability_component.sync_all_abilities_to_client(id)
		
		# Make sure health is set correctly from the save data
		if player_instance.health_component:
			player_instance.health_component.current_health = player_data.get("current_health", 100)
			
		if id != 1 and player_instance.buff_component:
			await get_tree().process_frame
			var buff_component = player_instance.buff_component
			buff_component.sync_all_buffs_to_client(id)
		
		if id in active_players:
			active_players[id]["synced"] = true
	else:
		push_error("Could not find Players spawn node - cannot spawn character")
		player_instance.queue_free()


func _sync_entities_to_player(id: int):
	"""Sync state of all existing networked entities to new player"""
	var entity_count = 0
	for entity in get_tree().get_nodes_in_group("networked_entities"):
		var state_machine = entity.get_node_or_null("StateMachine")
		if state_machine and state_machine.has_method("sync_state_to_peer"):
			state_machine.sync_state_to_peer(id)
			entity_count += 1
		if (entity is DroppedItem):
			entity.sync_state_to_peer(id)
			entity_count += 1
	
	if entity_count > 0:
		print("Synced %d entities to player %d" % [entity_count, id])

func force_respawn_player(id: int):
	"""Force respawn a player (useful for debugging or admin functions)"""
	if not multiplayer.is_server():
		print("Cannot force respawn: not server")
		return
	
	if not id in active_players:
		print("Cannot force respawn: player %d not found" % id)
		return
	
	# Remove existing character
	remove_player(id)
	await get_tree().process_frame
	
	# Re-add player
	add_player(id)
