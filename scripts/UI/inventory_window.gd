class_name InventoryWindow
extends Control

@onready var inventory_window: Control = $"."
@onready var window_title_label: Label = $Label
@onready var monies_count_label: Label = $HBoxContainer/Panel/MoniesCountLabel

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()


func _ready() -> void:
	# Add to ui_window group for drop detection
	add_to_group("ui_window")
	
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

func _process(_delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenInventoryWindow"):
			if inventory_window.visible:
				inventory_window.visible = false
			elif not InputManager.is_locked():
				inventory_window.visible = true
			
	if is_dragging:
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var window_size = size
		
		new_position.x = clamp(new_position.x, 0, viewport_size.x - window_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - window_size.y)
		
		global_position = new_position

func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
				self.move_to_front()
		else:
			is_dragging = false
