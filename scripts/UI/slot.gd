extends PanelContainer
class_name Slot

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

var inventory: InventoryComponent = null

@export var item: Item = null:
	set(value):
		item = value
		_update_display()

# Drag state variables
var is_dragging: bool = false
var drag_item: Item = null
var drag_amount: int = 0
var original_amount: int = 0
var is_split_drag: bool = false

func _update_display():
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

		
func set_inventory(inv: InventoryComponent):
	inventory = inv
	

func can_add_to_stack(item_to_add: Item) -> bool:
	if item == null or item_to_add == null:
		return false
	return item.name == item_to_add.name and item.can_stack and item.current_stack_amount < item.max_stack_amount

	
func add_to_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0

	var space_left = item.max_stack_amount - item.current_stack_amount
	var amount_to_add = min(amount, space_left)
	item.current_stack_amount += amount_to_add
	_update_display()
	return amount_to_add

	
func remove_from_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0

	var amount_to_remove = min(amount, item.current_stack_amount)
	item.current_stack_amount -= amount_to_remove
	_update_display()
	return amount_to_remove

	
func is_stack_full() -> bool:
	return item != null and item.can_stack and item.current_stack_amount >= item.max_stack_amount

	
func get_remaining_space() -> int:
	if not item or not item.can_stack:
		return 0
	return item.max_stack_amount - item.current_stack_amount


func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	var can_drop = data is Slot and data != self
	if can_drop:
		modulate = Color(0.8, 1.0, 0.8, 2)
	return can_drop

	
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
	
	if is_dragging and drag_amount > 1:
		var preview_label = Label.new()
		preview_label.text = str(drag_amount)
		preview_label.add_theme_color_override("font_color", Color.WHITE)
		preview_label.add_theme_constant_override("outline_size", 2)
		preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
		preview.add_child(preview_label)
		preview_label.position = -.5 * Vector2(55, 55)

	return preview

	
func _get_drag_data(_at_position):
	if drag_item != null and drag_amount > 0:
		is_dragging = true
		set_drag_preview(get_preview())
		return self
		
	if item == null:
		return
		
	is_dragging = true
	is_split_drag = false
	drag_item = item.duplicate()
	drag_amount = item.current_stack_amount
	original_amount = item.current_stack_amount

	set_drag_preview(get_preview())
	return self

	
func _drop_data(at_position: Vector2, data: Variant) -> void:
	var source_slot: Slot = data
	if source_slot == self:
		return
		
	modulate = Color.WHITE
	
	if item != null and source_slot.drag_item != null and item.name == source_slot.drag_item.name and item.can_stack:
		var space_left = get_remaining_space()
		if space_left > 0:
			var amount_to_move = min(source_slot.drag_amount, space_left)
			add_to_stack(amount_to_move)
		
			source_slot.drag_amount -= amount_to_move
		
			if source_slot.drag_amount <= 0:
				if source_slot.is_split_drag and source_slot.item.current_stack_amount > 0:
					source_slot.cancel_drag()
				else:
					source_slot.cancel_drag()
					source_slot.item = null
			else:
				source_slot.item = source_slot.drag_item.duplicate()
				source_slot.item.current_stack_amount = source_slot.drag_amount
				source_slot._update_display()
				source_slot.cancel_drag()
			return
		
	if source_slot.drag_item != null:
		if item == null:
			item = source_slot.drag_item.duplicate()
			item.current_stack_amount = source_slot.drag_amount
			_update_display()
			
			if not source_slot.is_split_drag:
				source_slot.item = null
		else:
			var current_slot_item = item
			
			item = source_slot.drag_item.duplicate()
			item.current_stack_amount = source_slot.drag_amount
			_update_display()
			
			if source_slot.is_split_drag:
				print("Cannot swap items during split operation")
				item = current_slot_item
				_update_display()
				source_slot.item.current_stack_amount += source_slot.drag_amount
				source_slot._update_display()
			else:
				source_slot.item = current_slot_item.duplicate() if current_slot_item else null
				source_slot._update_display()
		
		source_slot.cancel_drag()
		
	if source_slot.is_dragging:
		source_slot.cancel_drag()

		
func restore_drag_to_source():
	"""Restore dragged items back to this slot"""
	if drag_item != null and drag_amount > 0:
		if is_split_drag:
			item.current_stack_amount += drag_amount
			_update_display()
			print("Restored ", drag_amount, " items back to source slot (split operation)")
		else:
			item = drag_item.duplicate()
			item.current_stack_amount = drag_amount
			_update_display()
			print("Restored ", drag_amount, " items back to source slot (normal drag)")

			
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

			if item != null and item.can_stack and item.current_stack_amount > 1:
				if drag_item != null and not is_dragging:
					cancel_split()
				else:
					show_split_dialog()

					
func cancel_split():
	if drag_item != null and not is_dragging:
		item.current_stack_amount += drag_amount
		_update_display()

		drag_item = null
		drag_amount = 0
		original_amount = 0

		print("Cancelled split - restored stack to ", item.current_stack_amount)
		
		
func split_stack_half():
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return
		
	var split_amount = ceili(item.current_stack_amount / 2.0)
	var remaining_amount = item.current_stack_amount - split_amount

	print("Splitting stack in half: ", item.name, " from ", item.current_stack_amount, " - dragging ", split_amount, ", keeping ", remaining_amount)
	
	if not inventory or not inventory.has_method("get_empty_slots"):
		print("No inventory reference or get_empty_slots method not found!")
		return

	var empty_slots = inventory.get_empty_slots()
	if empty_slots.size() == 0:
		print("No empty slots available for splitting")
		return
		
	item.current_stack_amount = remaining_amount
	_update_display()
	
	drag_item = item.duplicate()
	drag_amount = split_amount
	original_amount = split_amount
	is_dragging = true
	is_split_drag = true
	
	force_drag(self, get_preview())

	print("Split ", split_amount, " items - now force dragging them")
	
	
func show_split_dialog():
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return
		
	split_stack_half()

	
func split_into_singles():
	if not item or not item.can_stack or item.current_stack_amount <= 1:
		return

	print("Splitting into singles: ", item.name, " from ", item.current_stack_amount)
	
	if not inventory or not inventory.has_method("get_empty_slots"):
		print("No inventory reference or get_empty_slots method not found!")
		return
		
	var empty_slots = inventory.get_empty_slots()
	var items_to_split = min(item.current_stack_amount - 1, empty_slots.size())

	if items_to_split > 0:
		item.current_stack_amount = 1
		_update_display()
		
		drag_item = item.duplicate()
		drag_amount = items_to_split
		original_amount = items_to_split
		is_dragging = true
		is_split_drag = true
		
		force_drag(self, get_preview())

		print("Split ", items_to_split, " items - now dragging them")
	else:
		print("No empty slots available for splitting")

		
func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)


func split_stack_manual():
	if item != null and item.can_stack and item.current_stack_amount > 1:
		split_stack_half()

		
func _on_mouse_entered():
	if item != null:
		var tooltip_text = item.name
		if item.can_stack:
			tooltip_text += "\nStack: " + str(item.current_stack_amount) + "/" + str(item.max_stack_amount)
		if item.description != "":
			tooltip_text += "\n" + item.description

			
func _on_mouse_exited():
	if not is_dragging:
		modulate = Color.WHITE
