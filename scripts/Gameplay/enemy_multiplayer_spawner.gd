class_name EnemyMultiplayerSpawner
extends MultiplayerSpawner

# Reference to the parent EnemySpawner for configuration
@export var enemy_spawner: Node

var _spawn_function_set: bool = false

func _ready() -> void:
	if not is_multiplayer_authority():
		return
	# Find the parent EnemySpawner if not explicitly set
	if not enemy_spawner:
		enemy_spawner = get_parent()
	
	# Set the spawn function for this MultiplayerSpawner
	if not _spawn_function_set:
		spawn_function = _spawn_enemy_instance
		_spawn_function_set = true
	
	print("EnemyMultiplayerSpawner: Ready at %s, spawn_path: %s" % [get_path(), spawn_path])

func _spawn_enemy_instance() -> Node:
	"""Called by MultiplayerSpawner to create enemy instances for replication"""
	if not enemy_spawner or not enemy_spawner.get("enemy_scene"):
		push_error("EnemyMultiplayerSpawner: Cannot spawn enemy, no enemy_spawner or enemy_scene configured!")
		return null
	
	var enemy_scene = enemy_spawner.enemy_scene
	var enemy = enemy_scene.instantiate()
	
	if not enemy:
		push_error("EnemyMultiplayerSpawner: Failed to instantiate enemy scene")
		return null
	
	return enemy
