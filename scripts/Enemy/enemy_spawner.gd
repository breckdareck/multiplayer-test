extends Node
class_name EnemySpawner

@export_group("Spawning Configuration")
@export var enemy_scene: PackedScene:
	set(value):
		if not value and is_inside_tree():
			printerr("Enemy scene cannot be empty.")
		enemy_scene = value

@export var spawn_locations: Array[Marker2D] = []
@export var spawn_container: Node

@export_group("Pooling")
@export var pool_size: int = 5
@export var respawn_delay: float = 3.0

var _pool: Array[Node] = []
var _is_initialized: bool = false
var _multiplayer_spawner: MultiplayerSpawner = null

func _ready() -> void:
	if not is_multiplayer_authority():
		return
	# We wait for the MultiplayerManager to signal that the server has started.
	# This requires MultiplayerManager to be an Autoload singleton as recommended.
	MultiplayerManager.server_has_started.connect(_on_server_created)

	# It's also possible this spawner is added to the scene tree *after* the
	# server has already started (e.g., loading a new level).
	# This check handles that case.
	# We must check that the active peer is NOT the default OfflineMultiplayerPeer.
	# The default peer makes `is_server()` return true even when offline.
	if multiplayer.multiplayer_peer != null and not multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		_on_server_created()

func _on_server_created() -> void:
	# Ensure this logic only runs once and only on the server.
	if _is_initialized or not is_multiplayer_authority():
		return
	
	_is_initialized = true

	# Defer pool creation to ensure the scene tree is fully ready.
	call_deferred("_setup_spawner")

func _setup_spawner() -> void:
	# Get reference to MultiplayerSpawner now that we are deferred and on the server
	_multiplayer_spawner = get_node_or_null("MultiplayerSpawner")
	if not _multiplayer_spawner:
		push_error("EnemySpawner: Could not find MultiplayerSpawner child node! Enemies won't replicate to clients.")
		return

	_create_pool()
	_initial_spawn()

func _create_pool() -> void:
	if not _validate_exports():
		return
	
	if not _multiplayer_spawner:
		push_error("EnemySpawner: Cannot create pool, MultiplayerSpawner not available!")
		return
	
	# Ensure the spawn function is set up on the MultiplayerSpawner
	if _multiplayer_spawner.spawn_function == null:
		#print("EnemySpawner: Setting up spawn function on MultiplayerSpawner")
		_multiplayer_spawner.spawn_function = _create_enemy_instance
	
	#print("EnemySpawner: Creating pool of %d enemies using MultiplayerSpawner" % pool_size)
	
	for i in range(pool_size):
		var enemy: EnemyBase = enemy_scene.instantiate() as EnemyBase
		
		if not enemy:
			printerr("EnemySpawner: Failed to spawn enemy %d through MultiplayerSpawner." % i)
			continue
		
		if not enemy.health_component:
			printerr("EnemySpawner: Enemy instance %d is missing a HealthComponent." % i)
			enemy.queue_free()
			continue

		# Pool-managed enemies must be respawnable; otherwise enemy_base.gd's
		# death path queue_free's them and the pool never refills.
		enemy.respawnable = true

		# CRITICAL: Set public_visibility = false on enemy synchronizers BEFORE adding to tree
		# This ensures the MultiplayerSpawner tracks it with correct visibility from the start
		_set_enemy_synchronizers_visibility(enemy, false)
		
		# Now add to tree - MultiplayerSpawner will track it with visibility already configured
		spawn_container.add_child(enemy, true)
		
		# Connect to the enemy's own signal, which fires after its death animation is complete.
		enemy.ready_for_pooling.connect(_on_enemy_ready_for_pooling.bind(enemy))
		_pool.append(enemy)
		
		# Deactivate the enemy until it's needed
		enemy.pool_deactivate()
	
	#print("EnemySpawner: Pool created with %d enemies" % _pool.size())
	
	# Update visibility for all players on this map
	# This ensures the enemies are visible to the right players
	await get_tree().process_frame
	_update_all_player_visibility()


func _initial_spawn() -> void:
	for enemy in _pool:
		# Spawn each enemy with a slight delay between them to avoid clumping.
		var timer: SceneTreeTimer = get_tree().create_timer(randf_range(0.1, 0.5))
		timer.timeout.connect(_spawn_enemy.bind(enemy))

func _on_enemy_ready_for_pooling(enemy: EnemyBase) -> void:
	# When the enemy signals it's done with its death sequence, deactivate it and schedule a respawn.
	enemy.pool_deactivate()
	
	var timer: SceneTreeTimer = get_tree().create_timer(respawn_delay)
	timer.timeout.connect(_spawn_enemy.bind(enemy))


func _spawn_enemy(enemy: EnemyBase) -> void:
	# Reset the enemy's state using its own method, then place it in the world.
	if not is_instance_valid(enemy):
		return

	if spawn_locations.is_empty():
		printerr("Spawner has no spawn locations assigned.")
		return

	# --- Reset state ---
	if enemy.has_method("pool_reset"):
		enemy.pool_reset()
	else:
		printerr("Enemy scene is missing a 'pool_reset()' method for pooling.")

	# --- Position the enemy ---
	var spawn_point = spawn_locations.pick_random()
	if enemy is Node2D and is_instance_valid(spawn_point):
		enemy.global_position = spawn_point.global_position
	
	# --- Update visibility for this enemy ---
	# When the enemy is activated, its synchronizer is re-enabled
	# We need to ensure visibility is up-to-date for all players on this map
	if multiplayer.is_server():
		await get_tree().process_frame
		_update_all_player_visibility()

func _validate_exports() -> bool:
	var is_valid = true
	if not enemy_scene:
		printerr("Enemy Spawner: 'Enemy Scene' is not set.")
		is_valid = false
	if spawn_locations.is_empty():
		printerr("Enemy Spawner: 'Spawn Locations' array is empty.")
		is_valid = false
	if not spawn_container:
		printerr("Enemy Spawner: 'Spawn Container' is not set.")
		is_valid = false
	return is_valid


func _create_enemy_instance() -> Node:
	"""Spawn function callback for MultiplayerSpawner"""
	if not enemy_scene:
		push_error("EnemySpawner: Cannot create enemy, enemy_scene not set!")
		return null
	
	var enemy = enemy_scene.instantiate()
	if not enemy:
		push_error("EnemySpawner: Failed to instantiate enemy scene!")
		return null
	
	return enemy


func _set_enemy_synchronizers_visibility(enemy: Node, visible: bool):
	"""Recursively sets public_visibility on all MultiplayerSynchronizers in an enemy."""
	if enemy is MultiplayerSynchronizer:
		enemy.public_visibility = visible
	
	for child in enemy.get_children():
		_set_enemy_synchronizers_visibility(child, visible)


func _update_all_player_visibility():
	"""Tell MapManager to update visibility for all players on this map."""
	if not multiplayer.is_server():
		return
	
	# Find which map this spawner belongs to
	var map_node = get_parent()
	while map_node and not map_node.name.begins_with("Map_"):
		map_node = map_node.get_parent()
	
	if not map_node:
		return
	
	var map_id = map_node.name.replace("Map_", "")
	var players_on_map = MapManager.get_real_players_on_map(map_id)

	for player_id in players_on_map:
		MapManager.update_visibility_for_player(player_id)
	
	#print("EnemySpawner: Updated visibility for %d players on map %s" % [players_on_map.size(), map_id])
