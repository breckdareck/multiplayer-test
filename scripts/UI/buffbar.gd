class_name BuffBar
extends Control

## Displays active buffs with icons and countdown timers in a horizontal layout

#region #################### Configuration ####################
@export var icon_size: Vector2 = Vector2(48, 48)
@export var spacing: float = 8.0
@export var max_visible_buffs: int = 10
@export var progress_color: Color = Color(0.2, 0.8, 0.2, 0.8)  # Green progress ring
@export var background_color: Color = Color(0.2, 0.2, 0.2, 0.5)  # Dark background
@export var progress_thickness: float = 4.0
#endregion

#region #################### Member Variables ####################
var _buff_component: BuffComponent
var _buff_icons: Dictionary = {}  # buff_id -> BuffIcon node
var _container: HBoxContainer
#endregion

#region #################### Inner Class: BuffIcon ####################
class BuffIcon extends Control:
	var buff_id: String
	var icon_texture: Texture2D
	var remaining_time: float = 0.0
	var total_duration: float = 0.0
	var stacks: int = 1
	
	var progress_color: Color
	var background_color: Color
	var progress_thickness: float
	
	var _texture_rect: TextureRect
	var _time_label: Label
	var _stack_label: Label
	var _progress_overlay: Control
	
	func _draw_progress() -> void:
		if total_duration <= 0:
			return  # Don't draw progress for permanent buffs
		
		var center := _progress_overlay.size / 2.0
		var radius = min(_progress_overlay.size.x, _progress_overlay.size.y) / 2.0 - progress_thickness
		
		# Draw background circle
		_progress_overlay.draw_arc(center, radius, 0, TAU, 32, background_color, progress_thickness, true)
		
		# Draw progress arc
		if remaining_time > 0:
			var progress := remaining_time / total_duration
			var angle := -TAU * progress + (PI / 2)  # Start from top, go clockwise
			_progress_overlay.draw_arc(center, radius, PI / 2, angle, 32, progress_color, progress_thickness, true)
	
	func _init(id: String, texture: Texture2D, duration: float, size: Vector2):
		buff_id = id
		icon_texture = texture
		remaining_time = duration
		total_duration = duration
		custom_minimum_size = size
		name = "BuffIcon_" + id
		
		# Background panel
		var panel := Panel.new()
		panel.name = "BackgroundPanel"
		panel.set_anchors_preset(Control.PRESET_FULL_RECT)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)
		
		# Icon texture
		_texture_rect = TextureRect.new()
		_texture_rect.name = "IconTexture"
		_texture_rect.texture = icon_texture
		_texture_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		_texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_texture_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		_texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_texture_rect)
		
		# Progress overlay (drawn on top of icon)
		_progress_overlay = Control.new()
		_progress_overlay.name = "ProgressOverlay"
		_progress_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		_progress_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_progress_overlay.draw.connect(_draw_progress)
		add_child(_progress_overlay)
		
		# Time label
		_time_label = Label.new()
		_time_label.name = "TimeLabel"
		_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_time_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_time_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		_time_label.offset_top = -18
		_time_label.add_theme_font_size_override("font_size", 12)
		_time_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_time_label.add_theme_constant_override("outline_size", 2)
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
	
	func update_time(time: float) -> void:
		remaining_time = time
		if total_duration > 0 and remaining_time > 0:
			_time_label.text = _format_time(remaining_time)
		elif total_duration <= 0:
			_time_label.text = "∞"  # Permanent buff
		else:
			_time_label.text = "0s"
		_progress_overlay.queue_redraw()
	
	func update_stacks(stack_count: int) -> void:
		stacks = stack_count
		if stacks > 1:
			_stack_label.text = "x%d" % stacks
			_stack_label.visible = true
		else:
			_stack_label.visible = false
	
	func _format_time(time: float) -> String:
		if time >= 60:
			var minutes := int(time / 60)
			return "%dm" % minutes
		else:
			return "%.0fs" % time
	
	func _draw() -> void:
		if total_duration <= 0:
			return  # Don't draw progress for permanent buffs
		
		var center := size / 2.0
		var radius = min(size.x, size.y) / 2.0 - progress_thickness
		
		# Draw background circle
		draw_arc(center, radius, 0, TAU, 32, background_color, progress_thickness, true)
		
		# Draw progress arc
		if remaining_time > 0:
			var progress := remaining_time / total_duration
			var angle := -TAU * progress + (PI / 2)  # Start from top, go clockwise
			draw_arc(center, radius, PI / 2, angle, 32, progress_color, progress_thickness, true)
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
	
	# Create buff icon
	var icon := BuffIcon.new(buff_id, buff_data.buff_icon, duration, icon_size)
	icon.progress_color = progress_color
	icon.background_color = background_color
	icon.progress_thickness = progress_thickness
	
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
	icon.total_duration = new_duration
	icon.update_time(new_duration)
	
	# Update stacks
	var stacks := _buff_component.get_buff_stacks(buff_id)
	icon.update_stacks(stacks)
	
	# Brief flash effect on refresh
	var tween := create_tween()
	tween.tween_property(icon, "modulate", Color.WHITE * 1.5, 0.1)
	tween.tween_property(icon, "modulate", Color.WHITE, 0.1)
#endregion
