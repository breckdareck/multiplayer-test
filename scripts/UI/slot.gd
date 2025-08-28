extends PanelContainer
class_name Slot

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

var inventory: InventoryComponent = null

@export var allowed_item_type: Constants.ItemType = Constants.ItemType.ANY
@export var item: ItemData = null:
	set(value):
		var old_item = item
		item = value
		update_display(old_item, value)

# Drag state variables
var is_dragging: bool = false
var drag_item: ItemData = null
var drag_amount: int = 0
var original_amount: int = 0
var is_split_drag: bool = false

func update_display(old_item: ItemData = null, new_item: ItemData = null):
	if item != null:
		texture_rect.texture = item.icon
		if item.can_stack and item.current_stack_amount > 1:
			label.text = str(item.current_stack_amount)
			label.visible = true
		else:
			label.visible = false
	else:
		texture_rect.texture = null
		label.visible = false
	
	inventory._update_item_tracking(self, old_item, new_item)

		
func set_inventory(inv: InventoryComponent):
	inventory = inv
	

func can_add_to_stack(item_to_add: ItemData) -> bool:
	if item == null or item_to_add == null:
		return false
	return item.name == item_to_add.name and item.can_stack and item.current_stack_amount < item.max_stack_amount

	
func add_to_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0

	var space_left = item.max_stack_amount - item.current_stack_amount
	var amount_to_add = min(amount, space_left)
	item.current_stack_amount += amount_to_add
	update_display()
	return amount_to_add

	
func remove_from_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0

	var amount_to_remove = min(amount, item.current_stack_amount)
	item.current_stack_amount -= amount_to_remove
	update_display()
	return amount_to_remove

	
func is_stack_full() -> bool:
	return item != null and item.can_stack and item.current_stack_amount >= item.max_stack_amount

	
func get_remaining_space() -> int:
	if not item or not item.can_stack:
		return 0
	return item.max_stack_amount - item.current_stack_amount


func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	if data is Slot and data != self:
		# NEW: Check if this slot can accept the item being dragged
		if can_accept_item(data.drag_item):
			modulate = Color(0.8, 1.0, 0.8, 2) # Green tint for valid drop
			return true
		else:
			modulate = Color(1.0, 0.8, 0.8, 2) # Red tint for invalid drop
			return false # Prevent the drop
			
	return false

	
func _notification(what):
	if what == NOTIFICATION_DRAG_END:
		modulate = Color.WHITE
		if is_dragging:
			restore_drag_to_source()
			cancel_drag()

			
func get_preview():
	var preview_texture = TextureRect.new()
	preview_texture.texture = texture_rect.texture
	preview_texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview_texture.custom_minimum_size = Vector2(55,55)

	var preview = Control.new()
	preview.add_child(preview_texture)
	preview_texture.position = -.5 * Vector2(55,55)
	
	# Show the amount being dragged (for both splits and full drags)
	if is_dragging and drag_amount > 1:
		var preview_label = Label.new()
		preview_label.text = str(drag_amount)
		preview_label.add_theme_constant_override("outline_size", 2)
		preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
		
		# Different color for split drags vs full drags
		if is_split_drag:
			preview_label.add_theme_color_override("font_color", Color.YELLOW)  # Yellow for splits
			# Optional: Add a split indicator
			preview_label.text = str(drag_amount) + "✂"  # Scissors emoji to indicate split
		else:
			preview_label.add_theme_color_override("font_color", Color.WHITE)   # White for full drags
		
		preview.add_child(preview_label)
		preview_label.position = -.5 * Vector2(55, 55)

	return preview

	
func _get_drag_data(_at_position):
	# If we already have a drag in progress (from force_drag), just return self
	if is_dragging and drag_item != null and drag_amount > 0:
		return self
	
	# If we have a prepared split drag, use that
	if drag_item != null and drag_amount > 0 and not is_dragging:
		is_dragging = true
		set_drag_preview(get_preview())
		return self
	
	# Regular drag of entire item
	if item == null:
		return null
		
	is_dragging = true
	is_split_drag = false
	drag_item = item.duplicate_with_path()
	drag_amount = item.current_stack_amount
	original_amount = item.current_stack_amount

	set_drag_preview(get_preview())
	return self
	

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source_slot: Slot = data
	modulate = Color.WHITE
		
	if not self.can_accept_item(source_slot.drag_item):
		source_slot.restore_drag_to_source()
		source_slot.cancel_drag()
		return

	if self.item != null and not source_slot.can_accept_item(self.item):
		source_slot.restore_drag_to_source()
		source_slot.cancel_drag()
		return

	var from_index = inventory.slots.find(source_slot)
	var to_index = inventory.slots.find(self)
	
	if from_index == -1 or to_index == -1:
		print("Error: Could not find slot indices for movement")
		source_slot.restore_drag_to_source()
		source_slot.cancel_drag()
		return

	# For split drags, we need to handle this differently
	if source_slot.is_split_drag:
		# Use the split system instead of the move system
		var split_successful = inventory.split_stack_clientside(from_index, source_slot.drag_amount, to_index)
		if split_successful:
			source_slot.cancel_drag()
		else:
			print("Split was rejected by clientside validation")
			source_slot.restore_drag_to_source()
			source_slot.cancel_drag()
		return

	# Use the clientside movement system for regular drags
	var move_successful = inventory.move_item_clientside(from_index, to_index)
	
	if move_successful:
		# Only cancel drag if move was successful
		source_slot.cancel_drag()
	else:
		print("Move was rejected by clientside validation")
		# Restore the drag state since we didn't cancel it yet
		source_slot.restore_drag_to_source()
		source_slot.cancel_drag()

		
func restore_drag_to_source():
	"""Restore dragged items back to this slot"""
	if drag_item != null and drag_amount > 0:
		if is_split_drag:
			# For split drags, the original stack wasn't modified yet, so no need to restore
			print("Restored split drag - no changes to original stack needed")
		else:
			# Restore full drag: restore the entire item
			item = drag_item.duplicate_with_path()
			item.current_stack_amount = drag_amount
			update_display()
			print("Restored full drag - ", drag_amount, " items back to source slot")

			
func cancel_drag():
	is_dragging = false
	is_split_drag = false
	drag_item = null
	drag_amount = 0
	original_amount = 0
	
	
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_dragging:
				print("Right-click detected while dragging - restoring items")
				restore_drag_to_source()
				cancel_drag()
				return

			# Right-click to create draggable split
			if item != null and item.can_stack and item.current_stack_amount > 1:
				if drag_item != null and not is_dragging:
					# Cancel existing split if there is one
					cancel_split()
				else:
					# Create new split for dragging
					if Input.is_key_pressed(KEY_SHIFT):
						# Shift+Right-click: Split into singles (create 1-item drag)
						create_drag_split(1)
					else:
						# Regular right-click: Split in half
						var split_amount = ceili(item.current_stack_amount / 2.0)
						create_drag_split(split_amount)

				
func cancel_split():
	"""Cancel a split operation and restore the stack"""
	if drag_item != null and not is_dragging and is_split_drag:
		# For split drags, the original stack wasn't modified yet, so no need to restore
		print("Cancelled split - no changes to original stack needed")
	
	# Clear the split state
	drag_item = null
	drag_amount = 0
	original_amount = 0
	is_split_drag = false

		
func split_stack_half():
	"""Create a draggable half-split (don't auto-place)"""
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return
		
	var split_amount = ceili(item.current_stack_amount / 2.0)
	create_drag_split(split_amount)


func split_stack_half_validated():
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return
		
	var split_amount = ceili(item.current_stack_amount / 2.0)
	print("Splitting stack with validation: ", item.name, " from ", item.current_stack_amount)
	
	if not inventory:
		print("No inventory reference!")
		return

	var current_slot_index = inventory.slots.find(self)
	if current_slot_index == -1:
		print("Could not find current slot in inventory")
		return
	
	# FIXED: Use the clientside split system instead of trying to call RPC directly
	var split_successful = inventory.split_stack_clientside(current_slot_index, split_amount)
	
	if split_successful:
		print("Split initiated with server validation - ", split_amount, " items being moved to new slot")
	else:
		print("Split failed - no empty slots available or invalid split")

	
func show_split_dialog():
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return
	split_stack_half()

	
func split_into_singles():
	"""Create a draggable single-item split"""
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return

	create_drag_split(1)


func create_drag_split(split_amount: int):
	if not item or not item.can_stack or item.current_stack_amount <= split_amount:
		return
	
	print("Creating drag split: ", split_amount, " items from stack of ", item.current_stack_amount)
	
	# Set up the drag state for splitting
	is_split_drag = true
	drag_item = item.duplicate_with_path()
	drag_item.current_stack_amount = split_amount
	drag_amount = split_amount
	original_amount = item.current_stack_amount
	
	# Don't modify the original stack yet - wait for server validation
	# The visual feedback will come from the drag preview
	
	print("Split created - original stack still has ", item.current_stack_amount, ", drag has ", drag_amount)
	
	# FORCE the drag to start immediately
	is_dragging = true
	force_drag(self, get_preview())


func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func can_accept_item(item_to_check: ItemData) -> bool:
	if not item_to_check:
		return true # Can always accept nothing (clearing a slot)
	
	if allowed_item_type == Constants.ItemType.ANY:
		return true

	return item_to_check.item_type == allowed_item_type


func _on_mouse_entered():
	if item != null:
		# print("Mouse Entered: %s" % item.name)
		tooltip_text = item.name
		if item.can_stack:
			tooltip_text += "\nStack: " + str(item.current_stack_amount) + "/" + str(item.max_stack_amount)
		if item.description != "":
			tooltip_text += "\n" + item.description
	else:
		tooltip_text = ""


func _on_mouse_exited():
	tooltip_text = ""
	if not is_dragging:
		modulate = Color.WHITE
