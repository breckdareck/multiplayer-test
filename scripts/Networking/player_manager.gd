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
		"synced": false
	}
	
	# Sync existing entities to new player
	_sync_entities_to_player(id)
	
	# Request character selection from client
	rpc_id(id, "_request_character_selection", id)

func remove_player(id: int):
	print("Player %d left - removing character" % id)
	NetworkUtils.log_network_event("PLAYER_LEAVE", "Player ID: %d" % id)
	
	# Remove from active players
	if id in active_players:
		active_players.erase(id)
	
	# Remove player node from scene
	var spawn_node = NetworkUtils.get_players_spawn_node(get_tree())
	if spawn_node and spawn_node.has_node(str(id)):
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

@rpc("call_local", "any_peer")
func _request_character_selection(id: int):
	"""Called on client to request their character selection"""
	var menu_container = get_tree().get_current_scene().get_node_or_null("%MenuContainer")
	var selected_char = 0
	
	if menu_container and "selected_character" in menu_container:
		selected_char = menu_container.selected_character
	
	print("Client sending character selection: %d" % selected_char)
	rpc_id(1, "_receive_character_selection", id, selected_char)

@rpc("call_local", "any_peer")
func _receive_character_selection(id: int, character_type: int):
	"""Called on server when client sends their character selection"""
	if not multiplayer.is_server():
		return
	
	print("Server received character selection %d from player %d" % [character_type, id])
	
	# Update player info
	if id in active_players:
		active_players[id]["character_type"] = character_type
	
	# Spawn the character
	_spawn_character_for_player(id, character_type)

func _spawn_character_for_player(id: int, character_type: int):
	"""Spawn a character instance for the given player"""
	var player_instance = character_scene.instantiate()
	
	player_instance.player_id = id
	player_instance.name = str(id)
	var controller = player_instance as MultiplayerPlayerV2
	if controller.class_component:
		controller.class_component.change_class(character_type)
		
	# Add to networked entities group for proper cleanup
	player_instance.add_to_group("networked_entities")
	
	var spawn_node = NetworkUtils.get_players_spawn_node(get_tree())
	if spawn_node:
		spawn_node.add_child(player_instance, true)
		print("Successfully spawned character %d for player %d" % [character_type, id])
		
		# Update player tracking
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
