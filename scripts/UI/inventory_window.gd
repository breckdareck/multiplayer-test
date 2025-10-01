class_name InventoryWindow
extends Control

@onready var inventory_window: Control = $"."
@onready var window_title_label: Label = $Label

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()


func _ready() -> void:
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

func _process(_delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenInventoryWindow"):
			inventory_window.visible = !inventory_window.visible
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset


func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
		else:
			is_dragging = false
