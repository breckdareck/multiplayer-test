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
	"game3": "res://scenes/Levels/game3.tscn",
}

const DEFAULT_MAP = "game"

# Server-side tracking
var active_maps: Dictionary = {} ## {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} ## {player_id: map_id}

# Client-side state
var current_map_id: String = ""
var current_map_instance: Node = null
var my_player_node: Node = null
var _warned_missing_paths: Dictionary = {}
var _synchronizer_cache: Dictionary = {} ## {node_instance_id: Array[MultiplayerSynchronizer]}

var _loading_overlay_scene = preload("res://scenes/UI/loading_overlay.tscn")
var _loading_overlay: CanvasLayer = null

func _get_loading_overlay() -> CanvasLayer:
	if not _loading_overlay or not is_instance_valid(_loading_overlay):
		_loading_overlay = _loading_overlay_scene.instantiate()
		get_tree().root.add_child(_loading_overlay)
	return _loading_overlay


func _ready():
	# Defer server-side setup until the server is confirmed to be running.
	MultiplayerManager.server_has_started.connect(_on_server_started)


func _on_scene_changed():
	# This function is no longer needed since MapSpawner is persistent
	pass


func _exit_tree():
	if MultiplayerManager.server_has_started.is_connected(_on_server_started):
		MultiplayerManager.server_has_started.disconnect(_on_server_started)


func _on_server_started():
	# Server started - ready to spawn maps manually
	pass


# === SERVER LOGIC ===

func request_map_change(player_id: int, target_map_id: String, target_spawn_point_name: String = ""):
	"""Requests a player to be moved to a new map."""
	if not multiplayer.is_server(): return

	#print("MapManager: Player %d requesting map change to '%s' at spawn '%s'" % [player_id, target_map_id, target_spawn_point_name])

	if not target_map_id in MAP_SCENES:
		push_warning("MapManager: Invalid target_map_id '%s' for player %d. Using default map." % [target_map_id, player_id])
		target_map_id = DEFAULT_MAP

	# Track whether this is a map change (not the initial join)
	var is_map_change := player_id in player_current_maps

	# Remove player from current map
	if is_map_change:
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
		# Play per-map BGM for the host player
		if map_instance is MapBase and not map_instance.bgm_path.is_empty():
			AudioManager.play_song(map_instance.bgm_path)
		_finalize_player_spawn(player_id, target_map_id, target_spawn_point_name)
		# On map changes (not initial join), emit player_spawned so
		# PlayerManager._on_player_spawned re-initializes the host player
		# with fresh data from the backend.
		if is_map_change:
			player_spawned.emit(player_id)
		return

	# Bots have no client — skip the RPC and finalize directly on server.
	if BotManager.is_bot(player_id):
		_finalize_player_spawn(player_id, target_map_id, target_spawn_point_name)
		player_spawned.emit(player_id)
		return

	client_set_current_map.rpc_id(player_id, target_map_id, target_spawn_point_name)
	
func _load_map_on_server(map_id: String):
	"""Server-only: Manually instantiate map scene and add to scene tree"""
	if not multiplayer.is_server(): return
	if map_id in active_maps: return
																											
	#print("MapManager: Manually spawning map '%s' on server" % map_id)
	
	# Load and instantiate map scene
	var map_path = MAP_SCENES.get(map_id)
	if not map_path:
		push_error("MapManager: Invalid map_id '%s'" % map_id)
		return
	
	var map_scene = load(map_path)
	if not map_scene:
		push_error("MapManager: Failed to load map scene at '%s'" % map_path)
		return
		
	var map_instance = map_scene.instantiate()
	if not is_instance_valid(map_instance):
		push_error("MapManager: Failed to instantiate map '%s'" % map_id)
		return
	
	map_instance.name = "Map_" + map_id
	
	# Create Maps container if needed
	var maps_container = get_tree().root.get_node_or_null("Maps")
	if not maps_container:
		maps_container = Node.new()
		maps_container.name = "Maps"
		get_tree().root.add_child(maps_container)
		#print("MapManager: Created Maps container at /root/Maps")
	
	# Add to server's scene tree
	maps_container.add_child(map_instance)
																											
	active_maps[map_id] = {"scene_instance": map_instance, "player_ids": []}
	map_loaded.emit(map_id)
	
	#print("MapManager: Server spawned map '%s' at path %s" % [map_id, map_instance.get_path()])
	
	# CRITICAL: Set public_visibility to false for all synchronizers in this map
	# This prevents them from trying to sync to clients who haven't loaded the map yet
	_set_synchronizers_public_visibility(map_instance, false)
	#print("MapManager: Set public_visibility=false for all synchronizers in map '%s'" % map_id)
	
	# Update visibility for all players when new map is added
	_update_visibility_for_all_players()


func _finalize_player_spawn(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Creates the player character on the server via a PlayerSpawner."""
	if not multiplayer.is_server() or not map_id in active_maps: return

	#print("MapManager: Finalizing spawn for player %d on map %s at spawn '%s'" % [player_id, map_id, spawn_point_name])
	active_maps[map_id].player_ids.append(player_id)
	
	# Sync EXISTING players to the new joiner
	# The new joiner needs to know about everyone else already on the map
	var map_instance = active_maps[map_id].scene_instance
	var _joiner_is_bot = BotManager.is_bot(player_id)
	for existing_id in active_maps[map_id].player_ids:
		if existing_id == player_id: continue # Skip self (handled in _spawn_player_on_server_map)

		var existing_node = get_player_map_node(existing_id)
		if existing_node:
			# Tell the new player to spawn the existing player (skip for bots)
			if not _joiner_is_bot:
				client_spawn_player.rpc_id(player_id, existing_id, existing_node.global_position)
			# Also update visibility for the existing player
			update_visibility_for_player(existing_id)

	_spawn_player_on_server_map(player_id, map_id, spawn_point_name)

	# Sync existing players' buff visuals (e.g. Shadow Partner) to the new joiner (skip for bots)
	if not _joiner_is_bot:
		await get_tree().process_frame
		for existing_id in active_maps[map_id].player_ids:
			if existing_id == player_id: continue
			var existing_player = map_instance.get_node_or_null("Players/" + str(existing_id))
			if is_instance_valid(existing_player) and existing_player.buff_component:
				existing_player.buff_component.sync_all_buffs_to_client(player_id)
	
	# After the player is spawned and on the map, update visibilities.
	update_visibility_for_player(player_id)
	
	# Sync existing dropped items to the new player (skip for bots)
	if not _joiner_is_bot:
		var drop_handler = map_instance.get_node_or_null("GlobalDropHandler")
		if drop_handler and drop_handler.has_method("sync_items_to_player"):
			drop_handler.sync_items_to_player(player_id)
		else:
			push_warning("MapManager: Could not find GlobalDropHandler to sync items for player %d on map %s" % [player_id, map_id])


func _spawn_player_on_server_map(player_id: int, map_id: String, spawn_point_name: String = ""):
	"""Spawns a player character manually and syncs to clients."""
	var map_instance = active_maps[map_id].scene_instance
	var players_node = map_instance.get_node_or_null("Players")
	if not players_node:
		push_error("Map '%s' is missing a Players node!" % map_id)
		return

	# 1. Instantiate on Server
	var player_scene = load("res://scenes/Player/player.tscn")
	var player_char = player_scene.instantiate()
	player_char.name = str(player_id)
	player_char.player_id = player_id
	
	# Set position
	player_char.global_position = get_spawn_position_for_map(map_id, spawn_point_name)
	
	# Add to tree
	players_node.add_child(player_char)

	# Invalidate map's synchronizer cache since new player subtree was added
	invalidate_synchronizer_cache(map_instance)

	# CRITICAL: Set public_visibility=false for all player synchronizers
	# Visibility will be controlled via visibility filters and _update_visibility_for_player()
	_set_synchronizers_public_visibility(player_char, false)
	#print("MapManager: Set public_visibility=false for player %d synchronizers" % player_id)
	
	#print("MapManager: Manually spawned player %d on map '%s' at %s" % [player_id, map_id, player_char.global_position])
	
	# 2. Notify ALL clients on this map to spawn this player
	# We iterate through all players currently on this map
	var players_on_map = active_maps[map_id].player_ids
	for peer_id in players_on_map:
		if BotManager.is_bot(peer_id):
			continue
		# RPC each peer to spawn this new player
		client_spawn_player.rpc_id(peer_id, player_id, player_char.global_position)

	# Explicitly tell the client which node is theirs (for PlayerManager init)
	if not BotManager.is_bot(player_id):
		client_identify_player.rpc_id(player_id, player_char.get_path())


func _remove_player_from_map(player_id: int, map_id: String):
	if not map_id in active_maps: return
	
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance): return
	
	#print("MapManager: Removing player %d from map '%s'" % [player_id, map_id])
	
	# CRITICAL: Hide this map from the player BEFORE removing them
	# This prevents "Node not found" errors during map transitions
	if player_id in active_maps[map_id].player_ids:
		_set_visibility_for_node(map_instance, player_id, false)
		#print("MapManager: Hid map '%s' from player %d before removal" % [map_id, player_id])
	
	if player_id in active_maps[map_id].player_ids:
		active_maps[map_id].player_ids.erase(player_id)
	
	var player_node = map_instance.get_node_or_null("Players/" + str(player_id))
	if is_instance_valid(player_node):
		# Invalidate caches before freeing (player cache + map cache since subtree changes)
		invalidate_synchronizer_cache(player_node)
		invalidate_synchronizer_cache(map_instance)
		# Cleanup player components before freeing to prevent lingering network messages
		if player_node.has_method("cleanup_before_removal"):
			player_node.cleanup_before_removal()
		player_node.queue_free()
		
	# Notify clients on this map to remove this player (skip bot peers)
	for peer_id in active_maps[map_id].player_ids:
		if BotManager.is_bot(peer_id):
			continue
		client_despawn_player.rpc_id(peer_id, player_id)
	
	if player_id == 1 and current_map_instance == map_instance:
		current_map_instance = null
		current_map_id = ""
	
	if active_maps[map_id].player_ids.is_empty():
		_unload_map_on_server(map_id)


func _unload_map_on_server(map_id: String):
	if not map_id in active_maps: return
	
	#print("MapManager: Despawning empty map '%s'" % map_id)
	var map_instance = active_maps[map_id].scene_instance
	if is_instance_valid(map_instance):
		invalidate_synchronizer_cache(map_instance)
		map_instance.queue_free()

	active_maps.erase(map_id)
	map_unloaded.emit(map_id)


func handle_player_disconnect(player_id: int):
	if not multiplayer.is_server() or not player_id in player_current_maps: return
	
	var map_id = player_current_maps[player_id]
	_remove_player_from_map(player_id, map_id)
	player_current_maps.erase(player_id)


func reset_client_state():
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server(): return
	
	#print("MapManager: Resetting client-side map state.")
	current_map_id = ""
	current_map_instance = null
	my_player_node = null
	_warned_missing_paths.clear()


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
	if BotManager.is_bot(peer_id): return
	var synchronizers = _get_cached_synchronizers(node)
	for s in synchronizers:
		if not is_instance_valid(s): continue
		s.set_visibility_for(peer_id, visible)
		s.update_visibility(peer_id)


func _set_synchronizers_public_visibility(node: Node, visible: bool):
	"""Sets the default public visibility for all synchronizers in a node."""
	if not is_instance_valid(node): return
	var synchronizers = _get_cached_synchronizers(node)
	for s in synchronizers:
		if not is_instance_valid(s): continue
		s.public_visibility = visible


func _get_cached_synchronizers(node: Node) -> Array[MultiplayerSynchronizer]:
	"""Returns synchronizers for a node, using cache when available."""
	var id = node.get_instance_id()
	if _synchronizer_cache.has(id):
		return _synchronizer_cache[id]
	var syncs = _get_all_synchronizers_in_node(node)
	_synchronizer_cache[id] = syncs
	return syncs


func invalidate_synchronizer_cache(node: Node) -> void:
	"""Invalidates cached synchronizers for a node. Call when subtree structure changes."""
	_synchronizer_cache.erase(node.get_instance_id())


func update_visibility_for_player(player_id: int):
	"""
	Updates visibility for a given player against all other players and enemies.
	This should be called when a player changes maps.
	"""
	if not multiplayer.is_server(): return

	var player_node = PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node): return

	var player_map = player_current_maps.get(player_id, "")
	if player_map.is_empty(): return

	var _this_is_bot = BotManager.is_bot(player_id)

	# 1. Update visibility between this player and all OTHER PLAYERS
	for other_id in player_current_maps.keys():
		if other_id == player_id: continue
		var other_node = PlayerManager.get_player_node(other_id)
		if not is_instance_valid(other_node): continue

		var other_map = player_current_maps.get(other_id, "")
		var is_visible = (player_map == other_map)

		# Update other player's view of me (skip if other is a bot)
		if not BotManager.is_bot(other_id):
			_set_visibility_for_node(player_node, other_id, is_visible)
		# Update my view of other player (skip if I'm a bot)
		if not _this_is_bot:
			_set_visibility_for_node(other_node, player_id, is_visible)

	# Bots don't need map visibility updates — they have no client to sync to.
	if _this_is_bot:
		return

	# 2. Update this player's visibility of the ENTIRE MAP
	# This includes Enemies, Items, Projectiles, etc.
	for map_id in active_maps.keys():
		var map_instance = active_maps[map_id].scene_instance
		if not is_instance_valid(map_instance): continue

		var is_visible = (player_map == map_id)

		# Set visibility for all synchronizers in this map for this player
		_set_visibility_for_node(map_instance, player_id, is_visible)


func _update_visibility_for_all_players():
	"""Updates visibility for ALL active players. Useful when a new map is added."""
	if not multiplayer.is_server(): return
	
	for player_id in player_current_maps.keys():
		update_visibility_for_player(player_id)


# === CLIENT LOGIC ===


@rpc("authority", "call_local", "reliable")
func client_set_current_map(map_id: String, spawn_point_name: String = ""):
	"""
	Server tells client which map to load.
	Client manually instantiates ONLY this map.
	"""
	if not multiplayer.is_server():
		_get_loading_overlay().show_loading(map_id)

	#print("Client %d: Server requesting map '%s'" % [multiplayer.get_unique_id(), map_id])

	# Unload previous map if exists
	if is_instance_valid(current_map_instance):
		#print("Client: Unloading previous map '%s'" % current_map_id)
		# CRITICAL: Cleanup client's own player first before freeing map
		# This prevents InputSynchronizer errors during transition
		var my_id = multiplayer.get_unique_id()
		var players_node = current_map_instance.get_node_or_null("Players")
		if players_node:
			var my_player = players_node.get_node_or_null(str(my_id))
			if is_instance_valid(my_player) and my_player.has_method("cleanup_before_removal"):
				my_player.cleanup_before_removal()
				#print("Client: Cleaned up own player before map transition")
		
		current_map_instance.queue_free()
		current_map_instance = null
	
	# Load and instantiate new map
	var map_path = MAP_SCENES.get(map_id)
	if not map_path:
		push_error("Client: Invalid map_id '%s'" % map_id)
		return
	
	var map_scene = load(map_path)
	if not map_scene:
		push_error("Client: Failed to load map scene at '%s'" % map_path)
		return
		
	var map_instance = map_scene.instantiate()
	if not is_instance_valid(map_instance):
		push_error("Client: Failed to instantiate map '%s'" % map_id)
		return
		
	map_instance.name = "Map_" + map_id
	
	# Create Maps container if needed (same structure as server)
	var maps_container = get_tree().root.get_node_or_null("Maps")
	if not maps_container:
		maps_container = Node.new()
		maps_container.name = "Maps"
		get_tree().root.add_child(maps_container)
		#print("Client: Created Maps container at /root/Maps")
	
	# Add to client's scene tree under Maps (matching server structure)
	maps_container.add_child(map_instance)
	
	# On client, map synchronizers should start hidden and rely on server visibility updates
	# if not multiplayer.is_server():
	# 	_set_synchronizers_public_visibility(map_instance, false)
	# 	print("Client: Set public_visibility=false for map synchronizers")
	
	# Track locally
	current_map_instance = map_instance
	current_map_id = map_id
	_warned_missing_paths.clear()

	# Play per-map BGM if the map defines one
	if map_instance is MapBase and not map_instance.bgm_path.is_empty():
		AudioManager.play_song(map_instance.bgm_path)

	#print("Client %d: Loaded map '%s' at path %s" % [multiplayer.get_unique_id(), map_id, map_instance.get_path()])

	# ACK to server
	rpc_id(1, "client_map_loaded", map_id, spawn_point_name)


@rpc("authority", "call_local", "reliable")
func client_identify_player(player_node_path: String):
	"""Called by the server to tell the client which spawned player node is theirs."""
	#print("Client: Server identified my player at path: %s" % player_node_path)
	
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
	if _loading_overlay and is_instance_valid(_loading_overlay):
		_loading_overlay.hide_loading()
	#print("Client: Found my player node. Notifying server.")
	rpc_id(1, "client_player_spawned", current_map_id)


@rpc("authority", "call_local", "reliable")
func client_spawn_player(new_player_id: int, spawn_pos: Vector2):
	"""Client: Instantiate a player node manually."""
	if not is_instance_valid(current_map_instance):
		return
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if not players_node:
		push_error("Client: Current map missing Players node!")
		return
	
	if players_node.has_node(str(new_player_id)):
		# Already exists
		if multiplayer.is_server():
			# Server is authority, do not reset position of existing players
			return
			
		var p = players_node.get_node(str(new_player_id))
		p.global_position = spawn_pos
		return
		
	var player_scene = load("res://scenes/Player/player.tscn")
	var player_node = player_scene.instantiate()
	player_node.name = str(new_player_id)
	player_node.player_id = new_player_id
	player_node.global_position = spawn_pos
	
	players_node.add_child(player_node)
	
	# Set public_visibility=false for player synchronizers (client-side)
	# if not multiplayer.is_server():
	# 	_set_synchronizers_public_visibility(player_node, false)
	
	#print("Client: Manually spawned player %d at %s" % [new_player_id, spawn_pos])


@rpc("authority", "call_local", "reliable")
func client_despawn_player(player_id_to_remove: int):
	"""Client: Remove a player node."""
	if not is_instance_valid(current_map_instance): return
	
	var players_node = current_map_instance.get_node_or_null("Players")
	if players_node and players_node.has_node(str(player_id_to_remove)):
		var node = players_node.get_node(str(player_id_to_remove))
		node.queue_free()
		#print("Client: Despawned player %d" % player_id_to_remove)


# === SERVER-SIDE ACKS FROM CLIENTS ===

@rpc("any_peer", "call_local", "reliable")
func client_map_loaded(map_id: String, spawn_point_name: String = ""):
	"""ACK from client that they have a reference to the spawned map node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	#print("MapManager: Received map-loaded ACK from %d for map '%s'" % [peer_id, map_id])

	var expected_map = player_current_maps.get(peer_id, "")
	if expected_map != map_id:
		push_warning("MapManager: Peer %d reported map '%s' but server expects '%s'" % [peer_id, map_id, expected_map])
		return

	_finalize_player_spawn(peer_id, map_id, spawn_point_name)


@rpc("any_peer", "call_local", "reliable")
func client_player_spawned(_map_id: String) -> void:
	"""ACK from client that they have identified their own player character node."""
	if not multiplayer.is_server(): return

	var peer_id: int = multiplayer.get_remote_sender_id()
	#print("MapManager: Received player-spawned ACK from %d. Initializing." % peer_id)
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


func get_real_players_on_map(map_id: String) -> Array:
	var all_players := get_players_on_map(map_id)
	return all_players.filter(func(id): return not BotManager.is_bot(id))

func get_player_map(player_id: int) -> String:
	if not multiplayer.is_server(): return ""
	return player_current_maps.get(player_id, "")
	
func get_player_map_node(player_id: int) -> Node:
	if not multiplayer.is_server(): return null
	
	var map_id = get_player_map(player_id)
	if map_id and active_maps.has(map_id):
		return active_maps[map_id].scene_instance
	return null

func _find_all_nodes_of_type(root: Node, type_name: String) -> Array:
	var nodes = []
	if root.is_class(type_name):
		nodes.append(root)
	
	for child in root.get_children():
		nodes.append_array(_find_all_nodes_of_type(child, type_name))
		
	return nodes
