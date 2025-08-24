class_name InventoryComponent
extends Node

# Reference to the grid container that holds the slots
@export var inventory_grid: GridContainer
@export var slots: Array[Slot] = []

# Fix 4: Performance optimization - O(1) item lookups
var item_counts: Dictionary = {} # item_name -> total_count
var item_locations: Dictionary = {} # item_name -> Array[Slot]

func _ready() -> void:
	await get_tree().process_frame

	# If slots array is empty, try to get them from the grid
	if slots.is_empty() and inventory_grid:
		var grid_children = inventory_grid.get_children()
		for child in grid_children:
			if child is Slot:
				slots.append(child)

	# Set up each slot with this inventory reference
	for slot in slots:
		if slot.has_method("set_inventory"):
			slot.set_inventory(self)
		slot.add_to_group("inventory_slots")

	# Add some test items
	for x in range(20):
		add_item(load("res://resources/Items/Potion.tres"))

	# Build initial item tracking
	_rebuild_item_tracking()

# Alternative setup method for when you need to set slots manually
func setup_slots(slot_array: Array[Slot]):
	slots = slot_array
	for slot in slots:
		if slot.has_method("set_inventory"):
			slot.set_inventory(self)
		slot.add_to_group("inventory_slots")
	_rebuild_item_tracking()

# Fix 4: Rebuild item tracking dictionaries
func _rebuild_item_tracking():
	item_counts.clear()
	item_locations.clear()

	for slot in slots:
		if slot.item != null:
			var item_name = slot.item.name
			var stack_amount = slot.item.current_stack_amount

			# Update count
			if item_name in item_counts:
				item_counts[item_name] += stack_amount
			else:
				item_counts[item_name] = stack_amount

			# Update locations
			if item_name in item_locations:
				item_locations[item_name].append(slot)
			else:
				item_locations[item_name] = [slot]

# Fix 4: Update tracking when items change
func _update_item_tracking(slot: Slot, old_item: Item, new_item: Item):
	# Remove old item from tracking
	if old_item != null:
		var old_name = old_item.name
		if old_name in item_counts:
			item_counts[old_name] -= old_item.current_stack_amount
			if item_counts[old_name] <= 0:
				item_counts.erase(old_name)

		if old_name in item_locations:
			item_locations[old_name].erase(slot)
			if item_locations[old_name].is_empty():
				item_locations.erase(old_name)

	# Add new item to tracking
	if new_item != null:
		var new_name = new_item.name
		var stack_amount = new_item.current_stack_amount

		if new_name in item_counts:
			item_counts[new_name] += stack_amount
		else:
			item_counts[new_name] = stack_amount

		if new_name in item_locations:
			if slot not in item_locations[new_name]:
							item_locations[new_name].append(slot)
		else:
			item_locations[new_name] = [slot]

func add_item(item: Item):
	var original_item = item.duplicate()

	# First try to add to existing stacks using optimized lookup
	var item_name = item.name
	if item_name in item_locations and item.can_stack:
		var existing_slots = item_locations[item_name]
		for slot in existing_slots:
			if slot.can_add_to_stack(item):
				var space_left = slot.get_remaining_space()
				if space_left > 0:
					var amount_to_add = min(item.current_stack_amount, space_left)
					var old_amount = slot.item.current_stack_amount
					slot.add_to_stack(amount_to_add)
					item.current_stack_amount -= amount_to_add

					# Update tracking
					item_counts[item_name] += amount_to_add

					if item.current_stack_amount <= 0:
						return

	# If we still have items, find empty slots
	for slot in slots:
		if slot.item == null:
			slot.item = original_item.duplicate()
			slot.item.current_stack_amount = item.current_stack_amount
			slot._update_display()

			# Update tracking
			_update_item_tracking(slot, null, slot.item)
			return

	print("Can't add any more items")

func remove_item(item: Item):
	for slot in slots:
		if slot.item == item:
			var old_item = slot.item
			slot.item = null
			slot._update_display()
			_update_item_tracking(slot, old_item, null)
			return
	print("Item not found")

func remove_item_from_stack(item: Item, amount: int = 1):
	for slot in slots:
		if slot.item == item:
			var old_amount = slot.item.current_stack_amount
			var removed = slot.remove_from_stack(amount)

			# Update tracking
			if item.name in item_counts:
				item_counts[item.name] -= removed
				if item_counts[item.name] <= 0:
					item_counts.erase(item.name)
					if item.name in item_locations:
						item_locations[item.name].erase(slot)
						if item_locations[item.name].is_empty():
							item_locations.erase(item.name)

			if slot.item.current_stack_amount <= 0:
				var old_item = slot.item
				slot.item = null
				_update_item_tracking(slot, old_item, null)

			return removed
	print("Item not found")
	return 0

# Fix 4: O(1) item count lookup
func get_item_count(item_name: String) -> int:
	return item_counts.get(item_name, 0)

func has_item(item_name: String, amount: int = 1) -> bool:
	return get_item_count(item_name) >= amount

# Fix 4: O(1) item lookup
func get_item_by_name(item_name: String) -> Item:
	if item_name in item_locations:
		var slots_with_item = item_locations[item_name]
		if not slots_with_item.is_empty():
			return slots_with_item[0].item
	return null

func get_empty_slots() -> Array[Slot]:
	var empty_slots: Array[Slot] = []
	for slot in slots:
		if slot.item == null:
			empty_slots.append(slot)
	return empty_slots

func split_stack(slot: Slot, amount: int) -> bool:
	if not slot.item or not slot.item.can_stack or slot.item.current_stack_amount <= 1:
		return false

	if amount >= slot.item.current_stack_amount:
		return false

	# Find an empty slot for the split
	var empty_slots = get_empty_slots()
	if empty_slots.is_empty():
		return false

	var target_slot = empty_slots[0]

	# Create a copy of the item with the split amount
	var split_item = slot.item.duplicate()
	split_item.current_stack_amount = amount
	target_slot.item = split_item
	target_slot._update_display()

	# Reduce the original stack
	var old_amount = slot.item.current_stack_amount
	slot.remove_from_stack(amount)

	# Update tracking for both slots
	_update_item_tracking(target_slot, null, split_item)

	return true

# Get all slots in this inventory
func get_slots() -> Array[Slot]:
	return slots

# Check if this inventory is full
func is_full() -> bool:
	return get_empty_slots().is_empty()

# Get the total number of items in this inventory
func get_total_items() -> int:
	var total = 0
	for count in item_counts.values():
		total += count
	return total

# Fix 4: Get all items of a specific type (optimized)
func get_all_items_of_type(item_name: String) -> Array[Slot]:
	return item_locations.get(item_name, [])

# Utility method to refresh tracking if needed
func refresh_item_tracking():
	_rebuild_item_tracking()

# Debug method to print current tracking state
func debug_print_tracking():
	print("Item counts: ", item_counts)
	print("Item locations: ", item_locations.keys())
