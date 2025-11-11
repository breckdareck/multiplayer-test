# map_manager.gd - AutoLoad singleton
extends Node

signal map_loaded(map_id: String)
signal map_unloaded(map_id: String)
signal player_spawned(player_id: int)

# Map configuration - add your map scenes here
const MAP_SCENES = {
	"game": "res://scenes/Levels/game.tscn",
}

const DEFAULT_MAP = "game"

# Server-side tracking
var active_maps: Dictionary = {} # {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} # {player_id: map_id}
var pending_spawn_requests: Dictionary = {} # {player_id: map_id} - waiting for client to ack map load

# Client-side
var current_map_id: String = ""
var current_map_instance: Node = null

# Track which missing node warnings we've already emitted to avoid log spam
var _warned_missing_paths: Dictionary = {}

# Map container reference
var maps_container: Node = null


func _ready():
	if multiplayer.is_server():
		_setup_maps_container()


func _setup_maps_container():
	"""Setup the Maps container node under MainMenu"""
	var main_menu = get_tree().current_scene
	if not main_menu:
		push_error("MapManager: Could not find MainMenu scene!")
		return
	
	# Create or get Maps container directly under MainMenu
	maps_container = main_menu.get_node_or_null("Maps")
	if not maps_container:
		maps_container = Node.new()
		maps_container.name = "Maps"
		main_menu.add_child(maps_container, true)
	
	print("MapManager: Maps container ready at: ", maps_container.get_path())


# === SERVER FUNCTIONS ===

func request_spawn_on_map(player_id: int, map_id: String):
	"""Called when a player wants to join a specific map"""
	if not multiplayer.is_server():
		return
	
	print("MapManager: Player %d requesting spawn on map '%s'" % [player_id, map_id])
	
	# Validate map exists
	if not map_id in MAP_SCENES:
		push_error("Invalid map_id: %s" % map_id)
		map_id = DEFAULT_MAP
	
	# Remove player from previous map if they were on one
	if player_id in player_current_maps:
		var old_map = player_current_maps[player_id]
		_remove_player_from_map(player_id, old_map)
	
	# Ensure map is loaded on server
	if not map_id in active_maps:
		_load_map_on_server(map_id)

	# Host case: spawn immediately on the server map
	if player_id == 1:
		# Host uses the server map directly
		current_map_instance = active_maps[map_id].scene_instance
		current_map_id = map_id
		# Track and spawn host immediately
		active_maps[map_id].player_ids.append(player_id)
		player_current_maps[player_id] = map_id
		_spawn_player_on_server_map(player_id, map_id)
		_notify_players_of_new_arrival(player_id, map_id)
		return

	# Remote client: request they load the map and record a pending spawn.
	# The client will call `client_map_loaded` once the map is ready, and the
	# server will complete the spawn process then. This avoids race conditions
	# where the server spawns or issues RPCs before the client has the map tree.
	pending_spawn_requests[player_id] = map_id
	load_map_on_client.rpc_id(player_id, map_id)


func _load_map_on_server(map_id: String):
	"""Instantiate a map on the server"""
	if map_id in active_maps:
		return
	
	print("MapManager: Loading map '%s' on server" % map_id)
	
	if not maps_container:
		_setup_maps_container()
	
	var map_scene = load(MAP_SCENES[map_id])
	var map_instance = map_scene.instantiate()
	map_instance.name = "Map_" + map_id
	
	# IMPORTANT: Clear broken NodePath properties before adding to tree
	# This prevents Godot validation errors when MultiplayerSynchronizers try to resolve stale paths
	_clear_broken_nodepaths(map_instance)
	
	maps_container.add_child(map_instance, true)
	
	active_maps[map_id] = {
		"scene_instance": map_instance,
		"player_ids": []
	}
	
	print("MapManager: Map '%s' loaded at path: %s" % [map_id, map_instance.get_path()])
	map_loaded.emit(map_id)


func _spawn_player_on_server_map(player_id: int, map_id: String):
	"""Spawn player character on server's map instance"""
	if not map_id in active_maps:
		push_error("MapManager: Cannot spawn player, map '%s' not loaded!" % map_id)
		return
	
	var map_instance = active_maps[map_id].scene_instance
	
	# Find spawn point - check common names
	var spawn_point = map_instance.get_node_or_null("PlayerSpawn")
	if not spawn_point:
		spawn_point = map_instance.get_node_or_null("SpawnPoint")
	if not spawn_point:
		spawn_point = map_instance.get_node_or_null("Spawn")
	
	var spawn_position = Vector2.ZERO
	if spawn_point:
		spawn_position = spawn_point.global_position
	else:
		push_warning("Map '%s' missing PlayerSpawn node! Using (0,0)" % map_id)
	
	var char_scene = load("res://scenes/Player/player.tscn")
	if not char_scene:
		push_error("MapManager: Failed to load player scene!")
		return
	
	var player_char = char_scene.instantiate()
	if not player_char:
		push_error("MapManager: Failed to instantiate player scene!")
		return
	
	player_char.name = str(player_id)
	player_char.position = spawn_position
	player_char.player_id = player_id
	
	# Add to Players node in map
	var players_node = map_instance.get_node_or_null("Players")
	if not players_node:
		players_node = Node2D.new()
		players_node.name = "Players"
		map_instance.add_child(players_node)
	
	players_node.add_child(player_char, true)
	print("MapManager: Spawned player %d on server map '%s' at %s" % [player_id, map_id, spawn_position])


func _notify_players_of_new_arrival(new_player_id: int, map_id: String):
	"""Tell existing players on map to spawn the new player"""
	if not map_id in active_maps:
		return
	
	var players_on_map = active_maps[map_id].player_ids
	
	for existing_player_id in players_on_map:
		if existing_player_id == new_player_id:
			continue

		# Tell existing player to spawn new player
		# NOTE: If the existing player is the host (server), they already have the
		# server-side instance in their map. Instructing the host client to spawn
		# another local visual would create a duplicate. We still instruct remote
		# clients to spawn the new player.
		if existing_player_id != 1:
			spawn_player_on_client.rpc_id(existing_player_id, new_player_id)

		# Tell new player to spawn existing player (new client needs to see others)
		spawn_player_on_client.rpc_id(new_player_id, existing_player_id)


func _remove_player_from_map(player_id: int, map_id: String):
	"""Remove player from a map"""
	if not map_id in active_maps:
		return
	
	print("MapManager: Removing player %d from map '%s'" % [player_id, map_id])
	
	# Remove from tracking
	active_maps[map_id].player_ids.erase(player_id)
	
	# Remove player node from server map
	var map_instance = active_maps[map_id].scene_instance
	var players_node = map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id)):
		players_node.get_node(str(player_id)).queue_free()
	
	# Tell other players to despawn this player
	for other_player_id in active_maps[map_id].player_ids:
		despawn_player_on_client.rpc_id(other_player_id, player_id)
	
	# Clear host's current_map_instance reference if they're leaving this map
	if player_id == 1 and current_map_instance == map_instance:
		current_map_instance = null
		current_map_id = ""
	
	# Unload map if empty
	if active_maps[map_id].player_ids.is_empty():
		_unload_map_on_server(map_id)


func _unload_map_on_server(map_id: String):
	"""Unload a map when no players are on it"""
	if not map_id in active_maps:
		return
	
	print("MapManager: Unloading empty map '%s'" % map_id)
	
	var map_instance = active_maps[map_id].scene_instance
	map_instance.queue_free()
	active_maps.erase(map_id)
	
	map_unloaded.emit(map_id)


func handle_player_disconnect(player_id: int):
	"""Called when a player disconnects"""
	if not multiplayer.is_server():
		return
	
	if not player_id in player_current_maps:
		return
	
	var map_id = player_current_maps[player_id]
	_remove_player_from_map(player_id, map_id)
	player_current_maps.erase(player_id)


func change_player_map(player_id: int, new_map_id: String):
	"""Move a player from their current map to a new one"""
	if not multiplayer.is_server():
		return
	
	print("MapManager: Moving player %d to map '%s'" % [player_id, new_map_id])
	
	# This will handle cleanup and respawn
	request_spawn_on_map(player_id, new_map_id)


# === CLIENT RPC FUNCTIONS ===

@rpc("authority", "call_local", "reliable")
func load_map_on_client(map_id: String):
	"""Remote client loads map with SAME structure as server for MultiplayerSynchronizer compatibility"""
	print("Client %d: Loading map '%s'" % [multiplayer.get_unique_id(), map_id])
	
	# Unload current map if exists
	if current_map_instance:
		current_map_instance.queue_free()
		current_map_instance = null
		await get_tree().process_frame
	
	var main_menu = get_tree().current_scene
	if not main_menu:
		push_error("Client %d: Could not find MainMenu!" % multiplayer.get_unique_id())
		return
	
	# Create Maps container if it doesn't exist (same as server)
	var client_maps_container = main_menu.get_node_or_null("Maps")
	if not client_maps_container:
		client_maps_container = Node.new()
		client_maps_container.name = "Maps"
		main_menu.add_child(client_maps_container, true)
	
	# Load map with same name as server: "Map_" + map_id
	var map_scene = load(MAP_SCENES[map_id])
	current_map_instance = map_scene.instantiate()
	current_map_instance.name = "Map_" + map_id  # SAME NAME AS SERVER
	current_map_id = map_id
	
	# IMPORTANT: Clear broken NodePath properties before adding to tree
	# This prevents Godot validation errors when MultiplayerSynchronizers try to resolve stale paths
	_clear_broken_nodepaths(current_map_instance)
	
	client_maps_container.add_child(current_map_instance, true)
	print("Client %d: Map '%s' loaded at: %s" % [multiplayer.get_unique_id(), map_id, current_map_instance.get_path()])
	print("  Path matches server: /root/MainMenu/Maps/Map_%s" % map_id)

	# Clear previous missing-path warnings so we can log new missing nodes for this map once
	_warned_missing_paths.clear()

	# Debug: print top-level children of the loaded map to confirm structure
	var child_names := []
	for c in current_map_instance.get_children():
		child_names.append(c.name)
	print("Client %d: Map children: %s" % [multiplayer.get_unique_id(), child_names])
	# Helpful quick-checks for common spawner names
	if not current_map_instance.get_node_or_null("GoblinSpawner"):
		print("Client %d: Warning - GoblinSpawner not found in Map_%s" % [multiplayer.get_unique_id(), map_id])
	if not current_map_instance.get_node_or_null("DmgNumberSpawner"):
		print("Client %d: Warning - DmgNumberSpawner not found in Map_%s" % [multiplayer.get_unique_id(), map_id])

	# Notify server that this client has finished loading the map so the
	# server can safely instruct the client to spawn its own player node.
	# Calls the server-side `client_map_loaded` RPC defined below.
	if multiplayer.get_unique_id() != 1:
		rpc_id(1, "client_map_loaded", map_id)


@rpc("authority", "call_local", "reliable")
func spawn_player_on_client(player_id: int):
	"""Client spawns another player on their current map"""
	if not current_map_instance:
		push_error("Client: Cannot spawn player %d, no map loaded!" % player_id)
		return
	
	print("Client: Spawning player %d" % player_id)
	
	# Find spawn point
	var spawn_point = current_map_instance.get_node_or_null("PlayerSpawn")
	if not spawn_point:
		spawn_point = current_map_instance.get_node_or_null("SpawnPoint")
	if not spawn_point:
		spawn_point = current_map_instance.get_node_or_null("Spawn")
	
	var spawn_position = Vector2.ZERO
	if spawn_point:
		spawn_position = spawn_point.global_position
	else:
		push_warning("Client: Map missing PlayerSpawn, using (0,0)")
	
	var char_scene = load("res://scenes/Player/player.tscn")
	if not char_scene:
		push_error("Client: Failed to load player scene!")
		return
	
	var player_char = char_scene.instantiate()
	if not player_char:
		push_error("Client: Failed to instantiate player scene!")
		return
	
	player_char.name = str(player_id)
	player_char.position = spawn_position
	player_char.player_id = player_id
	
	# Add to Players node
	var players_node = current_map_instance.get_node_or_null("Players")
	if not players_node:
		players_node = Node2D.new()
		players_node.name = "Players"
		current_map_instance.add_child(players_node)

	# Prevent duplicate spawns: if a node with this player_id already exists,
	# don't add another. This avoids the host creating a duplicate visual when
	# the server-side instance already exists on the host's map.
	if players_node.has_node(str(player_id)):
		print("Client: Player %d already exists in Players node, skipping spawn" % player_id)
		player_char.queue_free()
		return

	players_node.add_child(player_char, true)
	print("Client: Spawned player %d at %s" % [player_id, spawn_position])


@rpc("authority", "call_local", "reliable")
func despawn_player_on_client(player_id: int):
	"""Client removes a player from their view"""
	if not current_map_instance:
		return
	
	print("Client: Despawning player %d" % player_id)
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id)):
		players_node.get_node(str(player_id)).queue_free()


# === UTILITY FUNCTIONS ===

func get_current_visible_map() -> Node:
	"""Get the map the local player is viewing (works for host and clients)"""
	return current_map_instance


func find_node_in_current_map(path: String) -> Node:
	"""Find a node by path within the current map (works for host and clients)"""
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


func get_node_in_player_map(player_id: int, relative_path: String) -> Node:
	"""Get a node from a specific player's map (server only)"""
	if not multiplayer.is_server():
		return null
	
	var map_id = player_current_maps.get(player_id, "")
	if map_id.is_empty() or not map_id in active_maps:
		return null
	
	var map_instance = active_maps[map_id].scene_instance
	return map_instance.get_node_or_null(relative_path)


func get_spawn_position_for_map(map_id: String) -> Vector2:
	"""Get the spawn position for a given map"""
	var map_instance = null
	
	if multiplayer.is_server():
		if map_id in active_maps:
			map_instance = active_maps[map_id].scene_instance
	else:
		# Remote clients use their current_map_instance
		if current_map_instance and current_map_id == map_id:
			map_instance = current_map_instance
	
	if map_instance:
		var spawn = map_instance.get_node_or_null("PlayerSpawn")
		if not spawn:
			spawn = map_instance.get_node_or_null("SpawnPoint")
		if not spawn:
			spawn = map_instance.get_node_or_null("Spawn")
		if spawn:
			return spawn.global_position
	
	return Vector2.ZERO


func get_players_on_map(map_id: String) -> Array:
	"""Get list of player IDs on a specific map (server only)"""
	if not multiplayer.is_server():
		return []
	
	if map_id in active_maps:
		return active_maps[map_id].player_ids.duplicate()
	
	return []


func get_player_map(player_id: int) -> String:
	"""Get which map a player is currently on (server only)"""
	if not multiplayer.is_server():
		return ""
	
	return player_current_maps.get(player_id, "")


@rpc("any_peer", "call_local", "reliable")
func client_map_loaded(map_id: String) -> void:
	"""Called by a client after it has loaded a map locally.
	Server will then instruct that client to spawn its own player instance.
	"""
	if not multiplayer.is_server():
		return

	var peer_id: int = multiplayer.get_remote_sender_id()
	print("MapManager: Received map-loaded ACK from %d for map '%s'" % [peer_id, map_id])

	# Validate that this peer is expected on this map
	var expected_map = player_current_maps.get(peer_id, "")
	if expected_map != map_id:
		# If there's a mismatch, log and ignore — the server's request_spawn_on_map
		# flow should have set player_current_maps earlier.
		push_warning("MapManager: Peer %d reported map '%s' but server expects '%s'" % [peer_id, map_id, expected_map])
		# Still, if the server knows about this map, attempt to spawn client visuals.

	# Complete pending spawn request if we have one recorded
	var requested_map = pending_spawn_requests.get(peer_id, "")
	if requested_map == "":
		# No pending request - nothing to do here aside from the warning above
		return

	# Validate expected map; if mismatch warn but continue if map matches server-side
	if requested_map != map_id:
		push_warning("MapManager: Pending map for peer %d was '%s' but ACKed '%s'" % [peer_id, requested_map, map_id])

	# Ensure the map is loaded on the server
	if not map_id in active_maps:
		_load_map_on_server(map_id)

	# Finalize spawn on server-side
	active_maps[map_id].player_ids.append(peer_id)
	player_current_maps[peer_id] = map_id
	_spawn_player_on_server_map(peer_id, map_id)

	# Tell existing players on this map about new player (remote clients only)
	_notify_players_of_new_arrival(peer_id, map_id)

	# Tell the client to spawn its own player now that the map is ready
	spawn_player_on_client.rpc_id(peer_id, peer_id)

	# Clear pending request
	pending_spawn_requests.erase(peer_id)

	# Emit a signal so other systems (e.g., PlayerManager) can continue
	# initialization once server-side spawning is complete.
	player_spawned.emit(peer_id)


func _clear_broken_nodepaths(node: Node) -> void:
	"""Recursively clear broken NodePath properties to prevent validation errors
	
	When a scene is loaded into a new part of the tree, NodePath export variables
	that were set via the editor may contain stale absolute paths. This causes
	Godot's MultiplayerSynchronizer to fail validation.
	
	This function walks the scene tree and clears NodePath properties that
	reference nodes that don't exist, preventing cascading "Node not found" errors.
	"""
	if not node:
		return
	
	# Debug: notify we're clearing paths for this node
	if node.name.begins_with("Map_"):
		print("MapManager: Starting to clear broken NodePaths in tree rooted at '%s'" % node.name)
	
	# Get all properties of this node
	var script = node.get_script()
	if script:
		var properties = script.get_property_list()
		for prop in properties:
			# Check if this is a NodePath property
			if prop.type == TYPE_NODE_PATH:
				var prop_name = prop.name
				var current_value = node.get(prop_name)
				
				# If the property has a value, try to resolve it
				if current_value and current_value != NodePath():
					# Try to resolve the path - if it fails, the property will have a stale value
					var target_node = node.get_node_or_null(current_value)
					if not target_node:
						# Path is broken - clear it
						print("MapManager: Clearing broken NodePath '%s' from %s" % [prop_name, node.name])
						node.set(prop_name, NodePath())
	
	# Recursively process children
	for child in node.get_children():
		_clear_broken_nodepaths(child)
