class_name BuffBar
extends Control

## Displays active buffs with icons and countdown timers in a horizontal layout

#region #################### Configuration ####################
@export var icon_size: Vector2 = Vector2(68, 68)
@export var spacing: int = 8
@export var max_visible_buffs: int = 10
#endregion

#region #################### Member Variables ####################
var _buff_component: BuffComponent
var _buff_icons: Dictionary = {}  # buff_id -> BuffIcon node
var _container: HBoxContainer
#endregion

#region #################### Inner Class: BuffIcon ####################
class BuffIcon extends Control:
	signal buff_remove_requested(buff_id: String)
	
	var buff_id: String
	var icon_texture: Texture2D
	var remaining_time: float = 0.0
	var total_duration: float = 0.0
	var stacks: int = 1
	var is_removable: bool = true  # NEW: Can this buff be manually removed?
	
	var gradient_color: Color = Color(0.3, 0.3, 0.3, 0.8)
	var hover_color: Color = Color(1.0, 1.0, 1.0, 0.3)
	
	var _texture_rect: TextureRect
	var _time_label: Label
	var _stack_label: Label
	var _gradient_overlay: ColorRect
	var _hover_overlay: ColorRect  # NEW: Shows when hovering
	
	func _init(id: String, texture: Texture2D, duration: float, icon_dimensions: Vector2, removable: bool = true):
		buff_id = id
		icon_texture = texture
		remaining_time = duration
		total_duration = duration
		is_removable = removable
		custom_minimum_size = icon_dimensions
		name = "BuffIcon_" + id
		
		# NEW: Enable mouse input
		mouse_filter = Control.MOUSE_FILTER_STOP
		
		# Icon texture
		_texture_rect = TextureRect.new()
		_texture_rect.name = "IconTexture"
		_texture_rect.texture = icon_texture
		_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_texture_rect)
		
		# Gradient overlay (moves from top to bottom as time decreases)
		_gradient_overlay = ColorRect.new()
		_gradient_overlay.name = "GradientOverlay"
		_gradient_overlay.color = gradient_color
		_gradient_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_gradient_overlay.anchor_left = 0
		_gradient_overlay.anchor_right = 1
		_gradient_overlay.anchor_top = 0
		_gradient_overlay.anchor_bottom = 0
		_gradient_overlay.offset_left = 0
		_gradient_overlay.offset_right = 0
		_gradient_overlay.offset_top = 0
		_gradient_overlay.offset_bottom = 0
		add_child(_gradient_overlay)
		
		# NEW: Hover overlay (shows on mouse hover)
		_hover_overlay = ColorRect.new()
		_hover_overlay.name = "HoverOverlay"
		_hover_overlay.color = hover_color
		_hover_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hover_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_hover_overlay.visible = false
		add_child(_hover_overlay)
		
		# Time label (centered, yellow text with black outline)
		_time_label = Label.new()
		_time_label.name = "TimeLabel"
		_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_time_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_time_label.add_theme_font_size_override("font_size", 16)
		_time_label.add_theme_color_override("font_color", Color.YELLOW)
		_time_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_time_label.add_theme_constant_override("outline_size", 16)
		_time_label.add_theme_font_override("font", load("res://assets/fonts/PixelOperator8-Bold.ttf"))
		_time_label.add_theme_font_size_override("font_size", 24)
		_time_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_time_label)
		
		# Stack label (top right corner)
		_stack_label = Label.new()
		_stack_label.name = "StackLabel"
		_stack_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_stack_label.vertical_alignment = VERTICAL_ALIGNMENT_TOP
		_stack_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		_stack_label.offset_left = -24
		_stack_label.offset_right = -4
		_stack_label.offset_top = 4
		_stack_label.offset_bottom = 20
		_stack_label.add_theme_font_size_override("font_size", 14)
		_stack_label.add_theme_color_override("font_color", Color.YELLOW)
		_stack_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_stack_label.add_theme_constant_override("outline_size", 2)
		_stack_label.visible = false
		_stack_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_stack_label)

		TooltipTheme.apply_to(self)
	
	# NEW: Handle mouse enter
	func _mouse_enter() -> void:
		if is_removable:
			_hover_overlay.visible = true
		tooltip_text = _build_tooltip()
		# Debuffs (non-removable buffs) get a red tooltip border to match the
		# "this is bad" cue the rest of the UI uses.
		var border: Variant = null
		if not is_removable:
			border = Color(0.9, 0.3, 0.3)
		TooltipTheme.set_border_color(self, border)

	func _build_tooltip() -> String:
		var buff_data: BuffData = ResourceManager.get_buff_data(buff_id)
		var lines: Array[String] = []
		if buff_data and not buff_data.buff_name.is_empty():
			lines.append(buff_data.buff_name)
		else:
			lines.append(buff_id)
		if buff_data and not buff_data.description.is_empty():
			lines.append("")
			lines.append(buff_data.description)
		if is_removable:
			lines.append("")
			lines.append("(Right-click to remove)")
		return "\n".join(lines)

	# NEW: Handle mouse exit
	func _mouse_exit() -> void:
		_hover_overlay.visible = false
	
	# NEW: Handle mouse input
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				if is_removable:
					buff_remove_requested.emit(buff_id)
					accept_event()  # Prevent event from propagating
	
	func update_time(time: float) -> void:
		remaining_time = time
		
		# Update text to show only the number
		if total_duration > 0 and remaining_time > 0:
			_time_label.text = _format_time_number(remaining_time)
		elif total_duration <= 0:
			_time_label.text = "∞"  # Permanent buff
		else:
			_time_label.text = "0"
		
		# Update gradient overlay height based on remaining time
		_update_gradient_overlay()
	
	func _update_gradient_overlay() -> void:
		if total_duration <= 0:
			# Permanent buff - no overlay
			_gradient_overlay.visible = false
			return
		
		_gradient_overlay.visible = true
		
		# Calculate how much of the icon should be covered
		# As time decreases, gradient covers more (moves from top to bottom)
		var progress := 0.0
		if total_duration > 0:
			progress = 1.0 - (remaining_time / total_duration)  # 0 = full time, 1 = no time
		
		# Set the gradient to cover from top to the progress point
		_gradient_overlay.anchor_bottom = progress
	
	func update_stacks(stack_count: int) -> void:
		stacks = stack_count
		if stacks > 1:
			_stack_label.text = "x%d" % stacks
			_stack_label.visible = true
		else:
			_stack_label.visible = false
	
	func _format_time_number(time: float) -> String:
		# Only return the number, no unit suffix
		if time >= 60:
			var minutes := int(time / 60)
			_time_label.add_theme_font_size_override("font_size", 16)
			return "%dm" % minutes
		else:
			_time_label.add_theme_font_size_override("font_size", 24)
			return "%.0f" % time
#endregion

#region #################### Godot Engine Callbacks ####################
func _ready() -> void:
	# Create container
	_container = HBoxContainer.new()
	_container.name = "BuffIconContainer"
	_container.alignment = BoxContainer.ALIGNMENT_END
	_container.add_theme_constant_override("separation", spacing)
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_container)
	
	# Find BuffComponent in parent hierarchy
	_find_buff_component()
	
	if _buff_component:
		_connect_buff_signals()
		_initialize_existing_buffs()


func _process(delta: float) -> void:
	if not _buff_component:
		return
	
	# Update all buff timers
	for buff_id in _buff_icons:
		var icon: BuffIcon = _buff_icons[buff_id]
		var current_time := _buff_component.get_buff_duration(buff_id)
		
		# Client-side prediction: tick down locally
		if not multiplayer.is_server() and icon.total_duration > 0:
			icon.remaining_time = max(0, icon.remaining_time - delta)
			icon.update_time(icon.remaining_time)
		else:
			# Server uses authoritative time
			icon.update_time(current_time)
#endregion

#region #################### Initialization ####################
func _find_buff_component() -> void:
	# Try to find BuffComponent in common locations
	var player = owner as MultiplayerPlayerV2
	if player:
		_buff_component = player.buff_component
	
	if not _buff_component:
		push_warning("BuffBar: Could not find BuffComponent. Manually set it using set_buff_component()")


func set_buff_component(component: BuffComponent) -> void:
	if _buff_component:
		_disconnect_buff_signals()
	
	_buff_component = component
	
	if _buff_component:
		_connect_buff_signals()
		_initialize_existing_buffs()


func _connect_buff_signals() -> void:
	_buff_component.buff_applied.connect(_on_buff_applied)
	_buff_component.buff_removed.connect(_on_buff_removed)
	_buff_component.buff_refreshed.connect(_on_buff_refreshed)


func _disconnect_buff_signals() -> void:
	if _buff_component.buff_applied.is_connected(_on_buff_applied):
		_buff_component.buff_applied.disconnect(_on_buff_applied)
	if _buff_component.buff_removed.is_connected(_on_buff_removed):
		_buff_component.buff_removed.disconnect(_on_buff_removed)
	if _buff_component.buff_refreshed.is_connected(_on_buff_refreshed):
		_buff_component.buff_refreshed.disconnect(_on_buff_refreshed)


func _initialize_existing_buffs() -> void:
	# Clear any stale icons first
	for buff_id in _buff_icons.keys():
		var icon: BuffIcon = _buff_icons[buff_id]
		icon.queue_free()
	_buff_icons.clear()
	
	# Load any buffs that are already active
	var active_buffs := _buff_component.get_active_buff_ids()
	for buff_id in active_buffs:
		var duration := _buff_component.get_buff_duration(buff_id)
		_on_buff_applied(buff_id, duration)
#endregion

#region #################### Signal Handlers ####################
func _on_buff_applied(buff_id: String, duration: float) -> void:
	# Don't add duplicate icons
	if _buff_icons.has(buff_id):
		_on_buff_refreshed(buff_id, duration)
		return
	
	# Check max visible buffs
	if _buff_icons.size() >= max_visible_buffs:
		push_warning("BuffBar: Maximum visible buffs reached (%d)" % max_visible_buffs)
		return
	
	# Get buff data
	var buff_data: BuffData = ResourceManager.get_buff_data(buff_id)
	if not buff_data:
		push_warning("BuffBar: Could not find BuffData for '%s'" % buff_id)
		return
	
	# Determine if buff can be manually removed (beneficial buffs can be removed, debuffs cannot)
	var is_removable = not buff_data.is_debuff
	
	# Create buff icon — use the actual applied total duration for the progress bar
	# (which may differ from the resource default if a custom duration was used),
	# and the passed-in duration (which may be remaining time on load) for the countdown.
	var total_dur: float = _buff_component.get_buff_total_duration(buff_id)
	if total_dur <= 0.0:
		total_dur = buff_data.duration  # fallback to resource default
	var icon := BuffIcon.new(buff_id, buff_data.buff_icon, total_dur, icon_size, is_removable)
	icon.remaining_time = duration
	icon.update_time(duration)

	# NEW: Connect the remove signal
	icon.buff_remove_requested.connect(_on_buff_remove_requested)

	# Update stacks if applicable
	var stacks := _buff_component.get_buff_stacks(buff_id)
	icon.update_stacks(stacks)

	_buff_icons[buff_id] = icon
	_container.add_child(icon)
	
	# Add a fade-in animation
	icon.modulate.a = 0.0
	var tween := create_tween()
	tween.tween_property(icon, "modulate:a", 1.0, 0.3)


func _on_buff_removed(buff_id: String) -> void:
	if not _buff_icons.has(buff_id):
		return
	
	var icon: BuffIcon = _buff_icons[buff_id]
	_buff_icons.erase(buff_id)
	
	# Fade out animation before removing
	var tween := create_tween()
	tween.tween_property(icon, "modulate:a", 0.0, 0.2)
	tween.tween_callback(icon.queue_free)


func _on_buff_refreshed(buff_id: String, new_duration: float) -> void:
	if not _buff_icons.has(buff_id):
		# Icon doesn't exist (possibly due to reconnection), create it
		_on_buff_applied(buff_id, new_duration)
		return

	var icon: BuffIcon = _buff_icons[buff_id]
	# Use the actual applied total duration from the buff component,
	# which accounts for custom durations from ability level scaling.
	var total_dur: float = _buff_component.get_buff_total_duration(buff_id)
	if total_dur > 0.0:
		icon.total_duration = total_dur
	icon.remaining_time = new_duration
	icon.update_time(new_duration)
	
	# Update stacks
	var stacks := _buff_component.get_buff_stacks(buff_id)
	icon.update_stacks(stacks)
	
	# Brief flash effect on refresh
	var tween := create_tween()
	tween.tween_property(icon, "modulate", Color.WHITE * 1.5, 0.1)
	tween.tween_property(icon, "modulate", Color.WHITE, 0.1)


func _on_buff_remove_requested(buff_id: String) -> void:
	if not _buff_component:
		return
	
	# Request buff removal from the buff component
	#print("BuffBar: Requesting removal of buff '%s'" % buff_id)
	_buff_component.remove_buff(buff_id)
#endregion
