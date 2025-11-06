class_name DamageNumbers
extends MultiplayerSpawner

var spawner: MultiplayerSpawner = self
const NORMAL_HIT_GRADIENT_TEXTURE_2D = preload("uid://c5usnjygvaqot")
const CRIT_HIT_GRADIENT_TEXTURE_2D = preload("uid://dby4n0336k1cf")
const PLAYER_HIT_GRADIENT_TEXTURE_2D = preload("uid://battj1yw1t37b")

var _combo_z_index_counter: int = 5

func _ready() -> void:
	spawner.spawn_function = spawn_damage_number

func _get_next_combo_z_index() -> int:
	_combo_z_index_counter += 1
	if _combo_z_index_counter > 100:
		_combo_z_index_counter = 5
	return _combo_z_index_counter

# For single hits (e.g. enemy attacks)
func display_number(value: int, position: Vector2, is_critical: bool = false, is_player: bool = false):
	var spawn_pos = position
	var z_index = _get_next_combo_z_index()
	var number = _spawn_number_only(value, spawn_pos, is_critical, is_player, z_index)
	if is_instance_valid(number):
		_setup_drift_animation.call_deferred(number)

# For combo hits from the player
func display_number_combo(values: Array, are_crits: Array, position: Vector2, is_player: bool = false):
	var spawn_delay = 0.08
	var y_offset_per_hit = -10.0
	var combo_z_index = _get_next_combo_z_index()

	for i in range(values.size()):
		var value = values[i]
		if value == 0 and values.size() > 1: continue

		var is_critical = are_crits[i]
		var spawn_pos = position + Vector2(randf_range(-2, 2), i * y_offset_per_hit)
		
		var timer = get_tree().create_timer(i * spawn_delay, false)
		timer.timeout.connect(
			_spawn_and_setup_combo_hit.bind(value, spawn_pos, is_critical, is_player, combo_z_index - i)
		)

func _spawn_and_setup_combo_hit(value: int, position: Vector2, is_critical: bool, is_player: bool, z_index: int):
	var number = _spawn_number_only(value, position, is_critical, is_player, z_index)
	if is_instance_valid(number):
		_setup_combo_animation.call_deferred(number)

func _setup_combo_animation(number: Node):
	if not is_instance_valid(number):
		print("Node is invalid.")
		return

	var intended_global_position = number.global_position
	var new_pivot = number.size / 2
	
	number.pivot_offset = new_pivot
	
	var new_pos = intended_global_position - (new_pivot * number.scale)
	number.global_position = new_pos

	number.modulate.a = 0.0
	var fade_in_duration = 0.1
	var life_duration = 0.6
	var fade_out_duration = 0.3

	var tween = get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_parallel(false)
	tween.tween_property(number, "modulate:a", 1.0, fade_in_duration)
	tween.tween_interval(life_duration)
	tween.tween_property(number, "modulate:a", 0.0, fade_out_duration)
	tween.tween_callback(number.queue_free)

func _setup_drift_animation(number: Node):
	if not is_instance_valid(number):
		print("Node is invalid.")
		return

	var intended_global_position = number.global_position
	var new_pivot = number.size / 2
	
	number.pivot_offset = new_pivot

	var new_pos = intended_global_position - (new_pivot * number.scale)
	number.global_position = new_pos

	number.modulate.a = 0.0
	var fade_in_duration = 0.1
	var travel_distance_y = -50.0
	var travel_duration = 1.2
	var fade_out_delay = travel_duration - 0.4
	var fade_out_duration = 0.4

	var parallel_tween = get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	parallel_tween.set_parallel(true)
	parallel_tween.tween_property(number, "modulate:a", 1.0, fade_in_duration)
	parallel_tween.tween_property(number, "position:y", number.position.y + travel_distance_y, travel_duration).set_ease(Tween.EASE_OUT)

	var sequence_tween = get_tree().create_tween().set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	sequence_tween.tween_interval(fade_out_delay)
	sequence_tween.chain().tween_property(number, "modulate:a", 0.0, fade_out_duration)
	sequence_tween.chain().tween_callback(number.queue_free)

func _spawn_number_only(value: int, position: Vector2, is_critical: bool = false, is_player: bool = false, z_index: int = 5) -> Node:
	print("Spawning number ", value, " at ", position)
	var number: Label = spawner.spawn([value, position, is_critical, is_player, z_index])
	if is_instance_valid(number):
		print("Spawned. Initial global_position: ", number.global_position)
	if not is_instance_valid(number): return null
	return number

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
	
	number_outline.scale = Vector2(.05,.05)
	number_outline.global_position = args[1]
	number_outline.text = str(args[0])
	number_outline.z_index = args[4] if args.size() > 4 else 5
	number_outline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_outline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_outline.label_settings = LabelSettings.new()
	number_outline.label_settings.font = load("res://assets/fonts/DamageNumbersFontVariation.tres")
	number_outline.label_settings.outline_color = Color.WHITE
	number_outline.label_settings.outline_size = 60
	number_outline.label_settings.font_size = 290
	number_outline.add_theme_constant_override("char_spacing", -15)
	
	number.text = str(args[0])
	number.z_index = args[4] if args.size() > 4 else 5
	number.z_as_relative = false
	number.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.label_settings = LabelSettings.new()
	
	var font = load("res://assets/fonts/DamageNumbersFontVariation.tres")
	var font_size = 290
	
	gradient_texture.texture = NORMAL_HIT_GRADIENT_TEXTURE_2D
	gradient_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_texture.offset_right += 1
	gradient_texture.offset_top += -1
	
	if args[3]:
		gradient_texture.texture = PLAYER_HIT_GRADIENT_TEXTURE_2D
	if args[2]:
		number_outline.scale = Vector2(.056,.056)
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
