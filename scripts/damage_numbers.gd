class_name DamageNumbers
extends MultiplayerSpawner

var spawner: MultiplayerSpawner = self
const NORMAL_HIT_GRADIENT_TEXTURE_2D = preload("uid://c5usnjygvaqot")
const CRIT_HIT_GRADIENT_TEXTURE_2D = preload("uid://dby4n0336k1cf")
const PLAYER_HIT_GRADIENT_TEXTURE_2D = preload("uid://battj1yw1t37b")

func _ready() -> void:
	spawner.spawn_function = spawn_damage_number


func display_number(value: int, position: Vector2, is_critical: bool = false, is_player: bool = false):
	var number: Label = spawner.spawn([value, position, is_critical, is_player])
	
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
	var number_outline = Label.new()
	var number = Label.new()
	var gradient_texture = TextureRect.new()
	var sync = MultiplayerSynchronizer.new()
	number_outline.add_child(number)
	number_outline.add_child(sync)
	number.add_child(gradient_texture)
	
	var config = sync.replication_config
	if config == null:
		config = SceneReplicationConfig.new()
		sync.replication_config = config
	
	sync.replication_config.add_property(".:position")
	sync.replication_config.add_property(".:scale")
	sync.replication_config.add_property(".:pivot_offset")
	
	number_outline.global_position = args[1]
	number_outline.text = str(args[0])
	number_outline.z_index = 5
	number_outline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_outline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_outline.label_settings = LabelSettings.new()
	number_outline.label_settings.font = load("res://assets/fonts/PixelOperator8-Bold.ttf")
	number_outline.label_settings.outline_color = Color.WHITE
	number_outline.label_settings.outline_size = 4
	number_outline.label_settings.font_size = 16
	
	
	number.text = str(args[0])
	number.z_index = 5
	number.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.label_settings = LabelSettings.new()
	
	
	var font = load("res://assets/fonts/PixelOperator8-Bold.ttf")
	var font_size = 16
	
	gradient_texture.texture = NORMAL_HIT_GRADIENT_TEXTURE_2D
	gradient_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_texture.offset_right += 1
	gradient_texture.offset_top += -1
	
	if args[3]:
		gradient_texture.texture = PLAYER_HIT_GRADIENT_TEXTURE_2D
	if args[2]:
		number_outline.scale = Vector2(1.4,1.4)
		gradient_texture.texture = CRIT_HIT_GRADIENT_TEXTURE_2D
	if args[0] == 0:
		number.label_settings.font_color = "#FFF8"
		number.label_settings.outline_color = Color.BLACK
		number.label_settings.outline_size = 4
		gradient_texture.texture = null
		
	number.label_settings.font_size = font_size
	number.label_settings.font = font

	if args[0] == -1: # MISS
		number_outline.text = "Miss"
		number.text = "Miss"
		number.label_settings.font_color = Color.BLACK
		gradient_texture.texture = null
	
	number.set_anchors_preset(Control.PRESET_FULL_RECT)
	gradient_texture.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	
	#call_deferred("add_child", number)
	return number_outline
