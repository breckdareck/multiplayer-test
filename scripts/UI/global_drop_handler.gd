class_name GlobalDropHandler
extends Control

## Global drop handler that detects when items are dragged outside UI windows
## and creates DroppedItem instances in the world

signal item_dropped_in_world(item_data: ItemData, amount: int, world_position: Vector2)

var dropped_item_scene: PackedScene
var game_scene: Node2D

func _ready():
	# Add to group so slots can find us
	add_to_group("global_drop_handler")
	
	# Load the dropped item scene
	dropped_item_scene = preload("res://scenes/Gameplay/dropped_item.tscn")
	
	# Find the game scene
	game_scene = get_tree().get_first_node_in_group("game_scene")
	if not game_scene:
		# Try to find it by path
		game_scene = get_tree().current_scene.get_node("Level/Game")
	
	# Make this control fill the entire screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Enable mouse input
	mouse_filter = Control.MOUSE_FILTER_PASS
	
	# Connect to the global drag end signal
	# We'll use a different approach - monitor for drag operations

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	# Only accept Slot data
	return data is Slot

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var source_slot: Slot = data
	if not source_slot or not source_slot.drag_item:
		return
	
	# Convert screen position to world position
	var world_position = _screen_to_world_position(at_position)
	
	# Emit signal for the game to handle
	item_dropped_in_world.emit(source_slot.drag_item, source_slot.drag_amount, world_position)
	
	# Clear the source slot
	source_slot.cancel_drag()

func _screen_to_world_position(screen_position: Vector2) -> Vector2:
	# Convert screen coordinates to world coordinates
	# This assumes we have a camera in the scene
	var camera = get_viewport().get_camera_2d()
	if camera:
		return camera.to_global(screen_position)
	else:
		# Fallback: use the screen position directly
		return screen_position

func create_dropped_item(item_data: ItemData, amount: int, world_position: Vector2, target_player: Node = null, party_members: Array = []) -> void:
	if not multiplayer.is_server():
		return
	
	if not dropped_item_scene:
		push_error("GlobalDropHandler: Dropped item scene not loaded!")
		return
	
	# Create the dropped item instance
	var dropped_item = dropped_item_scene.instantiate() as DroppedItem
	if not dropped_item:
		push_error("GlobalDropHandler: Failed to instantiate dropped item!")
		return
	
	# Position it in the world
	dropped_item.global_position = world_position
	
	# Setup the dropped item
	dropped_item.setup(item_data, amount, target_player)
	
	# Add party members if provided
	for party_member in party_members:
		if is_instance_valid(party_member):
			dropped_item.add_party_member(party_member)
	
	# Add to the game scene
	if game_scene:
		game_scene.add_child(dropped_item, true)
	else:
		push_error("GlobalDropHandler: No game scene found to add dropped item!")
		dropped_item.queue_free()
		return
	
	print("GlobalDropHandler: Created dropped item %s x%d at %s for player %s" % [item_data.name, amount, world_position, target_player.username if target_player else "NULL"])
