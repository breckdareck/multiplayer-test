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
	# Get reference to MultiplayerSpawner for spawning enemies
	_multiplayer_spawner = get_node_or_null("MultiplayerSpawner")
	if not _multiplayer_spawner:
		push_error("EnemySpawner: Could not find MultiplayerSpawner child node! Enemies won't replicate to clients.")
	
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
		print("EnemySpawner: Setting up spawn function on MultiplayerSpawner")
		_multiplayer_spawner.spawn_function = _create_enemy_instance
	
	print("EnemySpawner: Creating pool of %d enemies using MultiplayerSpawner" % pool_size)
	
	for i in range(pool_size):
		# Spawn the enemy through the MultiplayerSpawner so it replicates to all clients
		# The spawner will handle replication automatically based on spawn_path
		var enemy: EnemyBase = _multiplayer_spawner.spawn() as EnemyBase
		
		if not enemy:
			printerr("EnemySpawner: Failed to spawn enemy %d through MultiplayerSpawner." % i)
			continue
		
		if not enemy.health_component:
			printerr("EnemySpawner: Enemy instance %d is missing a HealthComponent." % i)
			enemy.queue_free()
			continue
		
		# Connect to the enemy's own signal, which fires after its death animation is complete.
		enemy.ready_for_pooling.connect(_on_enemy_ready_for_pooling.bind(enemy))
		_pool.append(enemy)
		
		# Deactivate the enemy until it's needed (the MultiplayerSpawner already added it to spawn_container via spawn_path)
		enemy.pool_deactivate()
	
	print("EnemySpawner: Pool created with %d enemies" % _pool.size())

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
