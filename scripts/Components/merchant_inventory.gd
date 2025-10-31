# merchant_inventory.gd
class_name MerchantInventory
extends Node

@export var merchant_name: String = "Merchant"
@export var buy_price_multiplier: float = 1.0
@export var sell_price_multiplier: float = 0.5

@export var shop_window: Panel  # Reference to ShopWindow instance

# Configurable base stock: Array of { "item": ItemData, "stock": -1 or number }
@export var base_stock_config: Array[Dictionary] = []

# Runtime base stock: { "item_name": { "stock": -1 or number, "sold_count": 0 } }
var _runtime_base_stock: Dictionary = {}

# Per-player inventories: { player_id: { item_instance_id: ItemData } }
var player_sold_unique_items: Dictionary = {} # { player_id: { item_instance_id: ItemData } }
var player_sold_stackable_items: Dictionary = {} # { player_id: { item_id: { "item_data": ItemData, "count": int, "price_per_unit": int } } }

# Store the sell prices for buyback:
var player_buyback_unique_prices: Dictionary = {} # { player_id: { item_instance_id: sell_price } }
var player_buyback_stackable_prices: Dictionary = {} # { player_id: { item_id: price_per_unit } }

# Track how many of each limited item each player has bought: { player_id: { "item_name": count } }
var player_purchase_counts: Dictionary = {}

signal inventory_changed()

func _ready():
	if multiplayer.is_server():
		for config_entry in base_stock_config:
			var item_data: ItemData = config_entry.keys()[0]
			var stock_limit: int = config_entry.get(config_entry.keys()[0], -1)
			
			if item_data:
				_runtime_base_stock[item_data.name] = {
					"item_id": item_data.item_id, # Store base item_id for easy access
					"stock": stock_limit,
					"sold_count": 0
				}
		inventory_changed.emit()


func get_player_stock(player_id: int, item_name: String) -> int:
	# Returns how many of this item the player can still buy
	if not _runtime_base_stock.has(item_name):
		return 0
	
	var stock_info = _runtime_base_stock[item_name]
	if stock_info["stock"] == -1:
		return 999  # Infinite, return large number for display
	
	# Check how many this player has already bought from base stock
	var player_bought = 0
	if player_purchase_counts.has(player_id) and player_purchase_counts[player_id].has(item_name):
		player_bought = player_purchase_counts[player_id][item_name]
	
	return max(0, stock_info["stock"] - player_bought)

func get_player_sold_items(player_id: int) -> Array:
	var sold_items_list: Array = []
	
	# Add unique items
	if player_sold_unique_items.has(player_id):
		for item_instance_id in player_sold_unique_items[player_id]:
			var item: ItemData = player_sold_unique_items[player_id][item_instance_id]
			sold_items_list.append({"item": item, "is_stackable": false})
	
	# Add stackable items
	if player_sold_stackable_items.has(player_id):
		for item_id in player_sold_stackable_items[player_id]:
			var item_entry = player_sold_stackable_items[player_id][item_id]
			var item: ItemData = item_entry.item_data
			var count: int = item_entry.count
			sold_items_list.append({"item": item, "count": count, "is_stackable": true})
	
	return sold_items_list

func add_sold_item(player_id: int, item: ItemData, sell_price: int):
	# Add item to player's sold inventory
	if item.can_stack:
		if not player_sold_stackable_items.has(player_id):
			player_sold_stackable_items[player_id] = {}
		if not player_buyback_stackable_prices.has(player_id):
			player_buyback_stackable_prices[player_id] = {}
		
		var item_entry = player_sold_stackable_items[player_id].get(item.item_id, {"item_data": item, "count": 0, "price_per_unit": sell_price})
		item_entry.count += 1
		player_sold_stackable_items[player_id][item.item_id] = item_entry
		player_buyback_stackable_prices[player_id][item.item_id] = sell_price
	else:
		if not player_sold_unique_items.has(player_id):
			player_sold_unique_items[player_id] = {}
		if not player_buyback_unique_prices.has(player_id):
			player_buyback_unique_prices[player_id] = {}
		
		player_sold_unique_items[player_id][item.instance_id] = item
		player_buyback_unique_prices[player_id][item.instance_id] = sell_price
	inventory_changed.emit()

func remove_sold_item_from_player(player_id: int, item_id: String, is_stackable: bool) -> ItemData:
	var removed_item: ItemData = null
	
	if is_stackable:
		if not player_sold_stackable_items.has(player_id) or not player_sold_stackable_items[player_id].has(item_id):
			return null
		
		var item_entry = player_sold_stackable_items[player_id][item_id]
		item_entry.count -= 1
		removed_item = item_entry.item_data.duplicate_with_path(true)
		removed_item.current_stack_amount = 1
		
		if item_entry.count <= 0:
			player_sold_stackable_items[player_id].erase(item_id)
			if player_buyback_stackable_prices.has(player_id):
				player_buyback_stackable_prices[player_id].erase(item_id)
	else:
		if not player_sold_unique_items.has(player_id) or not player_sold_unique_items[player_id].has(item_id):
			return null
		
		removed_item = player_sold_unique_items[player_id].get(item_id)
		player_sold_unique_items[player_id].erase(item_id)
		
		if player_buyback_unique_prices.has(player_id):
			player_buyback_unique_prices[player_id].erase(item_id)
	
	inventory_changed.emit()
	return removed_item # Return the removed item

func can_player_buy_from_stock(player_id: int, item_name: String) -> bool:
	# Check if player can buy this item from base stock
	return get_player_stock(player_id, item_name) > 0

func record_player_purchase(player_id: int, item_name: String):
	# Record that player bought this item from base stock
	if not _runtime_base_stock.has(item_name):
		return
	
	var stock_info = _runtime_base_stock[item_name]
	if stock_info["stock"] != -1:  # Only track if not infinite
		if not player_purchase_counts.has(player_id):
			player_purchase_counts[player_id] = {}
		
		player_purchase_counts[player_id][item_name] = player_purchase_counts[player_id].get(item_name, 0) + 1
		print("Player %d has now bought %d/%d of %s" % [player_id, player_purchase_counts[player_id][item_name], stock_info["stock"], item_name])

func get_buyback_price(player_id: int, item_id: String, is_stackable: bool) -> int:
	# Returns the price the player sold the item for (what they'll pay to buy it back)
	if is_stackable:
		if player_buyback_stackable_prices.has(player_id):
			return player_buyback_stackable_prices[player_id].get(item_id, 0)
	else:
		if player_buyback_unique_prices.has(player_id):
			return player_buyback_unique_prices[player_id].get(item_id, 0)
	return 0
func get_buy_price(item_id: String) -> int:
	var item = ResourceManager.get_item_data(item_id)
	return int(item.base_value * buy_price_multiplier) if item else 0

func get_sell_price(item_id: String) -> int:
	var item = ResourceManager.get_item_data(item_id)
	var new_value = item.base_value * sell_price_multiplier
	return clampi(new_value, 1, 999999999) if item else 0

func get_stock_data(player_id: int) -> Array:
	var data: Array = []
	
	# Add base stock items (merchant's items for sale)
	for item_name in _runtime_base_stock.keys():
		var item: ItemData = ResourceManager.get_item_by_name(item_name)
		if item:
			var available = get_player_stock(player_id, item_name)
			if available > 0:
				data.append({
					"item_id": item.item_id,
					"name": item.name,
					"count": available,
					"price": get_buy_price(item.item_id),
					"is_buyback": false
				})
	
	# Add items this player has sold (buyback items)
	var sold_items_list = get_player_sold_items(player_id)
	for sold_item_entry in sold_items_list:
		var sold_item: ItemData = sold_item_entry["item"]
		var is_stackable_buyback: bool = sold_item_entry["is_stackable"]
		var item_id_for_lookup: String
		var count: int
		
		if is_stackable_buyback:
			item_id_for_lookup = sold_item.item_id
			count = sold_item_entry["count"]
		else:
			item_id_for_lookup = sold_item.instance_id
			count = 1
		
		data.append({
			"item_id": item_id_for_lookup,
			"name": sold_item.name,
			"count": count,
			"price": get_buyback_price(player_id, item_id_for_lookup, is_stackable_buyback),
			"item_dict": sold_item.to_dictionary(),
			"is_buyback": true,
			"is_stackable_buyback": is_stackable_buyback
		})
	
	return data

# Client requests shop data from server
@rpc("any_peer", "call_local", "reliable")
func request_shop_data():
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	
	var data = get_stock_data(sender_id)
	
	# Send shop data to the requesting client's shop window
	if shop_window:
		shop_window.receive_shop_data.rpc_id(sender_id, data)
	else:
		print("ERROR: shop_window is null!")

# Buy item (player buying from merchant)
@rpc("any_peer", "call_local", "reliable")
func request_buy_item(item_id: String, is_buyback: bool, is_stackable_buyback: bool = false):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player = get_player_by_id(sender_id)
	
	if not player or not player.inventory_component or not player.player_inventory:
		print("Buy failed: player not found or missing components for peer %d" % sender_id)
		return
		
	var price: int
	
	if is_buyback:
		var item_to_buyback: ItemData
		if is_stackable_buyback:
			if not player_sold_stackable_items.has(sender_id) or not player_sold_stackable_items[sender_id].has(item_id):
				print("Buyback failed for player %d: stackable item %s not in buyback list" % [sender_id, item_id])
				return
			item_to_buyback = player_sold_stackable_items[sender_id][item_id]["item_data"]
		else:
			if not player_sold_unique_items.has(sender_id) or not player_sold_unique_items[sender_id].has(item_id):
				print("Buyback failed for player %d: unique item %s not in buyback list" % [sender_id, item_id])
				return
			item_to_buyback = player_sold_unique_items[sender_id][item_id]
		
		price = get_buyback_price(sender_id, item_id, is_stackable_buyback)
		print("DEBUG: request_buy_item (buyback) - Buying back %s for %d coins" % [item_to_buyback.name, price])
		
		if player.player_inventory.monies_amount >= price:
			player.player_inventory.monies_amount -= price
			var removed_item: ItemData = remove_sold_item_from_player(sender_id, item_id, is_stackable_buyback) # Remove after successful purchase
			# Update client's money display
			if shop_window:
				shop_window.update_money_display.rpc_id(sender_id, player.player_inventory.monies_amount)
			player.inventory_component.server_add_item_instance(removed_item.to_dictionary())
			
			if shop_window:
				shop_window.receive_shop_data.rpc_id(sender_id, get_stock_data(sender_id))
				shop_window.update_sell_display.rpc_id(sender_id)
			
			print("%s: Player %d bought back %s for %d coins" % [merchant_name, sender_id, item_to_buyback.name, price])
		else:
			print("Buyback failed for player %d: %s (cost %d, has %d)" % [sender_id, item_to_buyback.name, price, player.player_inventory.monies_amount])
		
		return # End of buyback logic	# --- Logic for buying from base stock ---
	var item_data: ItemData = ResourceManager.get_item_data(item_id)
	if not item_data:
		print("Buy failed: Item not found: %s" % item_id)
		return

	var item_name_key = item_data.name
	price = get_buy_price(item_id)
	
	if not can_player_buy_from_stock(sender_id, item_name_key):
		print("Buy failed for player %d: %s - stock limit reached or unavailable" % [sender_id, item_name_key])
		return
	
	if player.player_inventory.monies_amount >= price:
		player.player_inventory.monies_amount -= price
		player.inventory_component.add_item(item_id)
		
		if shop_window:
			shop_window.receive_shop_data.rpc_id(sender_id, get_stock_data(sender_id))
			shop_window.update_sell_display.rpc_id(sender_id)
		
		record_player_purchase(sender_id, item_name_key)
		print("%s: Player %d bought %s for %d coins" % [merchant_name, sender_id, item_name_key, price])
	else:
		print("Buy failed for player %d: %s (cost %d, has %d)" % [sender_id, item_name_key, price, player.player_inventory.monies_amount])


# Sell item (player selling to merchant)
@rpc("any_peer", "call_local", "reliable")
func request_sell_item(slot_index: int):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player = get_player_by_id(sender_id)
	
	if not player or not player.inventory_component:
		print("Sell failed: player not found or missing inventory for peer %d" % sender_id)
		return
	
	var slots = player.inventory_component.get_slots()
	if slot_index >= slots.size():
		print("Sell failed: invalid slot index %d for peer %d" % [slot_index, sender_id])
		return
		
	var slot = slots[slot_index]
	if not slot or not slot.item:
		print("Sell failed: empty slot at index %d for peer %d" % [slot_index, sender_id])
		return
	
	var item = slot.item
	
	# Determine the item to sell and its price
	var item_to_sell: ItemData
	var price_for_transaction: int
	
	if item.can_stack and item.current_stack_amount > 1:
		# Create a new ItemData instance representing a single item from the stack
		item_to_sell = item.duplicate_with_path(true) # Deep duplicate
		item_to_sell.current_stack_amount = 1 # Explicitly set to 1 for single item sale
		
		# Price is for one item
		price_for_transaction = get_sell_price(item.item_id)
		
		# Remove one item from the player's stack
		player.inventory_component.remove_item_from_stack(item, 1)
	else:
		# Not stackable, or stack of 1. Sell the whole item.
		item_to_sell = item # Use the existing item object
		
		# Price is for the whole item/stack
		price_for_transaction = get_sell_price(item.item_id) * item.current_stack_amount
		
		# Remove the whole item from the player's inventory
		player.inventory_component.remove_item(item)
	
	# Add to this player's sold items (for buyback) and store the sell price
	add_sold_item(sender_id, item_to_sell, price_for_transaction)
	player.player_inventory.monies_amount += price_for_transaction
	
	# Send updated shop data to the seller (includes both buy and sell lists)
	if shop_window:
		shop_window.receive_shop_data.rpc_id(sender_id, get_stock_data(sender_id))
		# Also trigger update of the sell list (player's inventory)
		shop_window.update_sell_display.rpc_id(sender_id)
	
	print("%s: Player %d sold %s for %d coins" % [merchant_name, sender_id, item.name, price_for_transaction])

func get_player_by_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("Players")
	for p in players:
		if p.player_id == peer_id:
			return p
	print("Warning: Could not find player with peer_id %d" % peer_id)
	return null
