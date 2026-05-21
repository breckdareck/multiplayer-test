## crafting_station.gd
## Server-authoritative crafting logic. A client sends a "craft recipe X"
## intent via RPC; the server validates the requesting player's inventory has
## every ingredient in the required count, removes them, and adds the result.
## There is no client-side crafting — clients only display recipes and send
## intent. Mirrors the RPC pattern used by MerchantInventory.
class_name CraftingStation
extends Node

## Reference to the CraftingWindow instance, set when the window is opened.
@export var crafting_window: Panel


## Finds a player node in the "Players" group by peer id.
func get_player_by_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("Players")
	for p in players:
		if p.player_id == peer_id:
			return p
	return null


## Client requests to craft the recipe identified by [param recipe_name].
## All validation and mutation happen here on the server.
@rpc("any_peer", "call_local", "reliable")
func request_craft(recipe_name: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1  # Local call from host

	var player = get_player_by_id(sender_id)
	if not player or not player.inventory_component:
		_notify_result(sender_id, recipe_name, false, "Player not found.")
		return

	var recipe: CraftingRecipeData = ResourceManager.get_recipe_by_name(recipe_name)
	if recipe == null or not recipe.is_valid():
		_notify_result(sender_id, recipe_name, false, "Unknown recipe.")
		return

	var inventory: InventoryComponent = player.inventory_component

	# Validate: the inventory has every required ingredient in the needed count.
	# Counts are aggregated so a recipe that lists the same item twice is summed.
	var required: Dictionary = recipe.get_required_counts()
	for item_id in required:
		if inventory.get_item_count(item_id) < required[item_id]:
			_notify_result(sender_id, recipe_name, false, "Missing materials.")
			return

	# Validate: there is room for the result. A non-stackable result needs an
	# empty slot; a stackable result can also merge into an existing stack.
	if not _has_room_for_result(inventory, recipe, required):
		_notify_result(sender_id, recipe_name, false, "Inventory full.")
		return

	# Consume ingredients. Each item_id may be spread across multiple stacks,
	# so remove from each stack until the required amount is satisfied.
	for item_id in required:
		var remaining: int = required[item_id]
		while remaining > 0:
			var slots_with_item: Array = inventory.get_all_items_of_id(item_id)
			if slots_with_item.is_empty():
				break
			var slot = slots_with_item[0]
			var item: ItemData = slot.item
			if item == null:
				break
			var to_remove: int = min(remaining, item.current_stack_amount)
			inventory.remove_item_from_stack(item, to_remove, "crafted")
			remaining -= to_remove

	# Produce the result.
	for i in recipe.result_count:
		inventory.server_add_item(recipe.result.item_id)

	# Persist the change so a map switch or disconnect doesn't lose it.
	if player.username and SaveManager:
		SaveManager.queue_save(player.username, "inventory", player)

	_notify_result(sender_id, recipe_name, true, "Crafted %s!" % recipe.result.name)


## Returns true when the inventory can hold [param recipe]'s result. Treats a
## free empty slot as sufficient; for stackable results also accepts an
## existing stack with enough remaining space. [param freed] maps each
## ingredient item_id to the total amount the craft consumes — when a recipe
## consumes every copy of an ingredient, the slots holding it become free,
## which matters when the inventory is otherwise full.
func _has_room_for_result(inventory: InventoryComponent, recipe: CraftingRecipeData, freed: Dictionary) -> bool:
	var result_item: ItemData = recipe.result
	var empty_slots: int = inventory.get_empty_slots().size()

	# An ingredient whose entire owned amount is consumed frees all its slots.
	# (Conservative: only counts when the craft empties the item completely.)
	for item_id in freed:
		if inventory.get_item_count(item_id) <= freed[item_id]:
			empty_slots += inventory.get_all_items_of_id(item_id).size()

	if empty_slots > 0:
		return true

	# No empty slots — a stackable result can still fit into an existing stack.
	if result_item.can_stack:
		for slot in inventory.get_all_items_of_id(result_item.item_id):
			var item: ItemData = slot.item
			if item and item.current_stack_amount < item.max_stack_amount:
				return true

	return false


## Sends the craft outcome back to the requesting client's window.
func _notify_result(player_id: int, recipe_name: String, success: bool, message: String) -> void:
	if crafting_window:
		crafting_window.receive_craft_result.rpc_id(player_id, recipe_name, success, message)
