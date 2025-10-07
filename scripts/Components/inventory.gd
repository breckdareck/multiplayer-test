class_name InventoryComponent
extends Node

@export var inventory_grids: Array[GridContainer]
@export var slots: Array[Slot] = []
@export var equipment_component: EquipmentComponent

var item_counts: Dictionary = {} # item_name -> total_count
var item_locations: Dictionary = {} # item_name -> Array[Slot]

var pending_moves: Dictionary = {}
var pending_splits: Dictionary = {}
var pending_transfers: Dictionary = {}

# Buffer for inventory data received before this node enters the scene tree/has slots
var pending_inventory_data: Dictionary = {}



# Notify the owning player on the server that inventory data changed
func _notify_changed() -> void:
	if multiplayer.is_server():
		var player = _get_player()
		if player and player.has_method("_data_changed"):
			player._data_changed()

# Walk up the tree to find the player node that owns this inventory
func _get_player() -> MultiplayerPlayerV2:
	var node: Node = self
	while node:
		if node is MultiplayerPlayerV2:
			return node
		node = node.get_parent()
	return null

func _ready() -> void:
	if not multiplayer.is_server():
		return
	await _ensure_slots_initialized()
	
	# Test code for adding items
	# Get items by name from ResourceManager
	var potion = ResourceManager.get_item_by_name("Grape Potion")
	var coin = ResourceManager.get_item_by_name("Coin")
	var sword = ResourceManager.get_item_by_name("Iron Sword")
	var test_sword_2 = ResourceManager.get_item_by_name("Test Sword 2")
	var test_sword_3 = ResourceManager.get_item_by_name("Test Sword 3")
	var hat = ResourceManager.get_item_by_name("Test Hat")
	var chest = ResourceManager.get_item_by_name("Test Chest")

	# for x in range(10):
	# 	# Make sure to duplicate before adding
	# 	if potion:
	# 		var potion_copy = potion.duplicate_with_path()
	# 		add_item(potion_copy)

	_rebuild_item_tracking()
	
	# If any inventory data was buffered before initialization, apply it now
	if not pending_inventory_data.is_empty():
		print("Pending Inv Data")
		_apply_inventory_data(pending_inventory_data)
		pending_inventory_data.clear()
		
	# Put Add Item here for always gaining Item or 
	# put it before pending so save data is master
	#if sword:
		#var sword_copy = sword.duplicate_with_path()
		#add_item(sword_copy)
		#
	#if test_sword_2:
		#var test_sword_2_copy = test_sword_2.duplicate_with_path()
		#add_item(test_sword_2_copy)
		#
	#if test_sword_3:
		#var test_sword_3_copy = test_sword_3.duplicate_with_path()
		#add_item(test_sword_3_copy)
		#
	#if hat:
		#var hat_copy = hat.duplicate_with_path()
		#add_item(hat_copy)
		#
	#if chest:
		#var chest_copy = chest.duplicate_with_path()
		#add_item(chest_copy)
	
	#for x in range(150):
		#if potion:
			#var potion_copy = potion.duplicate_with_path()
			#add_item(potion_copy)
			#
		#if coin:
			#var coin_copy = coin.duplicate_with_path()
			#add_item(coin_copy)

	# After populating on the server, push the authoritative inventory to the owning client
	# so the client mirrors the server's inventory state immediately.
	var player = _get_player()
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server() and player:
		var inv_data = save_inventory()
		load_inventory_rpc.rpc_id(player.player_id, inv_data)


func _ensure_slots_initialized() -> void:
	# Ensure we're inside the scene tree before accessing it
	if not is_inside_tree():
		await tree_entered
	# If slots array is empty, try to get them from the grid (next frame to allow UI to build)
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


func setup_slots(slot_array: Array[Slot]):
	slots = slot_array
	for slot in slots:
		if slot.has_method("set_inventory"):
			slot.set_inventory(self)
		slot.add_to_group("inventory_slots")
	_rebuild_item_tracking()


func _rebuild_item_tracking():
	item_counts.clear()
	item_locations.clear()

	var all_slots = get_all_slots()
	for slot in all_slots:
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


func _update_item_tracking(slot: Slot, old_item: ItemData, new_item: ItemData):
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


func add_item(item: ItemData):
	var original_item = item.duplicate_with_path()
	var item_name = item.name

	# --- MODIFIED LOGIC: First, try to stack with existing items in valid slots ---
	if item_name in item_locations and item.can_stack:
		var existing_slots = item_locations[item_name]
		for slot in existing_slots:
			# NEW CHECK: Ensure the slot can accept this item type before trying to stack.
			if slot.has_method("can_accept_item") and not slot.can_accept_item(item):
				continue # Skip to the next slot if the type is wrong.

			if slot.can_add_to_stack(item):
				var space_left = slot.get_remaining_space()
				if space_left > 0:
					var amount_to_add = min(item.current_stack_amount, space_left)
					slot.add_to_stack(amount_to_add)
					item.current_stack_amount -= amount_to_add
					item_counts[item_name] += amount_to_add
					if item.current_stack_amount <= 0:
						return
						
	# --- MODIFIED LOGIC: Second, find a valid empty slot ---
	for slot in slots:
		# NEW CHECK: Find an empty slot that can also accept the item's type.
		if slot.item == null and (not slot.has_method("can_accept_item") or slot.can_accept_item(original_item)):
			slot.item = original_item.duplicate_with_path()
			slot.item.current_stack_amount = item.current_stack_amount
			slot.update_display()
			_update_item_tracking(slot, null, slot.item)
			return
			
	print("Inventory is full or no suitable slot found for this item type.")


func remove_item(item: ItemData):
	for slot in slots:
		if slot.item == item:
			var old_item = slot.item
			slot.item = null
			slot.update_display()
			_update_item_tracking(slot, old_item, null)
			return
	print("Item not found")


func remove_item_from_stack(item: ItemData, amount: int = 1):
	for slot in slots:
		if slot.item == item:
			var removed = slot.remove_from_stack(amount)

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


func get_item_count(item_name: String) -> int:
	return item_counts.get(item_name, 0)


func has_item(item_name: String, amount: int = 1) -> bool:
	return get_item_count(item_name) >= amount


func get_item_by_name(item_name: String) -> ItemData:
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
	var slot_index = slots.find(slot)
	if slot_index == -1:
		return false
	
	# Use the new clientside split system
	return split_stack_clientside(slot_index, amount)


func split_stack_by_index(from_slot_index: int, split_amount: int = -1) -> bool:
	if from_slot_index < 0 or from_slot_index >= slots.size():
		return false
	
	var from_slot = slots[from_slot_index]
	if not from_slot.item or not from_slot.item.can_stack or from_slot.item.current_stack_amount <= 1:
		return false
	
	# If no amount specified, split in half
	if split_amount == -1:
		split_amount = ceili(from_slot.item.current_stack_amount / 2.0)
	
	return split_stack_clientside(from_slot_index, split_amount)


func split_to_singles(slot_index: int) -> bool:
	if slot_index < 0 or slot_index >= slots.size():
		return false
	
	var slot = slots[slot_index]
	if not slot.item or not slot.item.can_stack or slot.item.current_stack_amount <= 1:
		return false
	
	var empty_slots = get_empty_slots()
	var max_splits = min(slot.item.current_stack_amount - 1, empty_slots.size())
	
	if max_splits <= 0:
		return false
	
	# Perform multiple splits to create singles
	var successful_splits = 0
	for i in range(max_splits):
		if split_stack_clientside(slot_index, 1):
			successful_splits += 1
		else:
			break
	
	return successful_splits > 0


func get_slots() -> Array[Slot]:
	return slots

func get_all_slots() -> Array[Slot]:
	var all_slots = slots.duplicate()
	if equipment_component:
		all_slots.append_array(equipment_component.get_slots())
	return all_slots


func is_full() -> bool:
	return get_empty_slots().is_empty()


func get_total_items() -> int:
	var total = 0
	for count in item_counts.values():
		total += count
	return total


func get_all_items_of_type(item_name: String) -> Array[Slot]:
	return item_locations.get(item_name, [])


func save_inventory() -> Dictionary:
	var inventory_data = {}
	var slot_data = []
	
	for i in range(slots.size()):
		var slot = slots[i]
		if slot.item != null:
			slot_data.append({
				"slot_index": i,
				"item_id": slot.item.item_id,  # This is a string
				"stack_amount": slot.item.current_stack_amount
			})
	
	# Save equipment slots as a dictionary: key -> item_id
	var equipment_data: Dictionary = {}
	if equipment_component and not equipment_component.equipment.is_empty():
		for eq_key in equipment_component.equipment.keys():
			var eq_slot: Slot = equipment_component.equipment[eq_key]
			if eq_slot and eq_slot.item != null:
				var key_str := str(eq_key)
				equipment_data[key_str] = eq_slot.item.item_id

	inventory_data["slots"] = slot_data
	inventory_data["equipment"] = equipment_data
	return inventory_data


func _apply_inventory_data(inventory_data: Dictionary) -> void:
	# Clear existing inventory
	for slot in slots:
		if slot.has_method("cancel_drag"):
			slot.cancel_drag()  # Cancel any ongoing drags
		slot.item = null
		slot.update_display()

	# Clear existing equipment items
	if equipment_component:
		for eq_slot in equipment_component.get_slots():
			if eq_slot.has_method("cancel_drag"):
				eq_slot.cancel_drag()
			eq_slot.item = null
			eq_slot.update_display()
	
	# Load saved items
	var slot_data = inventory_data.get("slots", [])
	for item_data in slot_data:
		var slot_index = item_data.get("slot_index", -1)
		var saved_item_id = item_data.get("item_id", "")
		var stack_amount = item_data.get("stack_amount", 1)
		
		if slot_index >= 0 and slot_index < slots.size() and not saved_item_id.is_empty():
			# Use the ResourceManager to get the item data by ID
			var item_resource = ResourceManager.get_item_data(saved_item_id)
			if item_resource:
				# print("Loading: %s" % item_resource.name)
				var item_copy = item_resource.duplicate_with_path()
				item_copy.item_id = saved_item_id
				item_copy.current_stack_amount = stack_amount
				slots[slot_index].item = item_copy
				slots[slot_index].update_display()
			else:
				print("Failed to load item with ID: " + saved_item_id)

	# Load equipment items from equipment dictionary mapping
	if equipment_component:
		var equipment_data_dict: Dictionary = inventory_data.get("equipment", {})
		for key_str in equipment_data_dict.keys():
			var eq_item_id: String = equipment_data_dict[key_str]
			if eq_item_id.is_empty():
				continue
			var target_slot: Slot = null
			if key_str == "WEAPON":
				target_slot = equipment_component.equipment.get("WEAPON")
			else:
				var key_val := int(key_str)
				target_slot = equipment_component.equipment.get(key_val)
			if target_slot:
				var eq_item_res = ResourceManager.get_item_data(eq_item_id)
				if eq_item_res:
					var eq_item_copy = eq_item_res.duplicate_with_path()
					eq_item_copy.item_id = eq_item_id
					target_slot.item = eq_item_copy
					target_slot.update_display()
				else:
					print("Failed to load equipment item with ID: " + eq_item_id)
	
	# Rebuild tracking after loading
	_rebuild_item_tracking()
	


func load_inventory(inventory_data: Dictionary) -> void:
	# If we're not yet inside the tree, buffer the data and apply later in _ready()
	if not is_inside_tree():
		pending_inventory_data = inventory_data
		return
	_apply_inventory_data(inventory_data)
	


@rpc("authority", "call_local", "reliable")
func load_inventory_rpc(inventory_data: Dictionary):
	print("Client %s received inventory data" % str(multiplayer.get_unique_id()))
	# If we're not yet inside the tree (node not replicated/added), buffer and exit
	if not is_inside_tree():
		pending_inventory_data = inventory_data
		return
	await _ensure_slots_initialized()
	_apply_inventory_data(inventory_data)
	


# Client-side: Immediately move item and request server validation
func move_item_clientside(from_slot_index: int, to_slot_index: int) -> bool:
	if from_slot_index < 0 or from_slot_index >= slots.size():
		return false
	if to_slot_index < 0 or to_slot_index >= slots.size():
		return false
	
	# Delegate to path-based transfer to avoid index-order mismatch between peers
	return transfer_item_clientside(slots[from_slot_index], slots[to_slot_index])


# Client-side split with server validation
func split_stack_clientside(from_slot_index: int, amount: int, to_slot_index: int = -1) -> bool:
	if from_slot_index < 0 or from_slot_index >= slots.size():
		return false
	
	var from_slot = slots[from_slot_index]
	if not from_slot.item or not from_slot.item.can_stack or from_slot.item.current_stack_amount <= 1:
		return false
	
	if amount >= from_slot.item.current_stack_amount or amount <= 0:
		return false
	
	# If no target slot specified, find the first empty slot
	if to_slot_index == -1:
		var empty_slots = get_empty_slots()
		if empty_slots.is_empty():
			return false
		to_slot_index = slots.find(empty_slots[0])
		if to_slot_index == -1:
			return false
	else:
		# Validate the target slot
		if to_slot_index < 0 or to_slot_index >= slots.size():
			return false
		var to_slot = slots[to_slot_index]
		if to_slot.item != null:
			return false
		if to_slot.has_method("can_accept_item") and not to_slot.can_accept_item(from_slot.item):
			return false
	
	# Store complete state for potential rollback (including visual state)
	var backup_state = {
		"from_item": from_slot.item.duplicate_with_path() if from_slot.item else null,
		"to_item": null, # Target slot is empty for splits
		"from_slot_index": from_slot_index,
		"to_slot_index": to_slot_index,
		"amount": amount
	}
	
	# Store this backup in case server rejects the split
	pending_splits[from_slot_index] = backup_state
	
	# Perform the split immediately on client (optimistic update)
	_execute_split_local(from_slot_index, to_slot_index, amount)
	
	# Send request to server for validation
	if multiplayer.has_multiplayer_peer():
		var player = owner as MultiplayerPlayerV2
		request_split_stack.rpc_id(1, from_slot_index, to_slot_index, amount, player.player_id)
	else:
		# Single player - no validation needed
		pending_splits.erase(from_slot_index)
	
	return true


func transfer_item_clientside(from_slot: Slot, to_slot: Slot) -> bool:
	# Get slot paths relative to this InventoryComponent BEFORE any local swap
	var from_path: NodePath = get_path_to(from_slot)
	var to_path: NodePath = get_path_to(to_slot)

	# Debug what we're sending (pre-swap state)
	var from_id := from_slot.item.item_id if from_slot.item else "<nil>"
	var to_id := to_slot.item.item_id if to_slot.item else "<nil>"
	

	# Store backup for potential rollback (pre-swap)
	var backup_state = {
		"from_item": from_slot.item.duplicate_with_path() if from_slot.item else null,
		"to_item": to_slot.item.duplicate_with_path() if to_slot.item else null,
		"from_slot_path": from_path,
		"to_slot_path": to_path
	}
	pending_transfers[from_path] = backup_state

	# Send request to server for validation
	if multiplayer.has_multiplayer_peer():
		var player = _get_player()
		if player:
			request_transfer_item.rpc_id(1, from_path, to_path, player.player_id)
		else:
			pass
	else:
		# Single player - no validation needed
		pending_transfers.erase(from_path)

	# Do not perform optimistic swap; wait for server confirmation to avoid race with other updates
	# Visuals will update on confirm_transfer_item
	
	return true


# Local execution of a swap (used by client and server)
func _execute_swap_local(from_slot: Slot, to_slot: Slot):
	# Store the original items before the swap
	var from_item = from_slot.item
	var to_item = to_slot.item

	# Perform the direct swap of item data
	from_slot.item = to_item
	to_slot.item = from_item

	# Explicitly update the tracking for both slots.
	# This is critical for maintaining a consistent state.
	_update_item_tracking(from_slot, from_item, to_item)
	_update_item_tracking(to_slot, to_item, from_item)

	# Ensure the display is updated
	from_slot.update_display()
	to_slot.update_display()


# Local execution of split (used by both client and server)
func _execute_split_local(from_slot_index: int, to_slot_index: int, amount: int):
	var from_slot = slots[from_slot_index]
	var to_slot = slots[to_slot_index]
	
	if not from_slot.item or to_slot.item != null:
		print("Invalid split state - from slot empty or to slot occupied")
		return

	# Keep a reference to the item data before modification for tracking
	var old_from_item = from_slot.item.duplicate_with_path()

	# Create the new item for the split stack
	var split_item = from_slot.item.duplicate_with_path()
	split_item.current_stack_amount = amount
	
	# Reduce original stack amount
	from_slot.item.current_stack_amount -= amount
	
	# Place the new split item in the target slot
	var old_to_item = to_slot.item # Should be null here
	to_slot.item = split_item
	
	# Update displays
	from_slot.update_display()
	to_slot.update_display()
	
	# Manually and explicitly update the item tracking for both slots
	_update_item_tracking(from_slot, old_from_item, from_slot.item)
	_update_item_tracking(to_slot, old_to_item, to_slot.item)


# Check if a move is valid
func _is_move_valid(from_slot: Slot, to_slot: Slot) -> bool:
	if from_slot.item == null:
		print("[INV][VALIDATE] from_slot has no item")
		return false
	
	# Check if target slot can accept the item type
	if to_slot.has_method("can_accept_item") and not to_slot.can_accept_item(from_slot.item):
		print("[INV][VALIDATE] to_slot cannot accept item '%s' (allowed=%s, item_type=%s)" % [from_slot.item.name, str(to_slot.allowed_item_type) if "allowed_item_type" in to_slot else "-", str(from_slot.item.item_type)])
		return false
	
	return true


# Check if a split is valid
func _is_split_valid(from_index: int, to_index: int, amount: int) -> bool:
	if from_index < 0 or from_index >= slots.size():
		return false
	if to_index < 0 or to_index >= slots.size():
		return false
	if amount <= 0:
		return false
	
	var from_slot = slots[from_index]
	var to_slot = slots[to_index]
	
	# Check if from slot has a valid stackable item
	if not from_slot.item or not from_slot.item.can_stack:
		return false
	
	# Check if we have enough items to split
	if amount <= 0 or amount >= from_slot.item.max_stack_amount:
		return false
	
	# Check if target slot is empty
	if to_slot.item != null:
		return false
	
	# Check if target slot can accept the item type
	if to_slot.has_method("can_accept_item") and not to_slot.can_accept_item(from_slot.item):
		return false
	
	return true


# SERVER RPC: Validate and broadcast move
@rpc("any_peer", "call_local", "reliable")
func request_move_item(from_index: int, to_index: int, requesting_player_id: int):
	if not multiplayer.is_server():
		return
	
	var player = _get_player()
	if not player or player.player_id != requesting_player_id:
		print("Move request from wrong player!")
		send_inventory_correction.rpc_id(requesting_player_id)
		return

	# Ensure server has initialized slots before validation
	if slots.is_empty():
		await _ensure_slots_initialized()
	
	if from_index < 0 or from_index >= slots.size() or to_index < 0 or to_index >= slots.size():
		print("Invalid slot indices in move request")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
	var from_slot = slots[from_index]
	var to_slot = slots[to_index]
	
	
	if not _is_move_valid(from_slot, to_slot):
		print("Invalid move rejected by server")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
	# Server executes the move
	_execute_swap_local(from_slot, to_slot)
	_notify_changed()
	
	# Send confirmation to the requesting client (clears pending moves)
	confirm_move_item.rpc_id(requesting_player_id, from_index, to_index, true)
	
	# Broadcast to other clients
	for peer_id in multiplayer.get_peers():
		if peer_id != requesting_player_id:
			confirm_move_item.rpc_id(peer_id, from_index, to_index, false)


# SERVER RPC: Validate and broadcast split
@rpc("any_peer", "call_local", "reliable")
func request_split_stack(from_index: int, to_index: int, amount: int, requesting_player_id: int):
	# Only server processes these requests
	if not multiplayer.is_server():
		return
	
	# Verify the request is from the correct player
	var player = _get_player()
	if not player or player.player_id != requesting_player_id:
		print("Split request from wrong player!")
		send_inventory_correction.rpc_id(requesting_player_id)
		return

	if slots.is_empty():
		await _ensure_slots_initialized()
	
	# Validate split on server
	if not _is_split_valid(from_index, to_index, amount):
		print("Invalid split rejected by server")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
	# Server approves and executes the split
	_execute_split_local(from_index, to_index, amount)
	_notify_changed()
	
	# Send confirmation to the requesting client (clears pending moves)
	confirm_split_stack.rpc_id(requesting_player_id, from_index, to_index, amount, true)
	
	# Broadcast the confirmed split to all other clients (except the one who requested it)
	for peer_id in multiplayer.get_peers():
		if peer_id != requesting_player_id:
			confirm_split_stack.rpc_id(peer_id, from_index, to_index, amount, false)
	
	print("Split validated and applied on server")


@rpc("any_peer", "call_local", "reliable")
func request_transfer_item(from_slot_path: NodePath, to_slot_path: NodePath, requesting_player_id: int):
	if not multiplayer.is_server():
		return

	var player = _get_player()
	if not player or player.player_id != requesting_player_id:
		send_inventory_correction.rpc_id(requesting_player_id)
		return

	if slots.is_empty():
		await _ensure_slots_initialized()

	var from_slot = get_node_or_null(from_slot_path)
	var to_slot = get_node_or_null(to_slot_path)

	if not from_slot or not to_slot:
		send_inventory_correction.rpc_id(requesting_player_id)
		return

	# Basic validation
	if not _is_move_valid(from_slot, to_slot):
		send_inventory_correction.rpc_id(requesting_player_id)
		return

	# Server executes the swap
	_execute_swap_local(from_slot, to_slot)
	_notify_changed()

	# Send confirmation to the requesting client
	confirm_transfer_item.rpc_id(requesting_player_id, from_slot_path, to_slot_path, true)

	# Broadcast to other clients
	for peer_id in multiplayer.get_peers():
		if peer_id != requesting_player_id:
			confirm_transfer_item.rpc_id(peer_id, from_slot_path, to_slot_path, false)


# CLIENT RPC: Receive confirmed move from server
@rpc("authority", "call_local", "reliable")
func confirm_move_item(from_index: int, to_index: int, was_requesting_client: bool = false):
	if multiplayer.is_server():
		return
	
	if was_requesting_client:
		# Clear the pending move since it was accepted
		pending_moves.erase(from_index)
		# Persist from client so server saves authoritative state
		var player = owner as MultiplayerPlayerV2
		if player:
			player._data_changed()
	else:
		# Apply the server-confirmed move from another client
		if from_index >= 0 and from_index < slots.size() and to_index >= 0 and to_index < slots.size():
			var from_slot = slots[from_index]
			var to_slot = slots[to_index]
			_execute_swap_local(from_slot, to_slot)


# CLIENT RPC: Receive confirmed split from server
@rpc("authority", "call_local", "reliable")
func confirm_split_stack(from_index: int, to_index: int, amount: int, was_requesting_client: bool = false):
	# Only clients process these confirmations
	if multiplayer.is_server():
		return
	
	if was_requesting_client:
		# Clear any pending splits since it was accepted
		pending_splits.erase(from_index)
		# Persist from client so server saves authoritative state
		var player = owner as MultiplayerPlayerV2
		if player:
			player._data_changed()
	else:
		# Apply the server-confirmed split from another client
		if _is_split_valid(from_index, to_index, amount):
			_execute_split_local(from_index, to_index, amount)


@rpc("authority", "call_local", "reliable")
func confirm_transfer_item(from_slot_path: NodePath, to_slot_path: NodePath, was_requesting_client: bool):
	if multiplayer.is_server():
		return

	if was_requesting_client:
		pending_transfers.erase(from_slot_path)
		var from_slot = get_node_or_null(from_slot_path)
		var to_slot = get_node_or_null(to_slot_path)
		if from_slot and to_slot:
			_execute_swap_local(from_slot, to_slot)
		# Persist from client so server saves authoritative state
		var player = owner as MultiplayerPlayerV2
		if player:
			player._data_changed()
	else:
		var from_slot = get_node_or_null(from_slot_path)
		var to_slot = get_node_or_null(to_slot_path)
		if from_slot and to_slot:
			_execute_swap_local(from_slot, to_slot)


# CLIENT RPC: Server sends correction when move was invalid
@rpc("authority", "call_local", "reliable")
func send_inventory_correction():
	if not multiplayer.is_server():
		return
		
	print("Sending inventory correction to client")
	var current_inventory = save_inventory()
	receive_inventory_correction.rpc_id(multiplayer.get_remote_sender_id(), current_inventory)


# Function to restore a rejected split
func restore_rejected_split(from_slot_index: int):
	if from_slot_index in pending_splits:
		var backup_state = pending_splits[from_slot_index]
		var from_slot = slots[from_slot_index]
		var to_slot = slots[backup_state.to_slot_index]
		
		# Restore the original state
		if backup_state.from_item:
			from_slot.item = backup_state.from_item.duplicate_with_path()
		to_slot.item = null
		
		# Update displays
		from_slot.update_display()
		to_slot.update_display()
		
		# Rebuild tracking
		_rebuild_item_tracking()
		
		# Clear the pending split
		pending_splits.erase(from_slot_index)
		
		print("Restored rejected split for slot ", from_slot_index)


@rpc("authority", "call_local", "reliable") 
func receive_inventory_correction(authoritative_inventory: Dictionary):
	if multiplayer.is_server():
		return
		
	print("Received inventory correction from server - restoring authoritative state")
	
	# Clear any pending moves and splits since server has rejected them
	pending_moves.clear()
	pending_splits.clear()
	pending_transfers.clear()
	
	# Load the authoritative inventory state
	_apply_inventory_data(authoritative_inventory)
