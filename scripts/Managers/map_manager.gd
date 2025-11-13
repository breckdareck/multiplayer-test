# map_manager.gd - AutoLoad singleton
# FINAL REFACTOR - Uses MultiplayerSpawners for both maps and players.
extends Node

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)
signal player_spawned(player_id: int)

# Map configuration - add your map scenes here
const MAP_SCENES = {
	"game": "res://scenes/Levels/game.tscn",
	"game2": "res://scenes/Levels/game2.tscn",
}

const DEFAULT_MAP = "game"

# Spawner for creating the map instances themselves as networked objects.
var map_spawner: MultiplayerSpawner

# Server-side tracking
var active_maps: Dictionary = {} # {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} # {player_id: map_id}

# Client-side state
var current_map_id: String = ""
var current_map_instance: Node = null
var my_player_node: Node = null
var _warned_missing_paths: Dictionary = {}
var _node_to_map_cache: Dictionary = {}


func _ready():
	# Wait a frame to ensure the main scene tree is fully established
	await get_tree().process_frame
	map_spawner = get_node_or_null("/root/MainMenu/MapSpawner")
	if not map_spawner:
		push_error("MapManager: Could not find /root/MainMenu/MapSpawner! Map replication will fail.")
		return
	if multiplayer.is_server():
		map_spawner.spawn_function = _spawn_map_instance
	else:
		# On clients, whenever a map is spawned, we need to re-evaluate visibility.
		map_spawner.spawned.connect(_on_map_spawned_on_client)
	# Defer server-side setup until the server is confirmed to be running.
	MultiplayerManager.server_has_started.connect(_on_server_started)


func _exit_tree():
	if MultiplayerManager.server_has_started.is_connected(_on_server_started):
		MultiplayerManager.server_has_started.disconnect(_on_server_started)

	if not multiplayer.is_server() and is_instance_valid(map_spawner):
		if map_spawner.spawned.is_connected(_on_map_spawned_on_client):
			map_spawner.spawned.disconnect(_on_map_spawned_on_client)


func _on_server_started():
	if multiplayer.is_server():
		map_spawner.spawn_function = _spawn_map_instance


func _spawn_map_instance(data: Dictionary) -> Node:
	"""Custom spawn function for the map_spawner. Instantiates a map scene."""
	var map_id = data.get("map_id", DEFAULT_MAP)
	if not map_id in MAP_SCENES:
		push_error("Invalid map_id in spawn data: %s" % map_id)
		map_id = DEFAULT_MAP
	
	var map_scene = load(MAP_SCENES[map_id])
	var map_instance = map_scene.instantiate()
	map_instance.name = "Map_" + map_id
	
	print("MapSpawner: Custom spawn function created map: %s" % map_instance.name)
	return map_instance


# === SERVER LOGIC ===

func request_map_change(player_id: int, target_map_id: String, target_spawn_point_name: String = ""):
	"""Requests a player to be moved to a new map."""
	if not multiplayer.is_server(): return

	print("MapManager: Player %d requesting map change to '%s' at spawn '%s'" % [player_id, target_map_id, target_spawn_point_name])

	if not target_map_id in MAP_SCENES:
		push_warning("MapManager: Invalid target_map_id '%s' for player %d. Using default map." % [target_map_id, player_id])
		target_map_id = DEFAULT_MAP

	# Remove player from current map
	if player_id in player_current_maps:
		_remove_player_from_map(player_id, player_current_maps[player_id])

	player_current_maps[player_id] = target_map_id

	# Load target map if not active
	if not target_map_id in active_maps:
		_load_map_on_server(target_map_id)

	var map_instance = active_maps.get(target_map_id, {}).get("scene_instance")
	if not is_instance_valid(map_instance):
		push_error("Map instance for '%s' is invalid after load for player %d!" % [target_map_id, player_id])
		return

	if player_id == 1:
		current_map_instance = map_instance
		current_map_id = target_map_id
		_finalize_player_spawn(player_id, target_map_id, target_spawn_point_name)
		return

	client_set_current_map.rpc_id(player_id, map_instance.get_path(), target_spawn_point_name)
	
	
func _load_map_on_server(map_id: String):                                                                                                           
	if map_id in active_maps: return                                                                        
																											
	print("MapManager: Spawning map '%s' via MultiplayerSpawner" % map_id)                                  
	if not map_spawner:                                                                                     
		push_error("MapManager: Map Spawner not found, cannot spawn map!")                                  
		return                                                                                              
																											
	var map_instance = map_spawner.spawn({"map_id": map_id})                                                
	if not is_instance_valid(map_instance):                                                                 
		push_error("Failed to spawn map '%s' via MultiplayerSpawner!" % map_id)                             
		return                                                                                              
																											
	active_maps[map_id] = { "scene_instance": map_instance, "player_ids": [] }                              
	map_loaded.emit(map_id) 


func _finalize_player_spawn(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Creates the player character on the server via a PlayerSpawner."""
	if not multiplayer.is_server() or not map_id in active_maps: return

	print("MapManager: Finalizing spawn for player %d on map %s at spawn '%s'" % [player_id, map_id, spawn_point_name])
	active_maps[map_id].player_ids.append(player_id)
	_spawn_player_on_server_map(player_id, map_id, spawn_point_name)
	
	# After the player is spawned and on the map, update visibilities.
	_update_visibility_for_player(player_id)


func _spawn_player_on_server_map(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Spawns a player character using the map's own PlayerSpawner."""
	var map_instance = active_maps[map_id].scene_instance
	var player_spawner = map_instance.get_node_or_null("PlayerSpawner")
	if not player_spawner:
		push_error("Map '%s' is missing a PlayerSpawner node!" % map_id)
		return

	# Pass the player's ID and spawn point to the spawn function so the node is created with the correct name.
	var player_char = player_spawner.spawn({"id": player_id, "spawn_point_name": spawn_point_name})
	if not is_instance_valid(player_char):
		push_error("Failed to spawn player via PlayerSpawner on map '%s'" % map_id)
		return

	# Set all synchronizers to be private by default.
	#_set_synchronizers_public_visibility(player_char, false)

	# Configure the authoritative instance. The name is set inside the spawn function.
	player_char.position = get_spawn_position_for_map(map_id, spawn_point_name)
	
	print("MapManager: Spawned player %d via PlayerSpawner on map '%s' at spawn '%s'" % [player_id, map_id, spawn_point_name])
	
	# Explicitly tell the client which node is theirs.
	client_identify_player.rpc_id(player_id, player_char.get_path())


func _remove_player_from_map(player_id: int, map_id: String):
	if not map_id in active_maps: return
	
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance): return
	
	print("MapManager: Removing player %d from map '%s'" % [player_id, map_id])
	
	if player_id in active_maps[map_id].player_ids:
		active_maps[map_id].player_ids.erase(player_id)
	
	var player_node = map_instance.get_node_or_null("Players/" + str(player_id))
	if is_instance_valid(player_node):
		player_node.queue_free()
	
	if player_id == 1 and current_map_instance == map_instance:
		current_map_instance = null
		current_map_id = ""
	
	if active_maps[map_id].player_ids.is_empty():
		_unload_map_on_server(map_id)


func _unload_map_on_server(map_id: String):
	if not map_id in active_maps: return
	
	print("MapManager: Despawning empty map '%s'" % map_id)
	var map_instance = active_maps[map_id].scene_instance
	if is_instance_valid(map_instance):
		map_instance.queue_free()

	active_maps.erase(map_id)
	map_unloaded.emit(map_id)


func handle_player_disconnect(player_id: int):
	if not multiplayer.is_server() or not player_id in player_current_maps: return
	
	var map_id = player_current_maps[player_id]
	_remove_player_from_map(player_id, map_id)
	player_current_maps.erase(player_id)


# === VISIBILITY LOGIC ===

func _get_all_synchronizers_in_node(node: Node) -> Array[MultiplayerSynchronizer]:
	"""Recursively finds all MultiplayerSynchronizer nodes under a given node."""
	var syncs: Array[MultiplayerSynchronizer] = []
	if node is MultiplayerSynchronizer:
		syncs.append(node)
	
	for child in node.get_children():
		syncs.append_array(_get_all_synchronizers_in_node(child))
		
	return syncs


func _set_visibility_for_node(node: Node, peer_id: int, visible: bool):
	"""Sets the visibility for all synchronizers within a node for a specific peer."""
	if not is_instance_valid(node): return
	var synchronizers = _get_all_synchronizers_in_node(node)
	for s in synchronizers:
		s.set_visibility_for(peer_id, visible)


func _set_synchronizers_public_visibility(node: Node, visible: bool):
	"""Sets the default public visibility for all synchronizers in a node."""
	if not is_instance_valid(node): return
	var synchronizers = _get_all_synchronizers_in_node(node)
	for s in synchronizers:
		s.public_visibility = visible


func _update_visibility_for_player(player_id: int):
	"""
	Updates visibility for a given player against all other players and enemies.
	This should be called when a player changes maps.
	"""
	if not multiplayer.is_server(): return

	var player_node = PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node): return

	var player_map = player_current_maps.get(player_id, "")
	if player_map.is_empty(): return

	# 1. Update visibility between this player and all OTHER PLAYERS
	for other_id in player_current_maps.keys():
		if other_id == player_id: continue
		var other_node = PlayerManager.get_player_node(other_id)
		if not is_instance_valid(other_node): continue
		
		var other_map = player_current_maps.get(other_id, "")
		var is_visible = (player_map == other_map)
		
		# Update other player's view of me
		_set_visibility_for_node(player_node, other_id, is_visible)
		# Update my view of other player
		_set_visibility_for_node(other_node, player_id, is_visible)

	# 2. Update this player's visibility of all ENEMIES
	for map_id in active_maps.keys():
		var map_instance = active_maps[map_id].scene_instance
		if not is_instance_valid(map_instance): continue
		
		var is_visible = (player_map == map_id)
		
		# Assuming enemies are in the "Enemies" group and parented to the map.
		# A more robust way would be to have a dedicated enemy container node.
		for enemy in get_tree().get_nodes_in_group("Enemies"):
			if enemy.get_owner() == map_instance:
				_set_visibility_for_node(enemy, player_id, is_visible)


# === CLIENT LOGIC ===

func _update_client_map_visibility():
	# This should only run on clients.
	if multiplayer.is_server(): return

	var spawner = map_spawner
	if not is_instance_valid(spawner):
		return

	var spawn_root = spawner.get_node_or_null(spawner.spawn_path)
	if not is_instance_valid(spawn_root):
		push_warning("MapManager: Map spawner root path not found.")
		return

	for child in spawn_root.get_children():
		# We identify maps by checking if they are in the "map_base" group.
		if child.is_in_group("map_base"):
			if child == current_map_instance:
				child.visible = true
				child.process_mode = Node.PROCESS_MODE_INHERIT
			else:
				child.visible = false
				child.process_mode = Node.PROCESS_MODE_DISABLED
				child.queue_free()

func _on_map_spawned_on_client(_node: Node):
	# A new node was spawned by the map spawner. It might be a map.
	# We run the visibility check to hide it if it's not our current map.
	_update_client_map_visibility()


@rpc("authority", "call_local", "reliable")
func client_set_current_map(map_path: String, spawn_point_name: String = ""):
	"""Called by the server to tell the client which map node to use."""
	print("Client %d: Server designated map path: %s" % [multiplayer.get_unique_id(), map_path])
	
	var map_node = get_node_or_null(map_path)
	var wait_count = 0
	while not is_instance_valid(map_node) and wait_count < 10:
		await get_tree().process_frame
		map_node = get_node_or_null(map_path)
		wait_count += 1

	if not is_instance_valid(map_node):
		push_error("Client %d: Timed out waiting for map node at path: %s" % [multiplayer.get_unique_id(), map_path])
		return

	print("Client %d: Found designated map instance." % multiplayer.get_unique_id())
	
	current_map_instance = map_node
	current_map_id = map_node.name.replace("Map_", "")
	_warned_missing_paths.clear()

	# Manually update which map is visible and processing.
	_update_client_map_visibility()

	# Now that we have the map, tell the server we're ready for the next step.
	rpc_id(1, "client_map_loaded", current_map_id, spawn_point_name)


@rpc("authority", "call_local", "reliable")
func client_identify_player(player_node_path: String):
	"""Called by the server to tell the client which spawned player node is theirs."""
	print("Client: Server identified my player at path: %s" % player_node_path)
	
	var node = get_node_or_null(player_node_path)
	var wait_count = 0
	while not is_instance_valid(node) and wait_count < 10:
		await get_tree().process_frame
		node = get_node_or_null(player_node_path)
		wait_count += 1
		
	if not is_instance_valid(node):
		push_error("Client: Timed out waiting for my player node at path: %s" % player_node_path)
		return
		
	my_player_node = node
	print("Client: Found my player node. Notifying server.")
	rpc_id(1, "client_player_spawned", current_map_id)


# === SERVER-SIDE ACKS FROM CLIENTS ===

@rpc("any_peer", "call_local", "reliable")
func client_map_loaded(map_id: String, spawn_point_name: String = ""):
	"""ACK from client that they have a reference to the spawned map node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	print("MapManager: Received map-loaded ACK from %d for map '%s'" % [peer_id, map_id])

	var expected_map = player_current_maps.get(peer_id, "")
	if expected_map != map_id:
		push_warning("MapManager: Peer %d reported map '%s' but server expects '%s'" % [peer_id, map_id, expected_map])
		return

	_finalize_player_spawn(peer_id, map_id, spawn_point_name)


@rpc("any_peer", "call_local", "reliable")
func client_player_spawned(map_id: String) -> void:
	"""ACK from client that they have identified their own player character node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	print("MapManager: Received player-spawned ACK from %d. Initializing." % peer_id)
	player_spawned.emit(peer_id)


# === UTILITY FUNCTIONS ===

func get_current_visible_map() -> Node:
	return current_map_instance

func find_node_in_current_map(path: String) -> Node:
	if not current_map_instance:
		if not _warned_missing_paths.has(path):
			_warned_missing_paths[path] = true
			push_warning("No current map loaded - cannot find '%s'" % path)
		return null

	var node = current_map_instance.get_node_or_null(path)
	if not node:
		if not _warned_missing_paths.has(path):
			_warned_missing_paths[path] = true
			push_warning("MapManager: Node '%s' not found in current map" % path)
		return null
	return node

func get_spawn_position_for_map(map_id: String, spawn_point_name: String = "") -> Vector2:
	var map_instance = null
	if multiplayer.is_server():
		if map_id in active_maps:
			map_instance = active_maps[map_id].scene_instance
	else:
		if current_map_instance and current_map_id == map_id:
			map_instance = current_map_instance
	
	if map_instance:
		var spawn_node_name = spawn_point_name
		if spawn_node_name.is_empty():
			# Fallback to default spawn points if no specific name is provided
			spawn_node_name = "PlayerSpawn"
		
		var spawn = map_instance.get_node_or_null(spawn_node_name)
		if not spawn: spawn = map_instance.get_node_or_null("SpawnPoint")
		if not spawn: spawn = map_instance.get_node_or_null("Spawn")
		if spawn: return spawn.global_position
	
	return Vector2.ZERO

func get_players_on_map(map_id: String) -> Array:
	if not multiplayer.is_server(): return []
	if map_id in active_maps: return active_maps[map_id].player_ids.duplicate()
	return []

func get_player_map(player_id: int) -> String:
	if not multiplayer.is_server(): return ""
	return player_current_maps.get(player_id, "")
