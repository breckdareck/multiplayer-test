class_name GlobalDropHandler
extends Control

## Global drop handler that detects when items are dragged outside UI windows
## and creates DroppedItem instances in the world

var dropped_item_scene: PackedScene


func _ready():
	# Add to group so slots can find us
	add_to_group("global_drop_handler")
	
	# Load the dropped item scene
	dropped_item_scene = preload("res://scenes/Gameplay/dropped_item.tscn")
	

	# Make this control fill the entire screen
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	
	# Enable mouse input
	mouse_filter = Control.MOUSE_FILTER_PASS
	top_level = true
	

func _can_drop_data(_at_position: Vector2, data: Variant) -> bool:
	#print("DEBUG: GlobalDropHandler._can_drop_data received data: %s" % str(data))
	var can_drop = data is Slot
	#print("DEBUG: GlobalDropHandler.can_drop returned: %s" % str(can_drop))
	# Only accept Slot data
	return can_drop

func _drop_data(at_position: Vector2, data: Variant) -> void:
	var source_slot: Slot = data
	#print("We made it here!")
	
	if not source_slot or not source_slot.drag_item:
		return

	# Convert screen position to world position
	var world_position = _screen_to_world_position(at_position)

	# Request the server to drop the item (pass the slot's NodePath for server validation)
	server_request_item_drop.rpc_id(1, source_slot.drag_item.item_id, source_slot.drag_amount, world_position, multiplayer.get_unique_id(), source_slot.get_path())

	source_slot.cancel_drag()

@rpc("any_peer", "call_local", "reliable")
func server_request_item_drop(item_id: String, amount: int, world_position: Vector2, player_id: int, source_slot_path: NodePath):
	if not multiplayer.is_server():
		return

	var item_data = ResourceManager.get_item_data(item_id)
	if not item_data:
		printerr("Server received drop request for invalid item '%s' from player %d" % [item_id, player_id])
		return

	# Find the player and their inventory on the server
	var player_node = PlayerManager.get_player_node(player_id)
	if not player_node:
		printerr("Drop failed: Could not find player node for ID: ", player_id)
		return
	
	var inventory_component = player_node.get_node("Components/PlayerInventory/InventoryComponent")
	if not inventory_component:
		printerr("Drop failed: Could not find inventory component for player: ", player_id)
		return

	# --- Server-side Validation ---
	# Locate the source slot using the provided NodePath
	var slot_node = get_node_or_null(source_slot_path)
	if not slot_node or not slot_node is Slot:
		printerr("Drop failed: Invalid source slot path '%s' from player %d" % [str(source_slot_path), player_id])
		inventory_component.send_inventory_correction.rpc_id(player_id)
		return
	
	# Check if the slot belongs to the correct inventory
	if slot_node.item_container != inventory_component:
		printerr("Drop failed: Player %d attempted to drop from a slot not in their inventory." % player_id)
		inventory_component.send_inventory_correction.rpc_id(player_id)
		return
		
	# Check if the item in the slot matches what the client claims to be dropping
	if not slot_node.item or slot_node.item.item_id != item_id or slot_node.item.current_stack_amount < amount:
		printerr("Drop failed: Player %d item drop validation failed. Client claimed to drop %dx '%s'." % [player_id, amount, item_id])
		inventory_component.send_inventory_correction.rpc_id(player_id)
		return

	# --- Execution ---
	# 1. Create the dropped item in the world.
	# The original item data from the slot is used to preserve its unique properties.
	# 1. Create the dropped item in the world.
	# The original item data from the slot is used to preserve its unique properties.
	# We need to find the correct map instance for this player to drop the item into.
	var target_map = MapManager.get_player_map_node(player_id)
	if not target_map:
		printerr("Drop failed: Could not find map node for player %d" % player_id)
		return

	create_dropped_item(slot_node.item, amount, world_position, [], target_map)

	# 2. Remove the item from the player's inventory.
	# This will sync the change back to the client automatically.
	if amount >= slot_node.item.current_stack_amount:
		inventory_component.clear_slot(slot_node, "dropped")
	else:
		inventory_component.remove_item_from_stack(slot_node.item, amount, "dropped")

func _screen_to_world_position(screen_position: Vector2) -> Vector2:
	# Convert screen coordinates to world coordinates
	# This assumes we have a camera in the scene
	var camera = get_viewport().get_camera_2d()
	if camera:
		return camera.to_global(screen_position)
	else:
		# Fallback: use the screen position directly
		return screen_position

func create_dropped_item(item_data: ItemData, amount: int, world_position: Vector2, eligible_player_ids: Array[int] = [], target_scene: Node = null) -> void:
	if not multiplayer.is_server():
		return
	
	if not dropped_item_scene:
		push_error("GlobalDropHandler: Dropped item scene not loaded!")
		return
	
	# Generate deterministic name for this item (same on server and client)
	var item_unique_name = "Item_%d_%d" % [Time.get_ticks_msec(), randi()]
	
	# Create the dropped item instance
	var dropped_item = dropped_item_scene.instantiate() as DroppedItem
	if not dropped_item:
		push_error("GlobalDropHandler: Failed to instantiate dropped item!")
		return
	
	# Set the deterministic name
	dropped_item.name = item_unique_name
	
	# Add to the game scene
	var scene_to_add_to = target_scene
	if not scene_to_add_to:
		scene_to_add_to = MapManager.get_current_visible_map()
	
	if scene_to_add_to:
		var drops_node = scene_to_add_to.get_node_or_null("ItemDrops")
		if drops_node:
			drops_node.add_child(dropped_item, true)
		else:
			scene_to_add_to.add_child(dropped_item, true)
	else:
		push_error("GlobalDropHandler: No game scene found to add dropped item!")
		dropped_item.queue_free()
		return

	# Position it in the world
	# IMPORTANT: Set position AFTER adding to tree so global_position is calculated correctly relative to parent
	dropped_item.global_position = world_position
	
	# Setup the dropped item
	dropped_item.setup(item_data, amount, eligible_player_ids)
	
	# Set synchronizer to not be publicly visible initially
	var synchronizer = dropped_item.get_node_or_null("MultiplayerSynchronizer")
	if synchronizer:
		synchronizer.public_visibility = false

	# Manual RPC for clients on the same map
	# REMOVED: MultiplayerSpawner handles this now
	# if scene_to_add_to.is_in_group("map_base"):
	# 	var map_name = scene_to_add_to.name.replace("Map_", "")
	# 	var players_on_map = MapManager.get_players_on_map(map_name)
	# 	
	# 	#print("GlobalDropHandler: Spawning item %s on map %s for players: %s" % [item_data.item_id, map_name, players_on_map])
	# 	for peer_id in players_on_map:
	# 		if peer_id != 1: # Server already has it
	# 			#print("GlobalDropHandler: Sending spawn_item_client RPC to peer %d" % peer_id)
	# 			spawn_item_client.rpc_id(peer_id, item_data.item_id, amount, world_position, eligible_player_ids, item_unique_name, scene_to_add_to.name)
	# 			
	# 			# Update synchronizer visibility for this peer
	# 			if synchronizer:
	# 				synchronizer.set_visibility_for(peer_id, dropped_item.should_be_visible_to(peer_id))
	
	# Manual RPC for clients on the same map
	if scene_to_add_to.is_in_group("map_base"):
		var map_name = scene_to_add_to.name.replace("Map_", "")
		var players_on_map = MapManager.get_real_players_on_map(map_name)

		#print("GlobalDropHandler: Spawning item %s on map %s for players: %s" % [item_data.item_id, map_name, players_on_map])
		for peer_id in players_on_map:
			if peer_id != 1: # Server already has it
				#print("GlobalDropHandler: Sending spawn_item_client RPC to peer %d" % peer_id)
				spawn_item_client.rpc_id(peer_id, item_data.item_id, amount, world_position, eligible_player_ids, item_unique_name, scene_to_add_to.name)

				# Update synchronizer visibility for this peer
				if synchronizer:
					synchronizer.set_visibility_for(peer_id, dropped_item.should_be_visible_to(peer_id))
	else:
		# Fallback if not added to a map (e.g. global drop?)
		#print("GlobalDropHandler: Fallback RPC (scene not in map_base group)")
		rpc("spawn_item_client", item_data.item_id, amount, world_position, eligible_player_ids, item_unique_name, "")

	#print("GlobalDropHandler: Created dropped item %s x%d at %s for eligible players: %s" % [item_data.name, amount, world_position, str(eligible_player_ids)])


@rpc("authority", "call_local", "reliable")
func spawn_item_client(item_id: String, amount: int, world_position: Vector2, eligible_player_ids: Array = [], item_name: String = "", _map_name: String = ""):
	#print("GlobalDropHandler.spawn_item_client called: item=%s, name=%s, is_server=%s" % [item_id, item_name, multiplayer.is_server()])
	if multiplayer.is_server():
		#print("GlobalDropHandler.spawn_item_client: Exiting on server")
		return # Server already spawned it
	
	if not dropped_item_scene:
		dropped_item_scene = preload("res://scenes/Gameplay/dropped_item.tscn")
		
	var dropped_item = dropped_item_scene.instantiate() as DroppedItem
	if not dropped_item: return
	
	var item_data = ResourceManager.get_item_data(item_id)
	if not item_data: return
	
	# Set the same deterministic name as server
	if item_name != "":
		dropped_item.name = item_name
	
	# Add to current map
	var scene_to_add_to = MapManager.get_current_visible_map()
	if scene_to_add_to:
		var drops_node = scene_to_add_to.get_node_or_null("ItemDrops")
		if drops_node:
			drops_node.add_child(dropped_item)
		else:
			scene_to_add_to.add_child(dropped_item)
	else:
		# If no map visible, maybe just don't spawn? Or spawn in root?
		# For now, ignore if no map.
		dropped_item.queue_free()
		return
		
	dropped_item.global_position = world_position
	dropped_item.setup(item_data, amount, eligible_player_ids)
	dropped_item.sprite.texture = item_data.icon


func sync_items_to_player(player_id: int) -> void:
	"""
	Called by MapManager when a player joins this map.
	Manually sends spawn RPCs for all existing items to the new player.
	"""
	if not multiplayer.is_server(): return
	
	# This GlobalDropHandler should be a child of the map
	var map_instance = get_parent()
	if not map_instance or not map_instance.name.begins_with("Map_"):
		push_error("GlobalDropHandler: Cannot sync items, parent is not a map: %s" % get_path())
		return
		
	var drops_node = map_instance.get_node_or_null("ItemDrops")
	if not drops_node: return
	
	#print("GlobalDropHandler: Syncing items on map %s to player %d" % [map_instance.name, player_id])
	
	for child in drops_node.get_children():
		if child is DroppedItem and is_instance_valid(child):
			var item = child as DroppedItem
			if not item.item_data: continue
			
			# Send spawn RPC to the specific player
			spawn_item_client.rpc_id(player_id,
				item.item_data.item_id,
				item.stack_amount,
				item.global_position,
				item._eligible_player_ids,
				item.name,
				map_instance.name
			)
			
			# Update visibility for this player
			var synchronizer = item.get_node_or_null("MultiplayerSynchronizer")
			if synchronizer:
				synchronizer.set_visibility_for(player_id, item.should_be_visible_to(player_id))
