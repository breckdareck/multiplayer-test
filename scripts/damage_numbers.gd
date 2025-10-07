class_name DamageNumbers
extends MultiplayerSpawner

var spawner: MultiplayerSpawner = self

func _ready() -> void:
	spawner.spawn_function = spawn_damage_number


func display_number(value: int, position: Vector2, is_critical: bool = false):
	var number: Label = spawner.spawn([value, position, is_critical])
	
	number.pivot_offset = Vector2(number.size /2)
	
	var tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(
		number, "position:y", number.position.y - 24, 0.25
	).set_ease(Tween.EASE_OUT)
	tween.tween_property(
		number, "position:y", number.position.y, 0.5
	).set_ease(Tween.EASE_IN).set_delay(0.25)
	tween.tween_property(
		number, "scale", Vector2.ZERO, 0.25
	).set_ease(Tween.EASE_IN).set_delay(0.5)

	await tween.finished
	number.queue_free()


func spawn_damage_number(args: Array) -> Label:
	var number = Label.new()
	var sync = MultiplayerSynchronizer.new()
	number.add_child(sync)
	var config = sync.replication_config
	if config == null:
		config = SceneReplicationConfig.new()
		sync.replication_config = config
	
	sync.replication_config.add_property(".:position")
	sync.replication_config.add_property(".:scale")
	sync.replication_config.add_property(".:pivot_offset")
	
	number.global_position = args[1]
	number.text = str(args[0])
	#number.scale = Vector2(0.5,0.5)
	number.z_index = 5
	number.label_settings = LabelSettings.new()
	
	var color = Color.DARK_GREEN
	var outline_color = Color.WHITE
	if args[2]:
		color = Color.RED
	if args[0] == 0:
		color = "#FFF8"
		outline_color = Color.BLACK
		
	number.label_settings.font_color = color
	number.label_settings.font_size = 8
	number.label_settings.font = load("res://assets/fonts/PixelOperator8-Bold.ttf")
	number.label_settings.outline_color = outline_color
	number.label_settings.outline_size = 4
	
	#call_deferred("add_child", number)
	return number
