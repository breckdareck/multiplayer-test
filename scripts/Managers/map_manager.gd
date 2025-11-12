# map_manager.gd - AutoLoad singleton
# REFACTORED to use a MultiplayerSpawner for maps.
extends Node

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)
signal player_spawned(player_id: int)

# Map configuration - add your map scenes here
const MAP_SCENES = {
	"game": "res://scenes/Levels/game.tscn",
}

const DEFAULT_MAP = "game"

# This spawner is responsible for creating map instances as networked objects.
# It should be placed in the main scene so it exists on server and all clients.
# Its spawn_path should point to a container node (e.g., /root/MainMenu/Maps).
var map_spawner: MultiplayerSpawner

# Server-side tracking
var active_maps: Dictionary = {} # {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} # {player_id: map_id}

# Client-side
var current_map_id: String = ""
var current_map_instance: Node = null

# Track which missing node warnings we've already emitted to avoid log spam
var _warned_missing_paths: Dictionary = {}


func _ready():
	# Wait a frame to ensure the main scene tree is fully established
	await get_tree().process_frame
	map_spawner = get_node_or_null("/root/MainMenu/MapSpawner")
	if not map_spawner:
		push_error("MapManager: Could not find /root/MainMenu/MapSpawner! Map replication will fail.")
		return
	
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


# === SERVER FUNCTIONS ===

func request_spawn_on_map(player_id: int, map_id: String):
	"""Ochestrates getting a player onto a specific map."""
	if not multiplayer.is_server():
		return
	
	print("MapManager: Player %d requesting spawn on map '%s'" % [player_id, map_id])
	
	if not map_id in MAP_SCENES:
		push_error("Invalid map_id: %s" % map_id)
		map_id = DEFAULT_MAP
	
	# Clean up player from any previous map
	if player_id in player_current_maps:
		var old_map = player_current_maps[player_id]
		_remove_player_from_map(player_id, old_map)
	
	# Set the player's destination map
	player_current_maps[player_id] = map_id
	
	# Ensure the map is spawned on the server (which replicates to clients)
	if not map_id in active_maps:
		_load_map_on_server(map_id)
	
	var map_instance = active_maps.get(map_id, {}).get("scene_instance")
	if not is_instance_valid(map_instance):
		push_error("Map instance for '%s' is invalid after load!" % map_id)
		return

	# Host case: The map instance is local. Set it and finalize spawn immediately.
	if player_id == 1:
		current_map_instance = map_instance
		current_map_id = map_id
		_finalize_player_spawn(player_id, map_id)
		return

	# Remote client: Tell them the path to their map. The map is already being
	# spawned on their machine by the MultiplayerSpawner. They just need to find it.
	client_set_current_map.rpc_id(player_id, map_instance.get_path())


func _load_map_on_server(map_id: String):
	"""Spawns a map scene using the MultiplayerSpawner."""
	if map_id in active_maps:
		return
	
	print("MapManager: Spawning map '%s' via MultiplayerSpawner" % map_id)
	
	if not map_spawner:
		push_error("MapManager: Map Spawner not found, cannot spawn map!")
		return
		
	var map_instance = map_spawner.spawn({"map_id": map_id})
	
	if not is_instance_valid(map_instance):
		push_error("Failed to spawn map '%s' via MultiplayerSpawner!" % map_id)
		return

	active_maps[map_id] = {
		"scene_instance": map_instance,
		"player_ids": []
	}
	
	print("MapManager: Map '%s' spawned at path: %s" % [map_id, map_instance.get_path()])
	map_loaded.emit(map_id)


func _finalize_player_spawn(player_id: int, map_id: String):
	"""
	Once a player has acknowledged their map is ready, this function
	creates their character on the server and tells the client to do the same.
	"""
	if not multiplayer.is_server() or not map_id in active_maps:
		return

	print("MapManager: Finalizing spawn for player %d on map %s" % [player_id, map_id])

	active_maps[map_id].player_ids.append(player_id)
	_spawn_player_on_server_map(player_id, map_id)
	_notify_players_of_new_arrival(player_id, map_id)
	spawn_player_on_client.rpc_id(player_id, player_id)


func _spawn_player_on_server_map(player_id: int, map_id: String):
	"""Spawn player character on server's map instance"""
	if not map_id in active_maps:
		push_error("MapManager: Cannot spawn player, map '%s' not loaded!" % map_id)
		return
	
	var map_instance = active_maps[map_id].scene_instance
	var spawn_position = get_spawn_position_for_map(map_id)
	
	var char_scene = load("res://scenes/Player/player.tscn")
	var player_char = char_scene.instantiate()
	
	player_char.name = str(player_id)
	player_char.position = spawn_position
	player_char.player_id = player_id
	
	var players_node = map_instance.get_node_or_null("Players")
	if not players_node:
		players_node = Node2D.new()
		players_node.name = "Players"
		map_instance.add_child(players_node)
	
	players_node.add_child(player_char, true)
	print("MapManager: Spawned player %d on server map '%s' at %s" % [player_id, map_id, spawn_position])


func _notify_players_of_new_arrival(new_player_id: int, map_id: String):
	"""Tell existing players on map to spawn the new player's character"""
	if not map_id in active_maps: return
	
	var players_on_map = active_maps[map_id].player_ids
	
	for existing_player_id in players_on_map:
		if existing_player_id == new_player_id: continue
		if existing_player_id != 1:
			spawn_player_on_client.rpc_id(existing_player_id, new_player_id)
		spawn_player_on_client.rpc_id(new_player_id, existing_player_id)


func _remove_player_from_map(player_id: int, map_id: String):
	if not map_id in active_maps: return
	
	print("MapManager: Removing player %d from map '%s'" % [player_id, map_id])
	
	if player_id in active_maps[map_id].player_ids:
		active_maps[map_id].player_ids.erase(player_id)
	
	var map_instance = active_maps[map_id].scene_instance
	var players_node = map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id)):
		players_node.get_node(str(player_id)).queue_free()
	
	for other_player_id in active_maps[map_id].player_ids:
		despawn_player_on_client.rpc_id(other_player_id, player_id)
	
	if player_id == 1 and current_map_instance == map_instance:
		current_map_instance = null
		current_map_id = ""
	
	if active_maps[map_id].player_ids.is_empty():
		_unload_map_on_server(map_id)


func _unload_map_on_server(map_id: String):
	"""Despawns a map scene using the MultiplayerSpawner."""
	if not map_id in active_maps: return
	
	print("MapManager: Despawning empty map '%s'" % map_id)
	
	var map_instance = active_maps[map_id].scene_instance
	if is_instance_valid(map_instance):
		# The MultiplayerSpawner manages the node's lifecycle.
		# We just need to tell it to despawn it.
		map_spawner.despawn(map_instance)

	active_maps.erase(map_id)
	map_unloaded.emit(map_id)


func handle_player_disconnect(player_id: int):
	if not multiplayer.is_server() or not player_id in player_current_maps:
		return
	
	var map_id = player_current_maps[player_id]
	_remove_player_from_map(player_id, map_id)
	player_current_maps.erase(player_id)


# === CLIENT RPC FUNCTIONS ===

@rpc("authority", "call_local", "reliable")
func client_set_current_map(map_path: String):
	"""Called by the server to tell the client which map node to use."""
	print("Client %d: Server designated map path: %s" % [multiplayer.get_unique_id(), map_path])
	
	# The map is spawned by a MultiplayerSpawner, it might take a frame to appear.
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

	# Now that we have the map, tell the server we're ready for the next step.
	rpc_id(1, "client_map_loaded", current_map_id)


@rpc("authority", "call_local", "reliable")
func spawn_player_on_client(player_id: int):
	"""Client spawns a player character on their current map"""
	if not current_map_instance:
		push_error("Client: Cannot spawn player %d, no map loaded!" % player_id)
		return
	
	if get_tree().get_root().has_node("MainMenu/Maps/Map_game/Players/" + str(player_id)):
		print("Client: Player %d already exists, skipping spawn" % player_id)
		return

	var spawn_position = get_spawn_position_for_map(current_map_id)
	var char_scene = load("res://scenes/Player/player.tscn")
	var player_char = char_scene.instantiate()
	
	player_char.name = str(player_id)
	player_char.position = spawn_position
	player_char.player_id = player_id
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if not players_node:
		players_node = Node2D.new()
		players_node.name = "Players"
		current_map_instance.add_child(players_node)

	players_node.add_child(player_char, true)
	print("Client: Spawned player %d at %s" % [player_id, spawn_position])

	if player_id == multiplayer.get_unique_id():
		print("Client: Finished spawning my own character. Notifying server.")
		rpc_id(1, "client_player_spawned", current_map_id)


@rpc("authority", "call_local", "reliable")
func despawn_player_on_client(player_id: int):
	if not current_map_instance: return
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id)):
		players_node.get_node(str(player_id)).queue_free()


# === SERVER-SIDE ACKS FROM CLIENTS ===

@rpc("any_peer", "call_local", "reliable")
func client_map_loaded(map_id: String) -> void:
	"""ACK from client that they have a reference to the spawned map node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	print("MapManager: Received map-loaded ACK from %d for map '%s'" % [peer_id, map_id])

	var expected_map = player_current_maps.get(peer_id, "")
	if expected_map != map_id:
		push_warning("MapManager: Peer %d reported map '%s' but server expects '%s'" % [peer_id, map_id, expected_map])
		return

	_finalize_player_spawn(peer_id, map_id)


@rpc("any_peer", "call_local", "reliable")
func client_player_spawned(map_id: String) -> void:
	"""ACK from client that they have spawned their own player character node."""
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

func get_spawn_position_for_map(map_id: String) -> Vector2:
	var map_instance = null
	if multiplayer.is_server():
		if map_id in active_maps:
			map_instance = active_maps[map_id].scene_instance
	else:
		if current_map_instance and current_map_id == map_id:
			map_instance = current_map_instance
	
	if map_instance:
		var spawn = map_instance.get_node_or_null("PlayerSpawn")
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
