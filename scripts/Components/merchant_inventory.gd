class_name MerchantInventory
extends Node

@export var inventory_component: InventoryComponent
@export var merchant_name: String = "Merchant"
@export var buy_price_multiplier: float = 1.5
@export var sell_price_multiplier: float = 0.5
@export var restock_timer: float = 300.0  # Restock every 5 minutes

var initial_stock: Dictionary = {}  # item_id -> amount


func _ready():
	if not inventory_component:
		inventory_component = get_node_or_null("InventoryComponent")
	
	if not inventory_component:
		push_error("MerchantInventory: No InventoryComponent found!")
		return
	
	# Configure for merchant (no multiplayer sync, merchants are server-side)
	inventory_component.enable_multiplayer_sync = false
	inventory_component.inventory_changed.connect(_on_inventory_changed)
	
	# Stock the merchant's inventory
	if multiplayer.is_server():
		_stock_initial_items()
		
		# Setup restock timer if needed
		if restock_timer > 0:
			var timer = Timer.new()
			add_child(timer)
			timer.wait_time = restock_timer
			timer.timeout.connect(_restock_items)
			timer.start()


func _stock_initial_items():
	# Define initial stock - override this in inherited classes or set via exported variables
	initial_stock = {
		"health_potion": 10,
		"mana_potion": 10,
		"iron_sword": 3,
		"leather_armor": 5,
	}
	
	for item_id in initial_stock.keys():
		var amount = initial_stock[item_id]
		for i in range(amount):
			inventory_component.add_item(item_id)


func _restock_items():
	"""Restock items back to initial amounts"""
	for item_id in initial_stock.keys():
		var target_amount = initial_stock[item_id]
		var current_amount = inventory_component.get_item_count(item_id)
		var needed = target_amount - current_amount
		
		for i in range(needed):
			inventory_component.add_item(item_id)
	
	print("%s restocked inventory" % merchant_name)


func _on_inventory_changed(_inventory: InventoryComponent):
	# Merchant-specific behavior
	# Could save merchant state to a global merchant manager here
	pass


func get_buy_price(item: ItemData) -> int:
	"""Price for player to buy from merchant"""
	return int(item.base_value * buy_price_multiplier)


func get_sell_price(item: ItemData) -> int:
	"""Price for player to sell to merchant"""
	return int(item.base_value * sell_price_multiplier)


func sell_to_player(item: ItemData, player_inventory: PlayerInventory) -> bool:
	"""Merchant sells item to player"""
	var price = get_buy_price(item)
	
	if player_inventory.monies_amount >= price:
		player_inventory.monies_amount -= price
		inventory_component.remove_item(item)
		player_inventory.add_item(item.item_id)
		print("%s sold %s to player for %d coins" % [merchant_name, item.name, price])
		return true
	
	print("Player cannot afford %s (costs %d)" % [item.name, price])
	return false


func buy_from_player(item: ItemData, player_inventory: PlayerInventory) -> bool:
	"""Merchant buys item from player"""
	var price = get_sell_price(item)
	
	# Check if merchant has space
	if inventory_component.is_full():
		print("%s has no space for %s" % [merchant_name, item.name])
		return false
	
	player_inventory.monies_amount += price
	player_inventory.remove_item(item)
	inventory_component.add_item(item.item_id)
	print("%s bought %s from player for %d coins" % [merchant_name, item.name, price])
	return true
