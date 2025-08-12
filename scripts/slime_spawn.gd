extends Area2D

@export var slime_spawn_node: Node2D
@export var spawn_location : Marker2D
@onready var slime_spawner: MultiplayerSpawner = $SlimeSpawner

var _slime_scene = preload("res://scenes/slime.tscn")

func _ready() -> void:
	if slime_spawn_node:
		slime_spawner.spawn_path = slime_spawn_node.get_path()
	else:
		print("No Spawn Node Detected")

func _on_body_entered(body):
	if is_multiplayer_authority():
		print("Slime spawned by %s" % body.name)
		call_deferred("_create_slime")
		_disable_spawn()

func _create_slime():
	var slime_to_spawn = _slime_scene.instantiate()
	slime_to_spawn.position = spawn_location.global_position
	
	var time_to_live = _create_death_timer()
	time_to_live.timeout.connect(slime_to_spawn.die)
	slime_to_spawn.add_child(time_to_live)
	
	slime_spawn_node.add_child(slime_to_spawn, true)

func _create_death_timer() -> Timer:
	var time_to_live = Timer.new()
	time_to_live.wait_time = 2
	time_to_live.one_shot = true
	time_to_live.autostart = true
	return time_to_live

func _disable_spawn():
	var collision_shape = get_node("CollisionShape2D")
	collision_shape.set_deferred("disabled", true)
