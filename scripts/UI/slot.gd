extends PanelContainer
class_name Slot

const RARITY_COLORS = {
	0: Color("ffffff"), # Common (White)
	1: Color("00ff00"), # Uncommon (Green)
	2: Color("0000ff"), # Rare (Blue)
	3: Color("ff00ff"), # Epic (Purple)
	4: Color("ff8000"), # Legendary (Orange)
}

const PANEL_STYLEBOX_THEME: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

@onready var texture_rect: TextureRect = $TextureRect
@onready var label: Label = $Label

# This can be an InventoryComponent, EquipmentComponent, or any other Node that manages slots.
var item_container: Node = null

@export var allowed_item_type: Constants.ItemType = Constants.ItemType.ANY

@export var item: ItemData = null:
	set(value):
		item = value
		update_display()

# Drag state variables
var is_dragging: bool = false
var drag_item: ItemData = null
var drag_amount: int = 0

var _custom_tooltip_theme: Theme = null # Declare as instance variable


func update_display():
		if item != null:
			texture_rect.texture = ResourceManager.get_item_data(item.item_id).icon		
			if item.can_stack and item.current_stack_amount > 1:
				label.text = str(item.current_stack_amount)
				label.visible = true
			else:
				label.visible = false
			# Ensure the panel is visible when there's an item
			add_theme_stylebox_override("panel", get_theme_stylebox("panel")) # Reapply default panel
		else:
			texture_rect.texture = null
			label.visible = false
		# Hide the panel when there's no item
			remove_theme_stylebox_override("panel")
		texture_rect.queue_redraw()
		label.queue_redraw()


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
		# Use transfer_item_clientside for all moves (it handles validation and sync)
		successful_operation = source_container.transfer_item_clientside(source_slot, self)
	
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
			# Check if we should create a dropped item instead of restoring
			if _should_create_dropped_item():
				_create_dropped_item()
			else:
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
	drag_item = item.duplicate_with_path()
	drag_amount = item.current_stack_amount

	set_drag_preview(get_preview())
	return self


func restore_drag_to_source():
	"""Restore dragged items back to this slot"""
	if drag_item != null and drag_amount > 0:
		# Restore the entire item
		item = drag_item.duplicate_with_path()
		item.current_stack_amount = drag_amount
		update_display()


func cancel_drag():
	is_dragging = false
	drag_item = null
	drag_amount = 0


func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			if is_dragging:
				# Abort any drag with a right click
				# The NOTIFICATION_DRAG_END will handle the restoration
				get_viewport().gui_release_focus()
				return


func _ready():
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	_custom_tooltip_theme = Theme.new()
	
	# Get the default PanelContainer stylebox from the editor's theme (or current scene's theme)
	# and set it as the default "panel" style for the Slot itself within _custom_tooltip_theme.
	var default_panel_stylebox = get_theme_stylebox("panel", "PanelContainer")
	if default_panel_stylebox:
		_custom_tooltip_theme.set_stylebox("panel", "PanelContainer", default_panel_stylebox)
		# Also set it as the generic "panel" style for the control itself
		_custom_tooltip_theme.set_stylebox("panel", "", default_panel_stylebox) # This is the key!
	
	_custom_tooltip_theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX_THEME)
	
	self.theme = _custom_tooltip_theme # Apply the custom theme to the slot itself for tooltip styling
	update_display() # Call update_display to ensure correct initial state


func can_accept_item(item_to_check: ItemData) -> bool:
	if not item_to_check:
		return true # Can always accept nothing (clearing a slot)

	if allowed_item_type != Constants.ItemType.ANY and item_to_check.item_type != allowed_item_type:
		return false

	return true


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
		
		# Set tooltip border color based on rarity
		var rarity_color: Color = Color.WHITE # Default to white
		var found_rarity = false

		if item.has_method("get_rarity"):
			var rarity = item.get_rarity()
			if RARITY_COLORS.has(rarity):
				rarity_color = RARITY_COLORS[rarity]
				found_rarity = true
		elif typeof(item.rarity) == TYPE_INT: # Check for rarity property directly
			var rarity = item.rarity
			if RARITY_COLORS.has(rarity):
				rarity_color = RARITY_COLORS[rarity]
				found_rarity = true
		
		if found_rarity:
			var new_stylebox = PANEL_STYLEBOX_THEME.duplicate()
			new_stylebox.border_color = rarity_color
			_custom_tooltip_theme.set_stylebox("panel", "TooltipPanel", new_stylebox)
			self.theme = _custom_tooltip_theme # Reapply the theme to update the tooltip
		else:
			# Reset to default tooltip style if rarity not found
			_custom_tooltip_theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX_THEME)
			self.theme = _custom_tooltip_theme
	else:
		tooltip_text = ""
		# Reset to default tooltip style when no item
		_custom_tooltip_theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX_THEME)
		self.theme = _custom_tooltip_theme


func _on_mouse_exited():
	tooltip_text = ""
	# Reset tooltip style to default
	_custom_tooltip_theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX_THEME)
	self.theme = _custom_tooltip_theme
	if not is_dragging:
		modulate = Color.WHITE


func _should_create_dropped_item() -> bool:
	# Check if we're dragging and the mouse is outside of any UI windows
	if not is_dragging or not drag_item:
		return false
	
	# Get the current mouse position
	var mouse_pos = get_global_mouse_position()
	
	# Check if mouse is outside of all UI windows
	var ui_windows = get_tree().get_nodes_in_group("ui_window")
	for window in ui_windows:
		if window.visible and window.get_global_rect().has_point(mouse_pos):
			return false
	
	# If we're here, the mouse is outside all UI windows
	return true


func _create_dropped_item():
	if not drag_item:
		return
	
	# Find the global drop handler
	var drop_handler = get_tree().get_first_node_in_group("global_drop_handler")
	if not drop_handler:
		# Try to find it by name
		drop_handler = get_tree().get_first_node_in_group("drop_handler")
	
	if drop_handler and drop_handler.has_method("create_dropped_item"):
		# Find the player to target the dropped item
		var player = _get_local_player()
		if player:
			# Use player's position instead of mouse position
			var world_pos = player.global_position
			drop_handler.create_dropped_item(drag_item, drag_amount, world_pos)
			
			# Remove the item from the inventory
			_remove_item_from_inventory()
		else:
			print("Slot: Could not find local player for dropped item")
	else:
		print("Slot: Could not find global drop handler")


func _get_local_player() -> Node:
	# Find the local player
	var players = get_tree().get_nodes_in_group("Players")
	for player in players:
		if player.has_method("is_local_player") and player.is_local_player():
			return player
		# Fallback: check player_id if available
		if "player_id" in player and multiplayer.get_unique_id() == player.player_id:
			return player
	return null


func _remove_item_from_inventory():
	# Use the proper RPC system to remove the item
	if item_container:
		if item_container is InventoryComponent:
			# Call through the inventory system which will handle sync
			item_container.clear_slot(self)
		elif item_container.has_method("clear_slot"):
			item_container.clear_slot(self)
		else:
			# Fallback
			item = null
			update_display()
	else:
		# Fallback
		item = null
		update_display()
