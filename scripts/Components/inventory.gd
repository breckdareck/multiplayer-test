class_name InventoryComponent
extends Node

@export var inventory_grids: Array[GridContainer]
@export var slots: Array[Slot] = []

var item_counts: Dictionary = {} # item_name -> total_count
var item_locations: Dictionary = {} # item_name -> Array[Slot]

var pending_moves: Dictionary = {}
var pending_splits: Dictionary = {}

func _ready() -> void:
	await _ensure_slots_initialized()
	
	# Test code for adding items
	for x in range(10):
		# Get items by name from ResourceManager
		var potion = ResourceManager.get_item_by_name("Grape Potion")
		var sword = ResourceManager.get_item_by_name("Iron Sword")
		var coin = ResourceManager.get_item_by_name("Coin")
		
		# Make sure to duplicate before adding
		if potion:
			var potion_copy = potion.duplicate_with_path()
			add_item(potion_copy)
			
		if sword:
			var sword_copy = sword.duplicate_with_path()
			add_item(sword_copy)
			
		if coin:
			var coin_copy = coin.duplicate_with_path()
			add_item(coin_copy)

	_rebuild_item_tracking()


func _ensure_slots_initialized() -> void:
	# If slots array is empty, try to get them from the grid
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
					# The rest of this stacking logic is the same...
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
	
	inventory_data["slots"] = slot_data
	return inventory_data


func load_inventory(inventory_data: Dictionary) -> void:
	# Clear existing inventory
	for slot in slots:
		slot.item = null
		slot.update_display()
	
	# Rebuild tracking
	_rebuild_item_tracking()

	#while slots.size() == 0:
		#await get_tree().process_frame
	
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
				var item_copy = item_resource.duplicate_with_path()
				# Preserve the saved item_id
				item_copy.item_id = saved_item_id
				item_copy.current_stack_amount = stack_amount
				slots[slot_index].item = item_copy
				slots[slot_index].update_display()
			else:
				print("Failed to load item with ID: " + saved_item_id)
	
	# Rebuild tracking after loading
	_rebuild_item_tracking()

	var player = owner as MultiplayerPlayerV2
	var client_id = player.player_id
	print(client_id)
	if client_id != 1: # Don't send to server
		load_inventory_rpc.rpc_id(client_id, inventory_data)


func load_inventory_from_data(inventory_data: Dictionary):
	# Clear existing inventory
	for slot in slots:
		if slot.has_method("cancel_drag"):
			slot.cancel_drag()  # Cancel any ongoing drags
		slot.item = null
		slot.update_display()
	
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
				var item_copy = item_resource.duplicate_with_path()
				item_copy.item_id = saved_item_id
				item_copy.current_stack_amount = stack_amount
				slots[slot_index].item = item_copy
				slots[slot_index].update_display()
			else:
				print("Failed to load item with ID: " + saved_item_id)
	
	# Rebuild tracking after loading
	_rebuild_item_tracking()


@rpc("authority", "call_local", "reliable")
func load_inventory_rpc(inventory_data: Dictionary):
	print("Client %s received inventory data" % str(multiplayer.get_unique_id()))
	
	# Clear existing inventory
	for slot in slots:
		slot.item = null
		slot.update_display()
	
	# Load the inventory data on client side
	var slot_data = inventory_data.get("slots", [])
	for item_data in slot_data:
		var slot_index = item_data.get("slot_index", -1)
		var saved_item_id = item_data.get("item_id", "")
		var stack_amount = item_data.get("stack_amount", 1)
		
		if slot_index >= 0 and slot_index < slots.size() and not saved_item_id.is_empty():
			# Use the ResourceManager to get the item data by ID
			var item_resource = ResourceManager.get_item_data(saved_item_id)
			
			if item_resource:
				var item_copy = item_resource.duplicate_with_path()
				item_copy.item_id = saved_item_id
				item_copy.current_stack_amount = stack_amount
				slots[slot_index].item = item_copy
				slots[slot_index].update_display()
			else:
				print("Failed to load item with ID: " + saved_item_id)
	
	_rebuild_item_tracking()


# Client-side: Immediately move item and request server validation
func move_item_clientside(from_slot_index: int, to_slot_index: int) -> bool:
	if from_slot_index < 0 or from_slot_index >= slots.size():
		return false
	if to_slot_index < 0 or to_slot_index >= slots.size():
		return false
	
	var from_slot: Slot = slots[from_slot_index]
	var to_slot: Slot = slots[to_slot_index]
	
	# Check if move is valid locally first
	if not _is_move_valid(from_slot, to_slot):
		return false
	
	# Store complete state for potential rollback (including visual state)
	var backup_state: Dictionary[Variant, Variant] = {
		"from_item": from_slot.item.duplicate_with_path() if from_slot.item else null,
		"to_item": to_slot.item.duplicate_with_path() if to_slot.item else null,
		"from_slot_index": from_slot_index,
		"to_slot_index": to_slot_index
	}
	
	# Store this backup in case server rejects the move
	pending_moves[from_slot_index] = backup_state
	
	# Perform the move immediately on client (optimistic update)
	_execute_move_local(from_slot, to_slot)
	
	# Send request to server for validation
	if multiplayer.has_multiplayer_peer():
		var player = owner as MultiplayerPlayerV2
		request_move_item.rpc_id(1, from_slot_index, to_slot_index, player.player_id)
	else:
		# Single player - no validation needed
		pending_moves.erase(from_slot_index)
	
	return true


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


# Local execution of the move (used by both client and server)
func _execute_move_local(from_slot: Slot, to_slot: Slot):
	var from_item = from_slot.item
	var to_item = to_slot.item
	
	# Handle different move scenarios
	if to_item == null:
		# Simple move to empty slot
		to_slot.item = from_item
		from_slot.item = null
	elif from_item != null and to_item != null:
		if from_item.name == to_item.name and from_item.can_stack and to_item.can_stack:
			# Try to stack items
			var space_in_to = to_item.max_stack_amount - to_item.current_stack_amount
			if space_in_to > 0:
				var amount_to_move = min(from_item.current_stack_amount, space_in_to)
				to_item.current_stack_amount += amount_to_move
				from_item.current_stack_amount -= amount_to_move
				
				if from_item.current_stack_amount <= 0:
					from_slot.item = null
			else:
				# Swap items if can't stack
				to_slot.item = from_item
				from_slot.item = to_item
		else:
			# Swap different items
			to_slot.item = from_item
			from_slot.item = to_item
	
	# Update displays
	from_slot.update_display()
	to_slot.update_display()
	
	# Update tracking
	_rebuild_item_tracking()


# Local execution of split (used by both client and server)
func _execute_split_local(from_slot_index: int, to_slot_index: int, amount: int):
	var from_slot = slots[from_slot_index]
	var to_slot = slots[to_slot_index]
	
	if not from_slot.item or to_slot.item != null:
		print("Invalid split state - from slot empty or to slot occupied")
		return
	
	# Create the split item
	var split_item = from_slot.item.duplicate_with_path()
	split_item.current_stack_amount = amount
	
	# Reduce original stack
	from_slot.item.current_stack_amount -= amount
	
	# Place split item in target slot
	to_slot.item = split_item
	
	# Update displays
	from_slot.update_display()
	to_slot.update_display()
	
	# Update tracking by rebuilding from scratch
	_rebuild_item_tracking()


# Check if a move is valid
func _is_move_valid(from_slot: Slot, to_slot: Slot) -> bool:
	if from_slot.item == null:
		return false
	
	# Check if target slot can accept the item type
	if to_slot.has_method("can_accept_item") and not to_slot.can_accept_item(from_slot.item):
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
	# For splits, we need to check if the amount is valid
	# The client may have already reduced the stack, so we check if the split amount is reasonable
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
	
	var player = owner as MultiplayerPlayerV2
	if player.player_id != requesting_player_id:
		print("Move request from wrong player!")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
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
	_execute_move_local(from_slot, to_slot)
	
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
	var player = owner as MultiplayerPlayerV2
	if player.player_id != requesting_player_id:
		print("Split request from wrong player!")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
	# Validate split on server
	if not _is_split_valid(from_index, to_index, amount):
		print("Invalid split rejected by server")
		send_inventory_correction.rpc_id(requesting_player_id)
		return
	
	# Server approves and executes the split
	_execute_split_local(from_index, to_index, amount)
	
	# Send confirmation to the requesting client (clears pending moves)
	confirm_split_stack.rpc_id(requesting_player_id, from_index, to_index, amount, true)
	
	# Broadcast the confirmed split to all other clients (except the one who requested it)
	for peer_id in multiplayer.get_peers():
		if peer_id != requesting_player_id:
			confirm_split_stack.rpc_id(peer_id, from_index, to_index, amount, false)
	
	print("Split validated and applied on server")


# CLIENT RPC: Receive confirmed move from server
@rpc("authority", "call_local", "reliable")
func confirm_move_item(from_index: int, to_index: int, was_requesting_client: bool = false):
	if multiplayer.is_server():
		return
	
	if was_requesting_client:
		# Clear the pending move since it was accepted
		pending_moves.erase(from_index)
		print("Move confirmed by server")
	else:
		# Apply the server-confirmed move from another client
		if from_index >= 0 and from_index < slots.size() and to_index >= 0 and to_index < slots.size():
			var from_slot = slots[from_index]
			var to_slot = slots[to_index]
			_execute_move_local(from_slot, to_slot)
			print("Applied move from another client")


# CLIENT RPC: Receive confirmed split from server
@rpc("authority", "call_local", "reliable")
func confirm_split_stack(from_index: int, to_index: int, amount: int, was_requesting_client: bool = false):
	# Only clients process these confirmations
	if multiplayer.is_server():
		return
	
	if was_requesting_client:
		# Clear any pending splits since it was accepted
		pending_splits.erase(from_index)
		print("Split confirmed by server")
	else:
		# Apply the server-confirmed split from another client
		if _is_split_valid(from_index, to_index, amount):
			_execute_split_local(from_index, to_index, amount)
			print("Received confirmed split from server")
		else:
			print("Received invalid split confirmation from server")


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
	
	# Load the authoritative inventory state
	load_inventory_from_data(authoritative_inventory)
