extends PanelContainer
class_name Slot

const PANEL_STYLEBOX_THEME: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

# This can be an InventoryComponent, EquipmentComponent, or any other Node that manages slots.
var item_container: Node = null

@export var allowed_item_type: Constants.ItemType = Constants.ItemType.ANY

@export var item: ItemData = null:
	set(value):
		var old_item = item
		item = value
		# The container is responsible for tracking changes
		if item_container and item_container.has_method("_update_item_tracking"):
			item_container._update_item_tracking(self, old_item, value)
		update_display()

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
	texture_rect.queue_redraw()
	label.queue_redraw()
	
	if item_container and item_container.has_method("_update_item_tracking"):
		item_container._update_item_tracking(self, old_item, new_item)

# The slot's container is now a generic Node.
func set_inventory(inv: Node):
	item_container = inv

func _drop_data(_at_position: Vector2, data: Variant) -> void:
	var source_slot: Slot = data
	modulate = Color.WHITE
	var successful_operation = false

	# --- VALIDATION ---
	if not can_accept_item(source_slot.drag_item):
		return # Let NOTIFICATION_DRAG_END handle restoration

	# If this slot has an item, check if the source slot can accept it (for a swap)
	if item != null and not source_slot.can_accept_item(item):
		return # Let NOTIFICATION_DRAG_END handle restoration

	# --- EXECUTION ---
	var source_container = source_slot.item_container
	var target_container = self.item_container

	# Case 1: Moving within the same InventoryComponent
	if source_container == target_container and source_container is InventoryComponent:
		var from_index = source_container.get_slots().find(source_slot)
		var to_index = source_container.get_slots().find(self)

		if from_index != -1 and to_index != -1:
			if source_slot.is_split_drag:
				successful_operation = source_container.split_stack_clientside(from_index, source_slot.drag_amount, to_index)
			else:
				successful_operation = source_container.move_item_clientside(from_index, to_index)
	
	# Case 2: Moving between different containers (e.g., Inventory <-> Equipment)
	else:
		# The InventoryComponent should orchestrate all transfers.
		# We need to find it. Assume one of the containers is the main inventory.
		var main_inventory = source_container if source_container is InventoryComponent else target_container
		if main_inventory is InventoryComponent and main_inventory.has_method("transfer_item_clientside"):
			successful_operation = main_inventory.transfer_item_clientside(source_slot, self)

	# On success, cancel the source slot's drag state to prevent it from being restored.
	if successful_operation:
		source_slot.cancel_drag()

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
	
	if is_dragging and drag_amount > 1:
		var preview_label = Label.new()
		preview_label.text = str(drag_amount)
		preview_label.add_theme_constant_override("outline_size", 2)
		preview_label.add_theme_color_override("font_outline_color", Color.BLACK)
		
		if is_split_drag:
			preview_label.add_theme_color_override("font_color", Color.YELLOW)
			preview_label.text = str(drag_amount) + "✂"
		else:
			preview_label.add_theme_color_override("font_color", Color.WHITE)
		
		preview.add_child(preview_label)
		preview_label.position = -.5 * Vector2(55, 55)

	return preview

func _get_drag_data(_at_position):
	if is_dragging and drag_item != null and drag_amount > 0:
		return self
	
	if drag_item != null and drag_amount > 0 and not is_dragging:
		is_dragging = true
		set_drag_preview(get_preview())
		return self
	
	if item == null:
		return null
		
	is_dragging = true
	is_split_drag = false
	drag_item = item.duplicate_with_path()
	drag_amount = item.current_stack_amount
	original_amount = item.current_stack_amount

	set_drag_preview(get_preview())
	return self

func restore_drag_to_source():
	"""Restore dragged items back to this slot"""
	if drag_item != null and drag_amount > 0:
		if is_split_drag:
			# For split drags, the original stack wasn't modified yet, so no need to restore
			pass
		else:
			# Restore full drag: restore the entire item
			item = drag_item.duplicate_with_path()
			item.current_stack_amount = drag_amount
			update_display()

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
				# Abort any drag with a right click
				# The NOTIFICATION_DRAG_END will handle the restoration
				get_viewport().gui_release_focus()
				return

			# Right-click to create draggable split
			if item != null and item.can_stack and item.current_stack_amount > 1:
				if drag_item != null and not is_dragging:
					# Cancel existing split if there is one
					cancel_split()
				else:
					# Create new split for dragging
					if Input.is_key_pressed(KEY_SHIFT):
						create_drag_split(1)
					else:
						var split_amount = ceili(item.current_stack_amount / 2.0)
						create_drag_split(split_amount)

func cancel_split():
	"""Cancel a split operation and restore the stack"""
	if drag_item != null and not is_dragging and is_split_drag:
		pass
	
	# Clear the split state
	drag_item = null
	drag_amount = 0
	original_amount = 0
	is_split_drag = false

func create_drag_split(split_amount: int):
	if not item or not item.can_stack or item.current_stack_amount <= split_amount:
		return
	
	is_split_drag = true
	drag_item = item.duplicate_with_path()
	drag_item.current_stack_amount = split_amount
	drag_amount = split_amount
	original_amount = item.current_stack_amount
	
	is_dragging = true
	force_drag(self, get_preview())

func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	var custom_theme = Theme.new()
	custom_theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX_THEME)
	self.theme = custom_theme


func can_accept_item(item_to_check: ItemData) -> bool:
	if not item_to_check:
		return true # Can always accept nothing (clearing a slot)

	# Optional: uncomment for debugging
	# print("Slot: %s" % item_to_check.name)

	# General item type check
	if allowed_item_type != Constants.ItemType.ANY and item_to_check.item_type != allowed_item_type:
		return false

	return true


#func _make_custom_tooltip(_for_text: String) -> Object:
	#var tooltip_scene: Panel = Panel.new()
	#var tooltip_label: Label = Label.new()
	#tooltip_scene.size = Vector2(100,50)
	#tooltip_label.add_theme_font_size_override("font_size", 16)
	#tooltip_scene.add_theme_stylebox_override("panel", PANEL_STYLEBOX_THEME)
	#tooltip_scene.add_child(tooltip_label)
	#tooltip_label.text = "test"
	#return tooltip_scene


func _on_mouse_entered():
	if item != null:
		tooltip_text = item.name
		if item.can_stack:
			tooltip_text += "\nStack: " + str(item.current_stack_amount) + "/" + str(item.max_stack_amount)
		if item.description != "":
			tooltip_text += "\n" + item.description
		if item.item_type == Constants.ItemType.EQUIPMENT:
			if item.equipment_type == Constants.EquipmentType.WEAPON:
				tooltip_text += "\n" + "Type: " + str(Constants.WeaponType.keys()[item.weapon_type]).capitalize()
				tooltip_text += "\n" + "Attack Speed: " + str(item.attack_speed).to_upper()
			if item.equipment_type == Constants.EquipmentType.ARMOR:
				tooltip_text += "\n" + "Type: " + str(Constants.ArmorType.keys()[item.armor_type]).capitalize()
			if item.bonus_stats:
				for stat_type in item.bonus_stats:
					if item.bonus_stats[stat_type].flat_bonus_value > 0:
						tooltip_text += "\n" + str(Constants.StatType.keys()[stat_type]).to_upper() + " : +" + str(item.bonus_stats[stat_type].flat_bonus_value)
	else:
		tooltip_text = ""

func _on_mouse_exited():
	tooltip_text = ""
	if not is_dragging:
		modulate = Color.WHITE
