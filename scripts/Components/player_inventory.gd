class_name PlayerInventory
extends Node

@export var inventory_component: InventoryComponent
@export var player: MultiplayerPlayerV2
@export var monies_label: Label

const MAX_MONIES_AMOUNT: int = 999999999
var _loading_mode: bool = false

var monies_amount: int = 0:
	set(value):
		monies_amount = clampi(value, 0, MAX_MONIES_AMOUNT)
		# monies_label is a UI node; a bot frees its UI subtree, so validate it.
		if is_instance_valid(monies_label):
			monies_label.text = inventory_component.format_number_with_commas(value)
		if not _loading_mode:
			_notify_player_data_changed()


func _ready():
	if not inventory_component:
		inventory_component = get_node_or_null("InventoryComponent")
	
	if not inventory_component:
		push_error("PlayerInventory: No InventoryComponent found!")
		return
	
	# Connect to the generic component's signals
	inventory_component.inventory_changed.connect(_on_inventory_changed)
	inventory_component.item_added.connect(_on_item_added)
	inventory_component.item_removed.connect(_on_item_removed)
	
	# Configure multiplayer for player
	if multiplayer.is_server() and player:
		inventory_component.owner_id = player.player_id
		inventory_component.enable_multiplayer_sync = true


func _on_inventory_changed(_inventory: InventoryComponent):
	if _loading_mode:
		return
	# Only trigger stats recalc on client when inventory_changed signal is emitted
	# This happens when equipment changes or full inventory loads
	if player and player.stats_component:
		player.stats_component.mark_stats_dirty()

	# Notify player data changed (for saving on server)
	_notify_player_data_changed()


func _on_item_added(item: ItemData):
	# Handle special items like coins
	if item.name == "Coin":
		monies_amount += item.current_stack_amount
		#print("Player gained %d coins" % item.current_stack_amount)
		if multiplayer.is_server():
			var map_node = MapManager.get_player_map_node(player.player_id)
			if map_node:
				var map_name = map_node.name.replace("Map_", "")
				AudioManager.play_sfx_for_map(map_name, "res://assets/sounds/coin.wav", player.global_position)


func _on_item_removed(item: ItemData, reason: String) -> void:
	# Player-specific behavior when an item leaves the inventory.
	var who: String = player.username if is_instance_valid(player) and not player.username.is_empty() else "Player"
	var verb: String = {
		"sold": "sold",
		"traded": "traded away",
		"dropped": "dropped",
		"used": "used",
	}.get(reason, "removed")
	print("%s %s %s." % [who, verb, item.name])


func _notify_player_data_changed():
	"""Notify the player that data changed (for saving)"""
	if multiplayer.is_server() and player:
		if player.has_method("_data_changed"):
			player._data_changed("inventory")


# Public API - delegates to inventory component
func add_item(item_id: String):
	inventory_component.add_item(item_id)


func add_item_instance(item_data: ItemData):
	if multiplayer.is_server():
		inventory_component.server_add_item_instance(item_data.to_dictionary())
	else:
		inventory_component.server_add_item_instance.rpc_id(1, item_data.to_dictionary())


func remove_item(item: ItemData, reason: String = "removed"):
	inventory_component.remove_item(item, reason)


func has_item(item_name: String, amount: int = 1) -> bool:
	return inventory_component.has_item(item_name, amount)


func get_item_count(item_name: String) -> int:
	return inventory_component.get_item_count(item_name)


# Save/Load with player-specific data
func save_player_inventory() -> Dictionary:
	var data = inventory_component.save_inventory()
	data["monies"] = monies_amount
	return data


func load_player_inventory(data: Dictionary):
	_loading_mode = true
	inventory_component.load_inventory(data)
	monies_amount = data.get("monies", 0)
	_loading_mode = false


func load_player_inventory_silent(data: Dictionary):
	_loading_mode = true
	inventory_component.load_inventory_silent(data)
	monies_amount = data.get("monies", 0)
	_loading_mode = false


@rpc("authority", "call_local", "reliable")
func set_monies_rpc(amount: int):
	monies_amount = amount
