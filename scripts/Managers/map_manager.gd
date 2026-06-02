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
	"game4": "res://scenes/Levels/game4.tscn",
	"town": "res://scenes/Levels/town.tscn",
}

const DEFAULT_MAP = "town"

# Server-side tracking
var active_maps: Dictionary = {} ## {map_id: {scene_instance, player_ids: []}}
var player_current_maps: Dictionary = {} ## {player_id: map_id}

## Map adjacency graph {map_id: Array[String]} derived from portal target_map_id
## values. Built once, server-side; used by bots to route across maps.
var map_connections: Dictionary = {}

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
	# Build the portal connectivity graph once, before bots start pathfinding.
	_build_map_connections()


# === MAP CONTAINER + SUBVIEWPORT WRAPPING ===
# Each map lives inside its own SubViewport with a fresh World2D, so physics,
# navigation, canvas (lights), and audio listeners are fully isolated between
# maps. Authors keep editing map scenes at (0,0); the wrap is added at runtime.
# Both server and client mirror the same wrapping so absolute node paths line up
# for MultiplayerSynchronizer replication and RPC routing.

func _ensure_maps_container() -> SubViewportContainer:
	var existing := get_tree().root.get_node_or_null("Maps")
	if existing is SubViewportContainer:
		return existing
	if existing != null:
		push_warning("MapManager: /root/Maps exists but is not a SubViewportContainer; replacing.")
		get_tree().root.remove_child(existing)
		existing.queue_free()
	var container := SubViewportContainer.new()
	container.name = "Maps"
	container.anchor_right = 1.0
	container.anchor_bottom = 1.0
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_PASS
	# Keep the per-viewport render texture sampled as nearest-neighbor when
	# blitted to the window, so pixel-art doesn't go blurry through the wrap.
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	get_tree().root.add_child(container)
	return container


func _wrap_in_subviewport(map_instance: Node, map_id: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "Map_%s_VP" % map_id
	viewport.world_2d = World2D.new()
	viewport.disable_3d = true
	viewport.handle_input_locally = false
	viewport.audio_listener_enable_2d = true
	viewport.physics_object_picking = true
	# SubViewport does NOT inherit the project's rendering/textures/canvas_textures/
	# default_texture_filter setting — it defaults to LINEAR. Force nearest so the
	# pixel-art textures rendered inside the viewport stay crisp.
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	# Render transparent when the map's content is hidden (visible=false on the
	# map root) so SubViewportContainer doesn't stack one map's render on top of
	# another on the host's screen. See _set_local_map_visible.
	viewport.transparent_bg = true
	# Default: GUI input off. _set_local_map_visible re-enables it when the
	# host moves to this map. SubViewportContainer dispatches input to EVERY
	# child SubViewport, so hidden maps would otherwise steal drag-drop hit-
	# tests from the active map. Clients only have one map loaded so this is
	# a no-op for them; matters for the host (server) which keeps every map
	# loaded for the other players.
	viewport.gui_disable_input = true
	viewport.add_child(map_instance)
	return viewport


## Show/hide a map LOCALLY on this peer. Bot/non-local maps stay loaded for
## physics, but their SubViewport content is hidden so the SubViewportContainer
## renders only the local peer's current map. Affects only the local peer's
## tree — remote clients have their own map instances and are unaffected.
##
## ALSO gates GUI input on the SubViewport. SubViewportContainer dispatches
## input to EVERY child SubViewport regardless of which one is visually on
## top, so without `gui_disable_input` the hidden maps' GUI tree silently
## competes for drag-drop hit-tests and steals drops from the host's active
## inventory the moment the host is on a map by themselves.
func _set_local_map_visible(map_id: String, vis: bool) -> void:
	if not active_maps.has(map_id):
		return
	var map_instance = active_maps[map_id].scene_instance
	if not is_instance_valid(map_instance):
		return
	map_instance.visible = vis
	var viewport: Node = map_instance.get_parent()
	if viewport is SubViewport:
		(viewport as SubViewport).gui_disable_input = not vis


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
	# Snapshot the host's previous map BEFORE _remove_player_from_map runs —
	# that call clears current_map_id when the host's own instance is removed,
	# which would otherwise hide the wrong (now-empty) value below and leave
	# the old map's SubViewport composited on top of the new one.
	var old_map_id: String = player_current_maps.get(player_id, "")

	# Remove player from current map
	if is_map_change:
		# Snapshot live state before the old body is freed so the respawn can
		# restore it in-memory — no save-backend round-trip, no stale-data race.
		var old_node := PlayerManager.get_player_node(player_id)
		if is_instance_valid(old_node) and old_node.has_method("get_save_data"):
			PlayerManager.set_carried_state(player_id, old_node.get_save_data("all"))
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
		# Hide the previously-active map locally so its SubViewport stops
		# compositing on top of the host's view; show the new one. Use the
		# pre-removal old_map_id — current_map_id was wiped above.
		if not old_map_id.is_empty() and old_map_id != target_map_id:
			_set_local_map_visible(old_map_id, false)
		_set_local_map_visible(target_map_id, true)

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

	# Wrap in a SubViewport (isolated World2D) so physics/nav don't leak across
	# maps that share the (0,0) authoring origin. See helpers above.
	var maps_container := _ensure_maps_container()
	var viewport := _wrap_in_subviewport(map_instance, map_id)
	maps_container.add_child(viewport)
	# Default to hidden locally — the host toggles it visible only when they
	# travel to this map. Bots/other peers keep simulating regardless; this
	# only suppresses local rendering on the host's screen.
	map_instance.visible = false

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

		# The actual player/bot character node (get_player_map_node returns the
		# map, not the character — its components must be read off this node).
		var existing_node = PlayerManager.get_player_node(existing_id)
		if is_instance_valid(existing_node):
			# Tell the new player to spawn the existing player (skip for bots)
			if not _joiner_is_bot:
				client_spawn_player.rpc_id(player_id, existing_id, existing_node.global_position, _player_username(existing_id))
				# A bot's sprite isn't streamed via the node-addressed sprite
				# RPC, so send the joiner the bot's class/level appearance.
				if BotManager.is_bot(existing_id) and is_instance_valid(existing_node.class_component) \
						and is_instance_valid(existing_node.level_component):
					var bot_class: int = existing_node.class_component.current_class
					var bot_level: int = existing_node.level_component.level
					if player_id == 1:
						# The host is the server — client_apply_appearance is a
						# call_remote RPC and can't target self; apply directly.
						existing_node.apply_appearance(bot_class, bot_level)
					else:
						client_apply_appearance.rpc_id(player_id, existing_id, bot_class, bot_level)
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
		client_spawn_player.rpc_id(peer_id, player_id, player_char.global_position, _player_username(player_id))

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
		# Free the SubViewport wrapper, not just the map, so the wrap doesn't
		# leak. Falls back to freeing the map directly if a wrap is somehow
		# missing (defensive — shouldn't happen with the current load path).
		var viewport: Node = map_instance.get_parent()
		if viewport is SubViewport:
			viewport.queue_free()
		else:
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

		# Free the SubViewport wrapper (created in the wrap below) so it doesn't
		# leak. Falls back to freeing the map directly if a wrap is missing.
		var old_viewport: Node = current_map_instance.get_parent()
		if old_viewport is SubViewport:
			old_viewport.queue_free()
		else:
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

	# Mirror the server's wrap so the absolute node path of every map-child
	# (Players/<id>, Enemies, spawners, ...) matches between server and client.
	# Synchronizer replication and RPC routing rely on this parity.
	var maps_container := _ensure_maps_container()
	var viewport := _wrap_in_subviewport(map_instance, map_id)
	maps_container.add_child(viewport)
	# Remote clients only ever have one map loaded; it's always the local
	# peer's current map, so render it and re-enable GUI input on its
	# SubViewport (which defaults to disabled — see _wrap_in_subviewport).
	map_instance.visible = true
	viewport.gui_disable_input = false
	
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
func client_spawn_player(new_player_id: int, spawn_pos: Vector2, username: String = ""):
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
		if not username.is_empty():
			p.set_username(username)
		return

	var player_scene = load("res://scenes/Player/player.tscn")
	var player_node = player_scene.instantiate()
	player_node.name = str(new_player_id)
	player_node.player_id = new_player_id
	player_node.global_position = spawn_pos

	players_node.add_child(player_node)

	# Apply the player's name so the floating label and right-click context
	# menu show it — covers bots, whose username is otherwise never sent to
	# clients (bot state is server-authoritative).
	if not username.is_empty():
		player_node.set_username(username)
	
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


## [Server -> Client] Spawns a projectile visual on a client. Routed through
## MapManager (an autoload that always resolves on every peer) so it works for
## any caster — including bots, whose component nodes a client may lack during
## a map transition. Clients simulate the projectile's movement locally; the
## server stays authoritative for hit detection.
@rpc("authority", "call_remote", "reliable")
func spawn_projectile_visual(proj_name: String, scene_path: String, start_pos: Vector2, direction: Vector2, speed: float, target_path: NodePath) -> void:
	if multiplayer.is_server():
		return
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var container = map_node.get_node_or_null("Projectiles")
	if not is_instance_valid(container):
		container = Node.new()
		container.name = "Projectiles"
		map_node.add_child(container)
	if container.has_node(proj_name):
		return  # already spawned — defensive against a duplicate RPC
	var scene: PackedScene = load(scene_path)
	if not scene:
		return
	var projectile = scene.instantiate()
	projectile.name = proj_name
	var target: Node = get_node_or_null(target_path) if not target_path.is_empty() else null
	projectile.initialize(null, target, null, null, speed, direction)
	container.add_child(projectile)
	projectile.global_position = start_pos


## [Server -> Client] Removes a projectile visual early — the server's
## authoritative copy hit something before its lifetime expired. Lifetime
## expiry is handled independently on each peer by the projectile's own timer.
@rpc("authority", "call_remote", "reliable")
func despawn_projectile_visual(proj_name: String) -> void:
	if multiplayer.is_server():
		return
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var container = map_node.get_node_or_null("Projectiles")
	if not is_instance_valid(container):
		return
	var projectile = container.get_node_or_null(proj_name)
	if is_instance_valid(projectile):
		projectile.queue_free()


const _LightningArcVfx = preload("res://scripts/VFX/lightning_arc.gd")

## [Server] Broadcasts a chain-lightning arc VFX to every real client viewing the
## event's map (and draws it on the host if the host is on that map). Cosmetic
## only — the chain DAMAGE is already applied server-side by StaffElementComponent.
## `points` are GLOBAL positions: the struck target first, then each chained enemy
## in order, so each peer draws one bolt threading through the shocked enemies.
func broadcast_lightning_arc(map_id: String, points: PackedVector2Array) -> void:
	if not multiplayer.is_server():
		return
	if points.size() < 2:
		return
	# The host is also a client — draw locally only if it is viewing this map
	# (the call_remote RPC below never runs on the server).
	if get_player_map(1) == map_id:
		_spawn_lightning_arc_visual(points)
	for peer_id in get_real_players_on_map(map_id):
		if peer_id != 1:
			client_show_lightning_arc.rpc_id(peer_id, points)


## [Server -> Client] Draws the chain-lightning arc on this peer. Routed through
## MapManager (an autoload that always resolves) rather than any per-entity node,
## mirroring bot_ability_used / spawn_projectile_visual.
@rpc("authority", "call_remote", "reliable")
func client_show_lightning_arc(points: PackedVector2Array) -> void:
	if multiplayer.is_server():
		return
	_spawn_lightning_arc_visual(points)


## Spawns the transient bolt node under the visible map (so it renders in the
## right SubViewport) and lets it self-free. No-op on a headless peer / when no
## map is visible.
func _spawn_lightning_arc_visual(points: PackedVector2Array) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var arc = _LightningArcVfx.new()
	map_node.add_child(arc)
	arc.setup(points)


## [Server] Broadcasts a cosmetic ground-zone visual to every real CLIENT
## viewing the event's map. The authoritative GroundZone (with damage logic) is
## already added under the map's scene_instance by `GroundZone.spawn_server`,
## so the host (which is also a client) needs no extra mirror — its own zone
## renders for free. We only RPC to remote clients, where a parallel visual
## mirror is spawned via _spawn_ground_zone_visual.
##
## CIRCLE backward-compat path. New ground-rect callers should use
## broadcast_ground_zone_shaped.
func broadcast_ground_zone(map_id: String, pos: Vector2, radius: float, duration: float, color: Color) -> void:
	broadcast_ground_zone_shaped(map_id, pos, 0, radius, Vector2.ZERO, duration, color)


## [Server] Shape-aware ground-zone visual broadcast. shape_type matches the
## GroundZone.Shape enum (0=CIRCLE, 1=RECT). For CIRCLE, only `radius` is read;
## for RECT, `rect_size` is the full width × height (centered on `pos`).
func broadcast_ground_zone_shaped(map_id: String, pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	if not multiplayer.is_server():
		return
	for peer_id in get_real_players_on_map(map_id):
		if peer_id != 1:
			client_show_ground_zone_shaped.rpc_id(peer_id, pos, shape_type, radius, rect_size, duration, color)


## [Server -> Client] Spawns a visual-only GroundZone on this peer. Routed
## through MapManager (an autoload that always resolves) rather than addressing
## any per-entity node. call_remote because the server already owns the
## authoritative damage path — it must NOT also run this visual spawn.
##
## Backward-compat: old call sites that targeted client_show_ground_zone with
## the 4-arg signature still get routed to a CIRCLE visual.
@rpc("authority", "call_remote", "reliable")
func client_show_ground_zone(pos: Vector2, radius: float, duration: float, color: Color) -> void:
	if multiplayer.is_server():
		return
	_spawn_ground_zone_visual(pos, 0, radius, Vector2.ZERO, duration, color)


## [Server -> Client] Shape-aware visual spawn — the canonical version.
@rpc("authority", "call_remote", "reliable")
func client_show_ground_zone_shaped(pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	if multiplayer.is_server():
		return
	_spawn_ground_zone_visual(pos, shape_type, radius, rect_size, duration, color)


## Spawns a damage-less GroundZone under the visible map so the shape renders
## in the right SubViewport. damage_per_tick stays 0 + applier stays null on
## the visual mirror, so _do_tick early-returns and no gameplay state is
## touched. The zone self-frees via its own duration timer.
##
## NOTE: preload rather than class_name reference — MapManager is an autoload
## and its parse order may run before ground_zone.gd registers its class_name,
## causing a "GroundZone not declared" parse error. The preload locks the
## script load explicitly.
const _GroundZoneScript = preload("res://scripts/Gameplay/ground_zone.gd")

func _spawn_ground_zone_visual(pos: Vector2, shape_type: int, radius: float, rect_size: Vector2, duration: float, color: Color) -> void:
	var map_node = get_current_visible_map()
	if not is_instance_valid(map_node):
		return
	var zone = _GroundZoneScript.new()
	zone.global_position = pos
	zone.shape_type = shape_type
	zone.radius = radius
	zone.rect_size = rect_size
	zone.duration = duration
	zone.visual_color = color
	map_node.add_child(zone)


## [Server -> Client] Plays a bot's ability-cast visual. Routed through
## MapManager (an autoload that always resolves) rather than the bot's
## AbilityComponent node, which a client may lack during a map transition.
@rpc("authority", "call_remote", "reliable")
func bot_ability_used(caster_id: int, ability_id: String, level: int) -> void:
	if multiplayer.is_server():
		return
	var caster = PlayerManager.get_player_node(caster_id)
	if not is_instance_valid(caster) or not is_instance_valid(caster.ability_component):
		return  # bot not present on this client — skip the visual, no error
	caster.ability_component.play_ability_visual(ability_id, level)


## [Server] Sends a bot's class/level to every real client on its map so they
## render the correct sprite. Bot appearance isn't streamed via the
## node-addressed sprite RPC, so this delivers it on demand.
func broadcast_player_appearance(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var node = PlayerManager.get_player_node(player_id)
	if not is_instance_valid(node) or not is_instance_valid(node.class_component) \
			or not is_instance_valid(node.level_component):
		return
	var class_type: int = node.class_component.current_class
	var level: int = node.level_component.level
	# Apply on the host directly — client_apply_appearance early-returns on the
	# server, but the host is also a client and must render the bot.
	node.apply_appearance(class_type, level)
	for peer_id in get_real_players_on_map(get_player_map(player_id)):
		if peer_id != 1:
			client_apply_appearance.rpc_id(peer_id, player_id, class_type, level)


## [Server -> Client] Applies a player/bot's sprite frames for its class/level.
## Routed through MapManager so it always resolves even mid map-transition.
@rpc("authority", "call_remote", "reliable")
func client_apply_appearance(player_id: int, class_type: int, level: int) -> void:
	if multiplayer.is_server():
		return
	var node = PlayerManager.get_player_node(player_id)
	if is_instance_valid(node):
		node.apply_appearance(class_type, level)


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


# === MAP CONNECTIVITY ===

## Builds the map adjacency graph by scanning each map scene's portal nodes for
## their target_map_id. Done once, server-side, before bots start pathfinding.
func _build_map_connections() -> void:
	map_connections.clear()
	for map_id in MAP_SCENES:
		var connections: Array[String] = []
		var scene: PackedScene = load(MAP_SCENES[map_id])
		if is_instance_valid(scene):
			# Instantiate (without entering the tree, so no _ready runs) and
			# walk the live nodes — property overrides on instanced portals are
			# only reliably readable off a real node, not the PackedScene state.
			var root := scene.instantiate()
			_collect_portal_targets(root, map_id, connections)
			root.free()
		map_connections[map_id] = connections
	print("MapManager: Map connectivity graph: %s" % map_connections)


## Recursively collects portal destination map ids under `node` into `out`.
func _collect_portal_targets(node: Node, map_id: String, out: Array) -> void:
	if "target_map_id" in node:
		var dest = node.target_map_id
		if dest is String and not dest.is_empty() and dest != map_id and dest not in out:
			out.append(dest)
	for child in node.get_children():
		_collect_portal_targets(child, map_id, out)


## Maps directly reachable from `map_id` via its portals.
func get_map_connections(map_id: String) -> Array:
	if map_connections.is_empty():
		_build_map_connections()
	return map_connections.get(map_id, [])


## Returns the next map to travel to along the shortest portal route from
## `from_map` to `to_map`, or "" if they are the same or no route exists. The
## returned map is always directly connected to `from_map`.
func get_next_map_toward(from_map: String, to_map: String) -> String:
	if from_map == to_map or to_map.is_empty():
		return ""
	if map_connections.is_empty():
		_build_map_connections()
	var visited := {from_map: true}
	var queue: Array = []  # entries: [current_map, first_hop_from_origin]
	for neighbor in map_connections.get(from_map, []):
		visited[neighbor] = true
		queue.append([neighbor, neighbor])
	while not queue.is_empty():
		var entry: Array = queue.pop_front()
		if entry[0] == to_map:
			return entry[1]
		for neighbor in map_connections.get(entry[0], []):
			if neighbor in visited:
				continue
			visited[neighbor] = true
			queue.append([neighbor, entry[1]])
	return ""


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


## Username for a player/bot id, used to pass names to clients on spawn.
func _player_username(id: int) -> String:
	var info: Dictionary = PlayerManager.get_player_info(id)
	return info.get("username", "")
	
func get_player_map_node(player_id: int) -> Node:
	if not multiplayer.is_server(): return null
	
	var map_id = get_player_map(player_id)
	if map_id and active_maps.has(map_id):
		return active_maps[map_id].scene_instance
	return null
