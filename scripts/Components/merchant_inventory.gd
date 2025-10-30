# merchant_inventory.gd
class_name MerchantInventory
extends Node

@export var merchant_name: String = "Merchant"
@export var buy_price_multiplier: float = 1.0
@export var sell_price_multiplier: float = 0.5

@export var shop_window: Panel  # Reference to ShopWindow instance

# Structure: { "item_name": { "stock": -1 or number, "sold_count": 0 } }
# stock: -1 = infinite, any positive number = limited stock
var base_stock: Dictionary = {}

# Per-player inventories: { player_id: { "item_name": count } }
var player_sold_items: Dictionary = {}

# Store the sell prices for buyback: { player_id: { "item_name": sell_price } }
var player_buyback_prices: Dictionary = {}

# Track how many of each limited item each player has bought: { player_id: { "item_name": count } }
var player_purchase_counts: Dictionary = {}

signal inventory_changed()

func _ready():
	if multiplayer.is_server():
		_setup_base_stock()

func _setup_base_stock():
	# -1 means infinite stock
	# Any positive number means that's the purchase limit per player
	base_stock = {
		"Grape Potion": {"stock": -1, "sold_count": 0},  # Infinite
		"Test Chest": {"stock": 1, "sold_count": 0},     # Limited to 1 per player
		"Test Hat": {"stock": 1, "sold_count": 0},       # Limited to 1 per player
		"Test Sword 2": {"stock": 1, "sold_count": 0},  # Limited to 1 per player
		"Test Sword 3": {"stock": 1, "sold_count": 0},  # Limited to 1 per player
	}
	inventory_changed.emit()

func get_player_stock(player_id: int, item_name: String) -> int:
	# Returns how many of this item the player can still buy
	if not base_stock.has(item_name):
		return 0
	
	var stock_info = base_stock[item_name]
	if stock_info["stock"] == -1:
		return 999  # Infinite, return large number for display
	
	# Check how many this player has already bought from base stock
	var player_bought = 0
	if player_purchase_counts.has(player_id) and player_purchase_counts[player_id].has(item_name):
		player_bought = player_purchase_counts[player_id][item_name]
	
	return max(0, stock_info["stock"] - player_bought)

func get_player_sold_items(player_id: int) -> Dictionary:
	# Returns items this specific player has sold to the merchant
	return player_sold_items.get(player_id, {})

func add_sold_item_to_player(player_id: int, item_name: String, sell_price: int, amount: int = 1):
	# Add item to player's sold inventory
	if not player_sold_items.has(player_id):
		player_sold_items[player_id] = {}
	if not player_buyback_prices.has(player_id):
		player_buyback_prices[player_id] = {}
	
	player_sold_items[player_id][item_name] = player_sold_items[player_id].get(item_name, 0) + amount
	# Store the sell price for buyback (the price the player received when selling)
	player_buyback_prices[player_id][item_name] = sell_price
	inventory_changed.emit()

func remove_sold_item_from_player(player_id: int, item_name: String, amount: int = 1) -> bool:
	# Remove item from player's sold inventory (when they buy it back)
	if not player_sold_items.has(player_id):
		return false
	
	var current = player_sold_items[player_id].get(item_name, 0)
	if current >= amount:
		player_sold_items[player_id][item_name] = current - amount
		if player_sold_items[player_id][item_name] <= 0:
			player_sold_items[player_id].erase(item_name)
			# Also remove the stored buyback price
			if player_buyback_prices.has(player_id):
				player_buyback_prices[player_id].erase(item_name)
		inventory_changed.emit()
		return true
	return false

func can_player_buy_from_stock(player_id: int, item_name: String) -> bool:
	# Check if player can buy this item from base stock
	return get_player_stock(player_id, item_name) > 0

func record_player_purchase(player_id: int, item_name: String):
	# Record that player bought this item from base stock
	if not base_stock.has(item_name):
		return
	
	var stock_info = base_stock[item_name]
	if stock_info["stock"] != -1:  # Only track if not infinite
		if not player_purchase_counts.has(player_id):
			player_purchase_counts[player_id] = {}
		
		player_purchase_counts[player_id][item_name] = player_purchase_counts[player_id].get(item_name, 0) + 1
		print("Player %d has now bought %d/%d of %s" % [player_id, player_purchase_counts[player_id][item_name], stock_info["stock"], item_name])

func get_buyback_price(player_id: int, item_name: String) -> int:
	# Returns the price the player sold the item for (what they'll pay to buy it back)
	if player_buyback_prices.has(player_id):
		return player_buyback_prices[player_id].get(item_name, 0)
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
	for item_name in base_stock.keys():
		var item: ItemData = ResourceManager.get_item_by_name(item_name)
		if item:
			var available = get_player_stock(player_id, item_name)
			if available > 0:
				data.append({
					"item_id": item.item_id,
					"name": item.name,
					"count": available,
					"price": get_buy_price(item.item_id),
					"icon": item.icon,
					"is_buyback": false
				})
	
	# Add items this player has sold (buyback items)
	var sold_items = get_player_sold_items(player_id)
	for item_name in sold_items.keys():
		var item: ItemData = ResourceManager.get_item_by_name(item_name)
		if item and sold_items[item_name] > 0:
			data.append({
				"item_id": item.item_id,
				"name": item.name,
				"count": sold_items[item_name],
				"price": get_buyback_price(player_id, item_name),  # Use the stored sell price
				"icon": item.icon,
				"is_buyback": true
			})
	
	return data

# Client requests shop data from server
@rpc("any_peer", "call_local", "reliable")
func request_shop_data():
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	print("=== REQUEST SHOP DATA DEBUG ===")
	print("Server received shop data request from player %d" % sender_id)
	print("Shop window exists: %s" % (shop_window != null))
	
	var data = get_stock_data(sender_id)
	print("Sending %d items to player %d" % [data.size(), sender_id])
	
	# Send shop data to the requesting client's shop window
	if shop_window:
		shop_window.receive_shop_data.rpc_id(sender_id, data)
		print("Sent shop data via RPC")
	else:
		print("ERROR: shop_window is null!")
	print("=== END DEBUG ===")

# Buy item (player buying from merchant)
@rpc("any_peer", "call_local", "reliable")
func request_buy_item(item_id: String, is_buyback: bool):
	if not multiplayer.is_server():
		return
	
	var sender_id = multiplayer.get_remote_sender_id()
	var player = get_player_by_id(sender_id)
	
	if not player or not player.inventory_component or not player.player_inventory:
		print("Buy failed: player not found or missing components for peer %d" % sender_id)
		return
		
	var item_data: ItemData = ResourceManager.get_item_data(item_id)
	if not item_data:
		print("Buy failed: Item not found: %s" % item_id)
		return

	var item_name_key = item_data.name
	var price: int
	var can_buy = false
	
	if is_buyback:
		# Player is buying back an item they previously sold
		price = get_buyback_price(sender_id, item_name_key)
		can_buy = remove_sold_item_from_player(sender_id, item_name_key, 1)
		if not can_buy:
			print("Buyback failed for player %d: %s not in buyback list" % [sender_id, item_name_key])
			return
	else:
		# Player is buying from base stock
		price = get_buy_price(item_id)
		can_buy = can_player_buy_from_stock(sender_id, item_name_key)
		if not can_buy:
			print("Buy failed for player %d: %s - stock limit reached or unavailable" % [sender_id, item_name_key])
			return
	
	# Check if player has enough money
	if player.player_inventory.monies_amount >= price:
		player.player_inventory.monies_amount -= price
		player.inventory_component.add_item(item_id)
		
		# Send updated shop data to the buyer
		if shop_window:
			shop_window.receive_shop_data.rpc_id(sender_id, get_stock_data(sender_id))
			# Also trigger update of the sell list (player's inventory)
			shop_window.update_sell_display.rpc_id(sender_id)
		
		record_player_purchase(sender_id, item_name_key)
		
		var buy_type = "bought back" if is_buyback else "bought"
		print("%s: Player %d %s %s for %d coins" % [merchant_name, sender_id, buy_type, item_name_key, price])
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
	var item_id = item.item_id
	var price = get_sell_price(item_id)
	
	# Remove item from player inventory
	if item.current_stack_amount > 1:
		player.inventory_component.remove_item_from_stack(item, 1)
	else:
		player.inventory_component.remove_item(item)
	
	# Add to this player's sold items (for buyback) and store the sell price
	add_sold_item_to_player(sender_id, item.name, price, 1)
	player.player_inventory.monies_amount += price
	
	# Send updated shop data to the seller (includes both buy and sell lists)
	if shop_window:
		shop_window.receive_shop_data.rpc_id(sender_id, get_stock_data(sender_id))
		# Also trigger update of the sell list (player's inventory)
		shop_window.update_sell_display.rpc_id(sender_id)
	
	print("%s: Player %d sold %s for %d coins" % [merchant_name, sender_id, item.name, price])

func get_player_by_id(peer_id: int) -> Node:
	var players = get_tree().get_nodes_in_group("Players")
	for p in players:
		if p.player_id == peer_id:
			return p
	print("Warning: Could not find player with peer_id %d" % peer_id)
	return null
