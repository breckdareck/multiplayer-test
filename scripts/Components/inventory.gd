class_name InventoryComponent
extends Node

signal inventory_changed(inventory: InventoryComponent)
signal item_added(item: ItemData)
signal item_removed(item: ItemData, reason: String)
signal inventory_saved(inventory: InventoryComponent)

@export var inventory_grids: Array[GridContainer]
@export var equipment_component: EquipmentComponent
@export var stats_component: StatsComponent


var slots: Array[Slot] = []
# Component-owned data model, kept 1:1 and in index order with `slots`. The
# item data lives here; the Slot nodes are views bound to these entries.
var slots_data: Array[SlotData] = []
var item_counts: Dictionary = {} # item_id -> total_count
var item_locations: Dictionary = {} # item_id -> Array[Slot]

var pending_moves: Dictionary = {}
var pending_splits: Dictionary = {}
var pending_transfers: Dictionary = {}
var pending_inventory_data: Dictionary = {}

# Optional multiplayer configuration - set by wrapper
var enable_multiplayer_sync: bool = true
var owner_id: int = -1


func format_number_with_commas(number: int) -> String:
	var num_str: String = str(abs(number))
	var result: String = ""
	var count: int = 0

	for i in range(num_str.length() - 1, -1, -1):
		result = num_str[i] + result
		count += 1
		if count % 3 == 0 and i != 0:
			result = "," + result
	
	if number < 0:
		result = "-" + result
		
	return result


func _notify_changed() -> void:
	inventory_saved.emit(self)


func _ready() -> void:
	if not multiplayer.is_server():
		return
	await _ensure_slots_initialized()
	
	_rebuild_item_tracking()
	
	if not pending_inventory_data.is_empty():
		#print("Applying pending inventory data")
		_apply_inventory_data(pending_inventory_data)
		pending_inventory_data.clear()


func _ensure_slots_initialized() -> void:
	if not is_inside_tree():
		await tree_entered
	await get_tree().process_frame
	if slots.is_empty() and not inventory_grids.is_empty():
		for grid in inventory_grids:
			for child in grid.get_children():
				if child is Slot:
					slots.append(child)

	for slot in slots:
		if slot.has_method("set_inventory"):
			slot.set_inventory(self)
		slot.add_to_group("inventory_slots")

	_build_slot_data()


func setup_slots(slot_array: Array[Slot]):
	slots = slot_array
	for slot in slots:
		if slot.has_method("set_inventory"):
			slot.set_inventory(self)
		slot.add_to_group("inventory_slots")
	_build_slot_data()
	_rebuild_item_tracking()


## Creates one SlotData per UI slot (in index order) and binds them. After this
## the data model lives in the component; the Slot nodes are pure views.
func _build_slot_data() -> void:
	if not slots_data.is_empty():
		return
	for i in slots.size():
		var data := SlotData.new()
		data.container_kind = SlotData.CONTAINER_INVENTORY
		data.index = i
		data.key = i
		data.allowed_item_type = slots[i].allowed_item_type
		slots_data.append(data)
		slots[i].bind_slot_data(data)


func _rebuild_item_tracking():
	item_counts.clear()
	item_locations.clear()

	var all_slots = get_all_slots()
	for slot in all_slots:
		if slot.item != null:
			var item_instance_id = slot.item.item_id
			var stack_amount = slot.item.current_stack_amount

			if item_instance_id in item_counts:
				item_counts[item_instance_id] += stack_amount
			else:
				item_counts[item_instance_id] = stack_amount

			if item_instance_id in item_locations:
				item_locations[item_instance_id].append(slot)
			else:
				item_locations[item_instance_id] = [slot]


## `slot` is untyped — it accepts a Slot view (current callers) or a SlotData
## (component-driven callers from Stage 2b). It is only used as a collection key.
func _update_item_tracking(slot, old_item: ItemData, new_item: ItemData):
	if old_item != null:
		var old_instance_id = old_item.item_id
		if old_instance_id in item_counts:
			item_counts[old_instance_id] -= old_item.current_stack_amount
			if item_counts[old_instance_id] <= 0:
				item_counts.erase(old_instance_id)

		if old_instance_id in item_locations:
			item_locations[old_instance_id].erase(slot)
			if item_locations[old_instance_id].is_empty():
				item_locations.erase(old_instance_id)

	if new_item != null:
		var new_instance_id = new_item.item_id
		var stack_amount = new_item.current_stack_amount

		if new_instance_id in item_counts:
			item_counts[new_instance_id] += stack_amount
		else:
			item_counts[new_instance_id] = stack_amount

		if new_instance_id in item_locations:
			if slot not in item_locations[new_instance_id]:
				item_locations[new_instance_id].append(slot)
		else:
			item_locations[new_instance_id] = [slot]


func _get_slot_index(slot: Slot) -> int:
	"""Get the index of a slot in the slots array, or -1 if not found"""
	return slots.find(slot)


## Refreshes the UI view bound to an inventory slot index, if one exists.
## No-op on a headless bot scene (no inventory window).
func _refresh_view(index: int) -> void:
	if index >= 0 and index < slots.size() and is_instance_valid(slots[index]):
		slots[index].update_display()


## Sets a SlotData's item, updates tracking, and refreshes its bound view.
## The single mutation entry point for component-driven inventory changes.
func _apply_item(sd: SlotData, new_item: ItemData) -> void:
	var old_item: ItemData = sd.item
	sd.item = new_item
	_update_item_tracking(sd, old_item, new_item)
	_refresh_view(sd.index)


## Sets an equipment SlotData's item and refreshes its bound view.
func _apply_equipment_item(key, new_item: ItemData) -> void:
	if not is_instance_valid(equipment_component):
		return
	var sd: SlotData = equipment_component.get_slot_data(key)
	if sd == null:
		return
	sd.item = new_item
	equipment_component.refresh_view(key)


## Refreshes whichever view (inventory or equipment) is bound to a SlotData.
func _refresh_slot_data_view(sd: SlotData) -> void:
	if sd.container_kind == SlotData.CONTAINER_EQUIPMENT:
		if is_instance_valid(equipment_component):
			equipment_component.refresh_view(sd.key)
	else:
		_refresh_view(sd.index)


## Swaps the items of two slots (inventory and/or equipment). UI-independent —
## the entry point bot equip logic uses, since a bot has no Slot views to drive
## a normal drag-and-drop transfer.
func swap_slot_data(from_sd: SlotData, to_sd: SlotData) -> void:
	if from_sd == null or to_sd == null:
		return

	var from_item := from_sd.item
	var to_item := to_sd.item
	from_sd.item = to_item
	to_sd.item = from_item

	_update_item_tracking(from_sd, from_item, to_item)
	_update_item_tracking(to_sd, to_item, from_item)

	_refresh_slot_data_view(from_sd)
	_refresh_slot_data_view(to_sd)

	var from_is_equipment := from_sd.container_kind == SlotData.CONTAINER_EQUIPMENT
	var to_is_equipment := to_sd.container_kind == SlotData.CONTAINER_EQUIPMENT

	# An equipment change drives the stats-recalc / save signal chain.
	if (from_is_equipment or to_is_equipment) and is_instance_valid(equipment_component):
		equipment_component.mark_changed()

	if multiplayer.is_server():
		if from_is_equipment:
			_sync_equipment_slot_to_client(from_sd, true)
		else:
			_sync_slot_to_client(from_sd, false)
		if to_is_equipment:
			_sync_equipment_slot_to_client(to_sd, true)
		else:
			_sync_slot_to_client(to_sd, false)

	_notify_changed()


func _sync_slot_to_client(sd: SlotData, trigger_stats_recalc: bool = false):
	"""Send a single slot update to the client"""
	if not enable_multiplayer_sync or owner_id <= 0 or not multiplayer.is_server():
		return

	if sd == null or sd.index < 0:
		return

	if sd.item != null:
		sync_slot_update_rpc.rpc_id(owner_id, sd.index, sd.item.to_dictionary(), trigger_stats_recalc)
	else:
		sync_slot_clear_rpc.rpc_id(owner_id, sd.index, trigger_stats_recalc)


@rpc("authority", "call_local", "reliable")
func sync_slot_update_rpc(slot_index: int, item_dict: Dictionary, trigger_stats_recalc: bool):
	"""Client receives a single slot update"""
	if multiplayer.is_server():
		return
	
	if slot_index < 0 or slot_index >= slots.size():
		return
	
	var slot = slots[slot_index]
	var old_item = slot.item
	
	var item_instance = ItemData.from_dictionary(item_dict)
	if item_instance:
		slot.item = item_instance
		slot.update_display()
			# Trigger stats recalc if needed (equipment change)
		if trigger_stats_recalc:
			if is_instance_valid(stats_component):
				stats_component._recalculate_stats_client()

@rpc("authority", "call_local", "reliable")
func sync_slot_clear_rpc(slot_index: int, trigger_stats_recalc: bool):
	"""Client receives notification that a slot was cleared"""
	if multiplayer.is_server():
		return
	
	if slot_index < 0 or slot_index >= slots.size():
		return
	
	var slot = slots[slot_index]
	var old_item = slot.item
	slot.item = null
	slot.update_display()
	_update_item_tracking(slot, old_item, null)
	
	# Trigger stats recalc if needed (equipment change)
	if trigger_stats_recalc:
		if is_instance_valid(stats_component):
			stats_component._recalculate_stats_client()


@rpc("any_peer", "call_local", "reliable")
func server_add_item(item_id: String):
	if not multiplayer.is_server():
		return
	var original_item: ItemData = ResourceManager.get_item_data(item_id).duplicate_with_path()
	var original_item_id = original_item.item_id

	# Try to stack with existing items in valid slots
	if original_item_id in item_locations and original_item.can_stack:
		var existing_slots: Array = item_locations[original_item_id]
		for sd in existing_slots:
			if not sd.can_accept_item(original_item):
				continue

			if sd.can_add_to_stack(original_item):
				var space_left = sd.get_remaining_space()
				if space_left > 0:
					var amount_to_add = min(original_item.current_stack_amount, space_left)
					sd.add_to_stack(amount_to_add)
					original_item.current_stack_amount -= amount_to_add
					item_counts[original_item_id] += amount_to_add
					_refresh_view(sd.index)

					# Only sync this one slot
					_sync_slot_to_client(sd)
					_notify_changed()

					if original_item.current_stack_amount <= 0:
						item_added.emit(original_item)
						return
	# Find a valid empty slot
	for sd in slots_data:
		if sd.item == null and sd.can_accept_item(original_item):
			var new_item: ItemData = original_item.duplicate_with_path()
			new_item.current_stack_amount = original_item.current_stack_amount
			_apply_item(sd, new_item)

			# Only sync this one slot
			_sync_slot_to_client(sd)
			_notify_changed()
			item_added.emit(original_item)
			return

	#print("Inventory is full or no suitable slot found for this item type.")


@rpc("any_peer", "call_local", "reliable")
func server_add_item_instance(item_dict: Dictionary):
	if not multiplayer.is_server():
		return
	
	var original_item: ItemData = ItemData.from_dictionary(item_dict)
	if not original_item:
		#print("Failed to create ItemData from dictionary in server_add_item_instance")
		return

	var original_item_id = original_item.item_id
	
	# Try to stack with existing items in valid slots
	if original_item_id in item_locations and original_item.can_stack:
		var existing_slots: Array = item_locations[original_item_id]
		for sd in existing_slots:
			if not sd.can_accept_item(original_item):
				continue

			if sd.can_add_to_stack(original_item):
				var space_left = sd.get_remaining_space()
				if space_left > 0:
					var amount_to_add = min(original_item.current_stack_amount, space_left)
					sd.add_to_stack(amount_to_add)
					original_item.current_stack_amount -= amount_to_add
					item_counts[original_item_id] += amount_to_add
					_refresh_view(sd.index)
					_notify_changed()
					
					if original_item.current_stack_amount <= 0:
						item_added.emit(original_item)
						return
						
	# Find a valid empty slot
	for sd in slots_data:
		if sd.item == null and sd.can_accept_item(original_item):
			var new_item: ItemData = original_item.duplicate_with_path()
			new_item.current_stack_amount = original_item.current_stack_amount
			_apply_item(sd, new_item)

			# Only sync this one slot
			_sync_slot_to_client(sd)
			_notify_changed()
			item_added.emit(original_item)
			return

	#print("Inventory is full or no suitable slot found for this item type.")


func add_item(item_id: String):
	if multiplayer.is_server():
		server_add_item(item_id)
	else:
		server_add_item.rpc_id(1, item_id)


## `reason` describes why the item left (e.g. "sold", "traded", "dropped",
## "used") and is forwarded on the item_removed signal for logging.
func remove_item(item: ItemData, reason: String = "removed"):
	for sd in slots_data:
		if sd.item == item:
			var old_item = sd.item
			_apply_item(sd, null)
			item_removed.emit(old_item, reason)

			# Only sync this one slot
			_sync_slot_to_client(sd)
			_notify_changed()
			return
	#print("Item not found")


func remove_item_from_stack(item: ItemData, amount: int = 1, reason: String = "removed"):
	for sd in slots_data:
		if sd.item == item:
			var removed = sd.remove_from_stack(amount)

			if item.item_id in item_counts:
				item_counts[item.item_id] -= removed
				if item_counts[item.item_id] <= 0:
					item_counts.erase(item.item_id)
					if item.item_id in item_locations:
						item_locations[item.item_id].erase(sd)
						if item_locations[item.item_id].is_empty():
							item_locations.erase(item.item_id)

			if sd.item.current_stack_amount <= 0:
				var old_item = sd.item
				_apply_item(sd, null)
				item_removed.emit(old_item, reason)
			else:
				_refresh_view(sd.index)

			# Only sync this one slot
			_sync_slot_to_client(sd)
			_notify_changed()
			return removed
	#print("Item not found")
	return 0


func clear_slot(slot: Slot, reason: String = "removed"):
	"""Clear a specific slot and update tracking"""
	if slot in slots:
		var sd: SlotData = slot.slot_data
		var old_item = sd.item
		_apply_item(sd, null)
		if old_item:
			item_removed.emit(old_item, reason)

		# Only sync this one slot
		_sync_slot_to_client(sd)
		_notify_changed()
	else:
		print("Slot not found in inventory")


func get_item_count(item_id: String) -> int:
	return item_counts.get(item_id, 0)


func has_item(item_id: String, amount: int = 1) -> bool:
	return get_item_count(item_id) >= amount


func get_item_by_id(item_id: String) -> ItemData:
	if item_id in item_locations:
		var slots_with_item = item_locations[item_id]
		if not slots_with_item.is_empty():
			return slots_with_item[0].item
	return null


func get_empty_slots() -> Array[SlotData]:
	var empty_slots: Array[SlotData] = []
	for sd in slots_data:
		if sd.item == null:
			empty_slots.append(sd)
	return empty_slots


func get_slots() -> Array[SlotData]:
	return slots_data


func get_all_slots() -> Array:
	var all_slots: Array = slots_data.duplicate()
	if equipment_component:
		all_slots.append_array(equipment_component.get_all_slot_data())
	return all_slots


func is_full() -> bool:
	return get_empty_slots().is_empty()


## Whether `item` could actually be placed — merged into an existing partial
## stack, or dropped into a valid empty slot. Mirrors the placement logic of
## `server_add_item_instance` so callers can gate before handing an item over.
func can_accept_item(item: ItemData) -> bool:
	if item == null:
		return false
	# A stackable item with room left in an existing valid stack fits.
	if item.can_stack and item.item_id in item_locations:
		for sd in item_locations[item.item_id]:
			if sd.can_accept_item(item) and sd.can_add_to_stack(item) and sd.get_remaining_space() > 0:
				return true
	# Otherwise it needs an empty slot that accepts this item type.
	for sd in slots_data:
		if sd.item == null and sd.can_accept_item(item):
			return true
	return false


func get_total_items() -> int:
	var total = 0
	for count in item_counts.values():
		total += count
	return total


func get_all_items_of_id(item_id: String) -> Array:
	return item_locations.get(item_id, [])


func save_inventory() -> Dictionary:
	var inventory_data = {}
	var slot_entries = []

	for i in range(slots_data.size()):
		var sd: SlotData = slots_data[i]
		if sd.item != null:
			slot_entries.append({
				"slot_index": i,
				"item_data": sd.item.get_save_data()
			})

	var equipment_data: Dictionary = {}
	if equipment_component:
		for eq_key in equipment_component.slots_data.keys():
			var eq_sd: SlotData = equipment_component.slots_data[eq_key]
			if eq_sd and eq_sd.item != null:
				equipment_data[str(eq_key)] = eq_sd.item.get_save_data()

	inventory_data["slots"] = slot_entries
	inventory_data["equipment"] = equipment_data
	return inventory_data


func _apply_inventory_data(inventory_data: Dictionary) -> void:
	# Clear existing inventory (cancel any in-progress drag on the views first)
	for view in slots:
		if is_instance_valid(view):
			view.cancel_drag()
	for sd in slots_data:
		sd.item = null
		_refresh_view(sd.index)

	# Clear existing equipment items
	if equipment_component:
		for view in equipment_component.get_slots():
			if is_instance_valid(view):
				view.cancel_drag()
		for eq_key in equipment_component.slots_data.keys():
			equipment_component.slots_data[eq_key].item = null
			equipment_component.refresh_view(eq_key)

	# Load saved items
	var slot_entries = inventory_data.get("slots", [])
	for entry in slot_entries:
		var slot_index = entry.get("slot_index", -1)
		var item_dict = entry.get("item_data", {})

		if slot_index >= 0 and slot_index < slots_data.size() and not item_dict.is_empty():
			var item_instance = ItemData.from_dictionary(item_dict)
			if item_instance:
				slots_data[slot_index].item = item_instance
				_refresh_view(slot_index)
			else:
				print("Failed to load item from dictionary: " + str(item_dict))

	# Load equipment items
	if equipment_component:
		var equipment_data_dict: Dictionary = inventory_data.get("equipment", {})
		for key_str in equipment_data_dict.keys():
			var item_dict: Dictionary = equipment_data_dict[key_str]
			if item_dict.is_empty():
				continue
			var key = "WEAPON" if key_str == "WEAPON" else int(key_str)
			var target_sd: SlotData = equipment_component.get_slot_data(key)
			if target_sd:
				var item_instance = ItemData.from_dictionary(item_dict)
				if item_instance:
					target_sd.item = item_instance
					equipment_component.refresh_view(key)
				else:
					print("Failed to load equipment item from dictionary: " + str(item_dict))

	_rebuild_item_tracking()

	# After loading equipment on the server, sync it to the client
	if multiplayer.is_server() and owner_id > 0 and equipment_component:
		for eq_key in equipment_component.slots_data.keys():
			var eq_sd: SlotData = equipment_component.slots_data[eq_key]
			if eq_sd and eq_sd.item != null:
				_sync_equipment_slot_to_client(eq_sd, true)


func load_inventory(inventory_data: Dictionary) -> void:
	if not is_inside_tree():
		pending_inventory_data = inventory_data
		return
	
	if equipment_component:
		equipment_component.set_silent_mode(true)
	
	_apply_inventory_data(inventory_data)
	
	if equipment_component:
		equipment_component.set_silent_mode(false)


@rpc("authority", "call_local", "reliable")
func load_inventory_rpc(inventory_data: Dictionary):
	"""Full inventory sync - only used for initial load or corrections"""
	#print("Client %s received full inventory data" % str(multiplayer.get_unique_id()))
	
	if not is_inside_tree():
		pending_inventory_data = inventory_data
		return
	
	await _ensure_slots_initialized()
	
	if equipment_component:
		equipment_component.set_silent_mode(true)
	
	_apply_inventory_data(inventory_data)
	
	if equipment_component:
		equipment_component.set_silent_mode(false)
		
	if not multiplayer.is_server():
		if is_instance_valid(stats_component):
			stats_component._recalculate_stats_client()

func transfer_item_clientside(from_slot: Slot, to_slot: Slot) -> bool:
	var from_path: NodePath = get_path_to(from_slot)
	var to_path: NodePath = get_path_to(to_slot)

	# 1. Always run client-side validation for instant feedback.
	if not _is_move_valid(from_slot, to_slot):
		#print("[CLIENT] Move invalid.")
		return false

	# 2. Set up the backup state for rollbacks
	var backup_state = {
		"from_item": from_slot.item.duplicate_with_path() if from_slot.item else null,
		"to_item": to_slot.item.duplicate_with_path() if to_slot.item else null,
		"from_slot_path": from_path,
		"to_slot_path": to_path
	}
	pending_transfers[from_path] = backup_state

	if not multiplayer.is_server():
		_execute_swap_local(from_slot, to_slot)

	# 4. Handle network or local execution
	if multiplayer.has_multiplayer_peer():
		var my_id = multiplayer.get_unique_id()
		request_transfer_item.rpc_id(1, from_path, to_path, my_id)
	else:
		if multiplayer.is_server():
			_execute_swap_local(from_slot, to_slot)
		
		# No RPC was sent, so clear the pending transfer.
		pending_transfers.erase(from_path)
	
	return true


func _execute_swap_local(from_slot: Slot, to_slot: Slot):
	var from_item = from_slot.item
	var to_item = to_slot.item

	from_slot.item = to_item
	to_slot.item = from_item

	_update_item_tracking(from_slot.slot_data, from_item, to_item)
	_update_item_tracking(to_slot.slot_data, to_item, from_item)

	from_slot.update_display()
	to_slot.update_display()

	# Check if these are equipment slots
	var from_is_equipment = _is_equipment_slot(from_slot)
	var to_is_equipment = _is_equipment_slot(to_slot)
	var involves_equipment = from_is_equipment or to_is_equipment

	# If on server, sync the changed slots to client
	if multiplayer.is_server():
		# Sync slots - only trigger stats recalc if the slot itself is an equipment slot
		if from_is_equipment:
			_sync_equipment_slot_to_client(from_slot.slot_data, true)
		else:
			_sync_slot_to_client(from_slot.slot_data, false)

		if to_is_equipment:
			_sync_equipment_slot_to_client(to_slot.slot_data, true)
		else:
			_sync_slot_to_client(to_slot.slot_data, false)


func _is_move_valid(from_slot: Slot, to_slot: Slot) -> bool:
	if from_slot.item == null:
		#print("[INV][VALIDATE] from_slot has no item")
		return false
	
	if to_slot.has_method("can_accept_item") and not to_slot.can_accept_item(from_slot.item):
		#print("[INV][VALIDATE] to_slot cannot accept item '%s'" % from_slot.item.name)
		return false
	
	return true


func _is_equipment_slot(slot: Slot) -> bool:
	"""Check if a slot is an equipment slot"""
	if not equipment_component:
		return false
	
	# Equipment slots have the equipment component as their container
	return slot.item_container == equipment_component


@rpc("any_peer", "call_local", "reliable")
func request_transfer_item(from_slot_path: NodePath, to_slot_path: NodePath, requesting_owner_id: int):
	if not multiplayer.is_server():
		return

	if owner_id > 0 and owner_id != requesting_owner_id:
		send_inventory_correction.rpc_id(requesting_owner_id)
		return

	if slots.is_empty():
		await _ensure_slots_initialized()

	var from_slot = get_node_or_null(from_slot_path)
	var to_slot = get_node_or_null(to_slot_path)

	if not from_slot or not to_slot:
		send_inventory_correction.rpc_id(requesting_owner_id)
		return

	if not _is_move_valid(from_slot, to_slot):
		send_inventory_correction.rpc_id(requesting_owner_id)
		return


	# Check if this involves equipment slots (needs stats recalc)
	var from_is_equipment = _is_equipment_slot(from_slot)
	var to_is_equipment = _is_equipment_slot(to_slot)

	_execute_swap_local(from_slot, to_slot)
	_notify_changed()

	# Send individual slot updates instead of full inventory
	confirm_transfer_item.rpc_id(requesting_owner_id, from_slot_path, to_slot_path, true, from_is_equipment, to_is_equipment)

	for peer_id in multiplayer.get_peers():
		if peer_id != requesting_owner_id:
			confirm_transfer_item.rpc_id(peer_id, from_slot_path, to_slot_path, false, from_is_equipment, to_is_equipment)


@rpc("authority", "call_local", "reliable")
func confirm_transfer_item(from_slot_path: NodePath, to_slot_path: NodePath, was_requesting_client: bool, from_is_equipment: bool, to_is_equipment: bool):
	if multiplayer.is_server():
		return

	var from_slot = get_node_or_null(from_slot_path)
	var to_slot = get_node_or_null(to_slot_path)
	
	if not from_slot or not to_slot:
		return

	if was_requesting_client:
		pending_transfers.erase(from_slot_path)
	else:
		_execute_swap_local(from_slot, to_slot)
	
	# Trigger stats recalc if the TO slot is an equipment slot
	if to_is_equipment:
		if is_instance_valid(stats_component):
			stats_component._recalculate_stats_client()


@rpc("authority", "call_local", "reliable")
func send_inventory_correction():
	if not multiplayer.is_server():
		return
		
	#print("Sending inventory correction to client")
	var current_inventory = save_inventory()
	receive_inventory_correction.rpc_id(multiplayer.get_remote_sender_id(), current_inventory)


@rpc("authority", "call_local", "reliable")
func receive_inventory_correction(authoritative_inventory: Dictionary):
	if multiplayer.is_server():
		return
		
	#print("Received inventory correction from server - restoring authoritative state")
	
	pending_moves.clear()
	pending_splits.clear()
	pending_transfers.clear()
	
	_apply_inventory_data(authoritative_inventory)


func sync_full_inventory_to_client() -> void:
	"""Force a full inventory sync - use sparingly (initial load, corrections)"""
	if not multiplayer.is_server() or owner_id <= 0:
		return
		
	var inv_data = save_inventory()
	load_inventory_rpc.rpc_id(owner_id, inv_data)


func _sync_equipment_slot_to_client(sd: SlotData, trigger_stats_recalc: bool = true):
	"""Send an equipment slot update to the client"""
	if not enable_multiplayer_sync or owner_id <= 0 or not multiplayer.is_server():
		return

	if not equipment_component:
		return

	# Find which equipment key this SlotData belongs to
	var eq_key = null
	for key in equipment_component.slots_data.keys():
		if equipment_component.slots_data[key] == sd:
			eq_key = key
			break

	if eq_key == null:
		return

	if sd.item != null:
		sync_equipment_update_rpc.rpc_id(owner_id, str(eq_key), sd.item.to_dictionary(), trigger_stats_recalc)
	else:
		sync_equipment_clear_rpc.rpc_id(owner_id, str(eq_key), trigger_stats_recalc)


@rpc("authority", "call_local", "reliable")
func sync_equipment_update_rpc(eq_key_str: String, item_dict: Dictionary, trigger_stats_recalc: bool):
	"""Client receives an equipment slot update"""
	if multiplayer.is_server():
		return
	
	if not equipment_component:
		return
	
	var target_slot: Slot = null
	if eq_key_str == "WEAPON":
		target_slot = equipment_component.equipment.get("WEAPON")
	else:
		var key_val := int(eq_key_str)
		target_slot = equipment_component.equipment.get(key_val)
	
	if not target_slot:
		return
	
	var old_item = target_slot.item
	var item_instance = ItemData.from_dictionary(item_dict)
	if item_instance:
		# Use silent mode if we're batching multiple equipment changes
		if equipment_component and not trigger_stats_recalc:
			equipment_component.set_silent_mode(true)
		
		target_slot.item = item_instance
		target_slot.update_display()
		_update_item_tracking(target_slot, old_item, item_instance)
		
	# Trigger stats recalc if needed
	if trigger_stats_recalc:
		if is_instance_valid(stats_component):
			stats_component._recalculate_stats_client()


@rpc("authority", "call_local", "reliable")
func sync_equipment_clear_rpc(eq_key_str: String, trigger_stats_recalc: bool):
	"""Client receives notification that an equipment slot was cleared"""
	if multiplayer.is_server():
		return
	
	if not equipment_component:
		return
	
	var target_slot: Slot = null
	if eq_key_str == "WEAPON":
		target_slot = equipment_component.equipment.get("WEAPON")
	else:
		var key_val := int(eq_key_str)
		target_slot = equipment_component.equipment.get(key_val)
	
	if not target_slot:
		return
	
	var old_item = target_slot.item
	
	# Use silent mode if we're batching multiple equipment changes
	if equipment_component and not trigger_stats_recalc:
		equipment_component.set_silent_mode(true)
	
	target_slot.item = null
	target_slot.update_display()
	_update_item_tracking(target_slot, old_item, null)
	
	if equipment_component and not trigger_stats_recalc:
		equipment_component.set_silent_mode(false)
	
	# Trigger stats recalc if needed
	if trigger_stats_recalc:
		if is_instance_valid(stats_component):
			stats_component._recalculate_stats_client()


func load_inventory_silent(inventory_data: Dictionary) -> void:
	if equipment_component:
		equipment_component.set_silent_mode(true)
	
	_apply_inventory_data(inventory_data)
	
	if equipment_component:
		equipment_component.set_silent_mode(false)
	
	# After loading, if this is on the server and we have an owner_id,
	# send the full inventory state to the client ONCE
	if multiplayer.is_server() and enable_multiplayer_sync and owner_id > 0:
		# Use call_deferred to ensure the inventory is fully loaded first
		call_deferred("_initial_sync_to_client")
		
		
func _initial_sync_to_client():
	"""Send initial full inventory state to client after loading"""
	if not multiplayer.is_server() or owner_id <= 0:
		return
	
	var inv_data = save_inventory()
	load_inventory_rpc.rpc_id(owner_id, inv_data)
	#print("Sent initial inventory sync to client %d" % owner_id)


@rpc("any_peer", "call_local", "reliable")
func request_use_item(slot_index: int):
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1  # Local call from host

	# Use PlayerManager to reliably find the player's node across maps
	var player = null
	if PlayerManager:
		player = PlayerManager.get_player_node(sender_id)
	if not player:
		#print("Use Item failed: Player %d not found." % sender_id)
		return

	if slot_index < 0 or slot_index >= slots_data.size():
		#print("Use Item failed: Invalid slot index %d for player %d." % [slot_index, sender_id])
		return

	var sd: SlotData = slots_data[slot_index]
	if not sd.item:
		#print("Use Item failed: No item in slot %d for player %d." % [slot_index, sender_id])
		return

	var item = sd.item
	if not item is ConsumableData:
		#print("Use Item failed: Item '%s' is not a consumable." % item.name)
		return

	var consumable = item as ConsumableData
	if not consumable.effect_script:
		#print("Use Item failed: Consumable '%s' has no effect script. item type=%d, script=%s" % [consumable.name, consumable.item_type, consumable.get_script()])
		return

	# Remove one from the stack and persist before executing the effect,
	# because effects like Town Potion trigger a map change that frees this node.
	remove_item_from_stack(item, 1, "used")

	# Force-save inventory now so map changes don't lose the removal
	if player.username and SaveManager:
		SaveManager.queue_save(player.username, "inventory", player)
		await SaveManager.flush_save(player.username)

	# Execute the effect (must happen after save completes, as effects like
	# Town Potion trigger a map change that frees this node and reloads from save)
	if not is_instance_valid(player):
		return
	var effect_instance = consumable.effect_script.new() as BaseItemEffect
	effect_instance.user = player
	effect_instance.source_item = consumable
	effect_instance.execute()
