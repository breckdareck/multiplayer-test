class_name DamageNumbers
extends MultiplayerSpawner

var spawner: MultiplayerSpawner = self
const NORMAL_HIT_GRADIENT_TEXTURE_2D = preload("uid://c5usnjygvaqot")
const CRIT_HIT_GRADIENT_TEXTURE_2D = preload("uid://dby4n0336k1cf")
const PLAYER_HIT_GRADIENT_TEXTURE_2D = preload("uid://battj1yw1t37b")
const DAMAGE_NUMBERS_1 = preload("res://assets/fonts/DamageNumbersFontVariation.tres")
const DAMAGE_NUMBERS_2 = preload("res://assets/fonts/DamageNumbersFontVariation2.tres")
const DAMAGE_NUMBERS_3 = preload("res://assets/fonts/DamageNumbersFontVariation3.tres")


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
	var z_index = _get_next_combo_z_index()
	
	# Generate deterministic name for this damage number
	var dmg_number_name = "DmgNum_%d_%d" % [Time.get_ticks_msec(), randi()]
	
	print("DamageNumbers.display_number called: value=%d, is_server=%s" % [value, multiplayer.is_server()])
	
	# Server-side: Broadcast to relevant clients manually
	if multiplayer.is_server():
		var args = [value, position, is_critical, is_player, z_index, dmg_number_name]
		
		# First, spawn locally to get the node reference
		var local_number = _create_damage_number_node(value, position, is_critical, is_player, z_index, dmg_number_name)
		if is_instance_valid(local_number):
			_setup_drift_animation.call_deferred(local_number)
			
			# Get the synchronizer to set visibility
			var sync = local_number.get_node_or_null("MultiplayerSynchronizer")
			
			# Find which map this spawner belongs to
			var map_node = get_parent()
			print("DamageNumbers: map_node=%s, in_group=%s" % [map_node, map_node.is_in_group("map_base") if map_node else false])
			if map_node and map_node.is_in_group("map_base"):
				var map_name = map_node.name.replace("Map_", "")
				var players_on_map = MapManager.get_players_on_map(map_name)
				
				print("DamageNumbers: Sending to players on map %s: %s" % [map_name, players_on_map])
				for peer_id in players_on_map:
					# Send RPC to spawn on client
					if peer_id != 1: # Skip server, already spawned locally
						spawn_damage_number_rpc.rpc_id(peer_id, args)
					
					# Set visibility for this peer
					if sync:
						sync.set_visibility_for(peer_id, true)
	else:
		# Client-side local spawn (if called locally, though usually called via RPC)
		print("DamageNumbers: Called on client, doing nothing (expecting RPC)")
		pass

# For combo hits from the player
func display_number_combo(_values: Array, _are_crits: Array, _position: Vector2, _is_player: bool = false):
	# ... (Keep existing logic but ensure it calls display_number or handles RPCs)
	# Since display_number_combo uses _spawn_and_setup_combo_hit which calls _spawn_number_only
	# We need to refactor this too.
	pass # TODO: Refactor combo logic if needed, or just rely on display_number for now.

@rpc("authority", "call_local", "reliable")
func spawn_damage_number_rpc(args: Array):
	var value = args[0]
	var position = args[1]
	var is_critical = args[2]
	var is_player = args[3]
	var z_index = args[4]
	var dmg_number_name = args[5] if args.size() > 5 else ""
	
	var number = _create_damage_number_node(value, position, is_critical, is_player, z_index, dmg_number_name)
	if is_instance_valid(number):
		_setup_drift_animation.call_deferred(number)

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

func _create_damage_number_node(value: int, position: Vector2, is_critical: bool = false, is_player: bool = false, z_index: int = 5, dmg_number_name: String = "") -> Node:
	# Create damage number nodes
	var number_outline = Label.new()
	var number = Label.new()
	var gradient_texture = TextureRect.new()
	
	# Set deterministic name for synchronizer matching
	if dmg_number_name != "":
		number_outline.name = dmg_number_name
	
	# Add MultiplayerSynchronizer for animation sync
	var sync = MultiplayerSynchronizer.new()
	var config = SceneReplicationConfig.new()

	sync.replication_config = config
	sync.public_visibility = false
	config.add_property(".:position")
	config.add_property(".:scale")
	config.add_property(".:modulate")
	config.add_property(".:pivot_offset")
	
	number_outline.add_child(sync )
	number_outline.add_child(number)
	number.add_child(gradient_texture)
	
	var font = DAMAGE_NUMBERS_1
	var font_size = 290
	
	number_outline.scale = Vector2(.05, .05)
	
	# Parent is the map (get_parent())
	var spawn_parent = get_parent()
	if spawn_parent:
		number_outline.position = position - spawn_parent.global_position
		spawn_parent.add_child(number_outline)
	else:
		number_outline.global_position = position
		add_child(number_outline) # Fallback
		
	# ... (Rest of setup logic)
	number_outline.text = str(value)
	number_outline.z_index = z_index
	number_outline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_outline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_outline.label_settings = LabelSettings.new()
	number_outline.label_settings.font = font
	number_outline.label_settings.outline_color = Color.WHITE
	number_outline.label_settings.outline_size = 80
	number_outline.label_settings.font_size = font_size
	number_outline.add_theme_constant_override("char_spacing", -15)
	
	number.text = str(value)
	number.z_index = z_index
	number.z_as_relative = false # Keep relative to parent for proper layering
	number.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.label_settings = LabelSettings.new()
	
	gradient_texture.texture = NORMAL_HIT_GRADIENT_TEXTURE_2D
	gradient_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_texture.offset_right += 1
	gradient_texture.offset_top += -1
	
	if is_player:
		gradient_texture.texture = PLAYER_HIT_GRADIENT_TEXTURE_2D
	if is_critical:
		number_outline.scale = Vector2(.056, .056)
		gradient_texture.texture = CRIT_HIT_GRADIENT_TEXTURE_2D
	if value == 0:
		number.label_settings.font_color = "#FFF8"
		number.label_settings.outline_color = Color.BLACK
		number.label_settings.outline_size = 4
		gradient_texture.texture = null
	
	# Set font AFTER conditionals (matches old function)
	number.label_settings.font_size = font_size
	number.label_settings.font = font

	if value == -1: # MISS
		number_outline.text = "Miss"
		number.text = "Miss"
		number.label_settings.font_color = Color.BLACK
		gradient_texture.texture = null
	
	# Set anchors for proper layout
	number.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	# Explicitly set gradient texture to fill the entire label
	gradient_texture.anchor_left = 0.0
	gradient_texture.anchor_top = 0.0
	gradient_texture.anchor_right = 1.0
	gradient_texture.anchor_bottom = 1.0
	# Set base offsets to 0, then apply the small adjustments
	gradient_texture.offset_left = 0.0
	gradient_texture.offset_top = -1.0 # Small upward adjustment
	gradient_texture.offset_right = 1.0 # Small right adjustment
	gradient_texture.offset_bottom = 0.0
	
	return number_outline

func _spawn_number_only(value: int, position: Vector2, is_critical: bool = false, is_player: bool = false, z_index: int = 5) -> Node:
	# Deprecated/Unused by RPC, but might be used by combo?
	return _create_damage_number_node(value, position, is_critical, is_player, z_index, "")

func spawn_damage_number(args: Array) -> Label:
	var number_outline = Label.new()
	var number = Label.new()
	var gradient_texture = TextureRect.new()
	var sync = MultiplayerSynchronizer.new()
	number_outline.add_child(number)
	number_outline.add_child(sync )
	number.add_child(gradient_texture)
	
	var config = sync.replication_config
	if config == null:
		config = SceneReplicationConfig.new()
		sync.replication_config = config
	
	sync.replication_config.add_property(".:position")
	sync.replication_config.add_property(".:scale")
	sync.replication_config.add_property(".:pivot_offset")
	sync.replication_config.add_property(".:modulate")
	
	
	var font = DAMAGE_NUMBERS_1
	var font_size = 290
	
	
	number_outline.scale = Vector2(.05, .05)
	# Convert global position to local position relative to spawn parent
	# args[1] is the global position, but since this node will be a child of the map (spawn_path = ".."),
	# we need to convert it to local position to account for the map's offset
	var spawn_parent = get_node(spawner.spawn_path)
	if spawn_parent:
		number_outline.position = args[1] - spawn_parent.global_position
	else:
		# Fallback to global position if spawn parent not found
		number_outline.global_position = args[1]
	number_outline.text = str(args[0])
	number_outline.z_index = args[4] if args.size() > 4 else 5
	number_outline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number_outline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number_outline.label_settings = LabelSettings.new()
	number_outline.label_settings.font = font
	number_outline.label_settings.outline_color = Color.WHITE
	number_outline.label_settings.outline_size = 80
	number_outline.label_settings.font_size = font_size
	number_outline.add_theme_constant_override("char_spacing", -15)
	
	number.text = str(args[0])
	number.z_index = args[4] if args.size() > 4 else 5
	number.z_as_relative = false
	number.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.label_settings = LabelSettings.new()
	
	
	gradient_texture.texture = NORMAL_HIT_GRADIENT_TEXTURE_2D
	gradient_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	gradient_texture.offset_right += 1
	gradient_texture.offset_top += -1
	
	if args[3]:
		gradient_texture.texture = PLAYER_HIT_GRADIENT_TEXTURE_2D
	if args[2]:
		number_outline.scale = Vector2(.056, .056)
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
