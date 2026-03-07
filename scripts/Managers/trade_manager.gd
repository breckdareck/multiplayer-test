extends Node
## TradeManager — Server-authoritative proximity-based player trading.
##
## Flow: /trade <username> → accept → both add items/coins → both confirm → execute
## Both players must be on the same map and within proximity range.

signal trade_started(player_a_id: int, player_b_id: int)
signal trade_completed(player_a_id: int, player_b_id: int)
signal trade_cancelled(player_id: int)

const TRADE_PROXIMITY_RANGE: float = 100.0
const TRADE_REQUEST_TIMEOUT: float = 30.0

# Active trade sessions: trade_id -> TradeSession data
var _active_trades: Dictionary = {}
# Player -> trade_id lookup
var _player_trade_map: Dictionary = {}  # player_id -> trade_id
# Pending trade requests: target_player_id -> { requester_id, timestamp }
var _pending_requests: Dictionary = {}

var _next_trade_id: int = 1


# ═══════════════════════════════════════════════════════════════════════════
# CLIENT → SERVER RPCs
# ═══════════════════════════════════════════════════════════════════════════

## /trade <username> — request a trade
@rpc("any_peer", "call_remote", "reliable")
func request_trade(target_username: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if _player_trade_map.has(sender_id):
		_send_trade_message.rpc_id(sender_id, "You are already in a trade.", Color.RED)
		return

	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	var target_id: int = PlayerManager.get_player_id_from_name(target_username)
	if target_id == -1:
		_send_trade_message.rpc_id(sender_id, "Player '%s' is not online." % target_username, Color.RED)
		return

	if target_id == sender_id:
		_send_trade_message.rpc_id(sender_id, "You can't trade with yourself.", Color.RED)
		return

	if _player_trade_map.has(target_id):
		_send_trade_message.rpc_id(sender_id, "%s is already in a trade." % target_username, Color.RED)
		return

	var target_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(target_id)
	if not is_instance_valid(target_node):
		return

	# Proximity check
	if sender_node.global_position.distance_to(target_node.global_position) > TRADE_PROXIMITY_RANGE:
		_send_trade_message.rpc_id(sender_id, "You must be closer to %s to trade." % target_username, Color.RED)
		return

	# Store request
	_pending_requests[target_id] = {"requester_id": sender_id, "timestamp": Time.get_unix_time_from_system()}

	_send_trade_message.rpc_id(sender_id, "Trade request sent to %s." % target_username, Color.YELLOW)
	_send_trade_message.rpc_id(target_id, "%s wants to trade! Type /trade accept" % sender_node.username, Color.YELLOW)


## /trade accept — accept pending trade request
@rpc("any_peer", "call_remote", "reliable")
func accept_trade() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _pending_requests.has(sender_id):
		_send_trade_message.rpc_id(sender_id, "No pending trade request.", Color.RED)
		return

	var request: Dictionary = _pending_requests[sender_id]
	_pending_requests.erase(sender_id)

	# Check timeout
	if Time.get_unix_time_from_system() - request.timestamp > TRADE_REQUEST_TIMEOUT:
		_send_trade_message.rpc_id(sender_id, "Trade request expired.", Color.RED)
		return

	var requester_id: int = request.requester_id
	if _player_trade_map.has(requester_id):
		_send_trade_message.rpc_id(sender_id, "That player is now in another trade.", Color.RED)
		return

	_start_trade(requester_id, sender_id)


## Add coins to the trade offer
@rpc("any_peer", "call_remote", "reliable")
func trade_offer_coins(amount: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _player_trade_map.has(sender_id):
		return

	var trade_id: int = _player_trade_map[sender_id]
	var trade: Dictionary = _active_trades[trade_id]
	var side: String = "a" if trade.player_a == sender_id else "b"
	var other_id: int = trade.player_b if side == "a" else trade.player_a

	# Validate coins
	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node):
		return
	if amount < 0 or amount > player_node.player_inventory.monies_amount:
		_send_trade_message.rpc_id(sender_id, "Invalid coin amount.", Color.RED)
		return

	trade[side + "_coins"] = amount
	# Reset confirmations when offer changes
	trade.a_confirmed = false
	trade.b_confirmed = false

	_send_trade_message.rpc_id(sender_id, "You offered %d coins." % amount, Color.YELLOW)
	_send_trade_message.rpc_id(other_id, "Partner offered %d coins." % amount, Color.YELLOW)


## Add an item to the trade (by inventory slot index)
@rpc("any_peer", "call_remote", "reliable")
func trade_offer_item(slot_index: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _player_trade_map.has(sender_id):
		return

	var trade_id: int = _player_trade_map[sender_id]
	var trade: Dictionary = _active_trades[trade_id]
	var side: String = "a" if trade.player_a == sender_id else "b"
	var other_id: int = trade.player_b if side == "a" else trade.player_a

	var player_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.player_inventory):
		return

	var inv: InventoryComponent = player_node.player_inventory.inventory_component
	if slot_index < 0 or slot_index >= inv.slots.size():
		_send_trade_message.rpc_id(sender_id, "Invalid slot.", Color.RED)
		return

	var slot = inv.slots[slot_index]
	if not slot.has_item():
		_send_trade_message.rpc_id(sender_id, "That slot is empty.", Color.RED)
		return

	var item: ItemData = slot.item
	var items_list: Array = trade[side + "_items"]

	# Toggle: if already offered, remove it
	for i in range(items_list.size()):
		if items_list[i].slot_index == slot_index:
			items_list.remove_at(i)
			trade.a_confirmed = false
			trade.b_confirmed = false
			_send_trade_message.rpc_id(sender_id, "Removed %s from trade." % item.name, Color.GRAY)
			_send_trade_message.rpc_id(other_id, "Partner removed %s from trade." % item.name, Color.GRAY)
			return

	items_list.append({"slot_index": slot_index, "item_name": item.name, "item_data": item})
	trade.a_confirmed = false
	trade.b_confirmed = false

	_send_trade_message.rpc_id(sender_id, "Added %s to trade." % item.name, Color.YELLOW)
	_send_trade_message.rpc_id(other_id, "Partner added %s to trade." % item.name, Color.YELLOW)


## Confirm the trade — both must confirm for execution
@rpc("any_peer", "call_remote", "reliable")
func confirm_trade() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _player_trade_map.has(sender_id):
		return

	var trade_id: int = _player_trade_map[sender_id]
	var trade: Dictionary = _active_trades[trade_id]
	var side: String = "a" if trade.player_a == sender_id else "b"
	var other_id: int = trade.player_b if side == "a" else trade.player_a

	trade[side + "_confirmed"] = true
	_send_trade_message.rpc_id(sender_id, "You confirmed the trade.", Color.GREEN)
	_send_trade_message.rpc_id(other_id, "Partner confirmed the trade.", Color.YELLOW)

	if trade.a_confirmed and trade.b_confirmed:
		_execute_trade(trade_id)


## Cancel the trade
@rpc("any_peer", "call_remote", "reliable")
func cancel_trade() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _player_trade_map.has(sender_id):
		_send_trade_message.rpc_id(sender_id, "You are not in a trade.", Color.RED)
		return

	var trade_id: int = _player_trade_map[sender_id]
	var trade: Dictionary = _active_trades[trade_id]
	var other_id: int = trade.player_b if trade.player_a == sender_id else trade.player_a

	_end_trade(trade_id)
	_send_trade_message.rpc_id(sender_id, "Trade cancelled.", Color.RED)
	_send_trade_message.rpc_id(other_id, "Trade was cancelled.", Color.RED)
	trade_cancelled.emit(sender_id)


## Show current trade status
@rpc("any_peer", "call_remote", "reliable")
func request_trade_status() -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	if not _player_trade_map.has(sender_id):
		_send_trade_message.rpc_id(sender_id, "You are not in a trade.", Color.GRAY)
		return

	var trade_id: int = _player_trade_map[sender_id]
	var trade: Dictionary = _active_trades[trade_id]
	var side: String = "a" if trade.player_a == sender_id else "b"
	var other_side: String = "b" if side == "a" else "a"

	var my_items: Array = trade[side + "_items"]
	var their_items: Array = trade[other_side + "_items"]
	var my_coins: int = trade[side + "_coins"]
	var their_coins: int = trade[other_side + "_coins"]

	var status: String = "=== Trade Status ==="
	status += "\nYour offer: %d coins" % my_coins
	for item_info in my_items:
		status += "\n  - %s" % item_info.item_name
	status += "\nTheir offer: %d coins" % their_coins
	for item_info in their_items:
		status += "\n  - %s" % item_info.item_name
	status += "\nYou: %s | Them: %s" % [
		"Confirmed" if trade[side + "_confirmed"] else "Not confirmed",
		"Confirmed" if trade[other_side + "_confirmed"] else "Not confirmed",
	]
	status += "\nUse /trade confirm to confirm, /trade cancel to cancel."

	_send_trade_message.rpc_id(sender_id, status, Color.WHITE)


# ═══════════════════════════════════════════════════════════════════════════
# SERVER → CLIENT RPCs
# ═══════════════════════════════════════════════════════════════════════════

@rpc("authority", "call_local", "reliable")
func _send_trade_message(text: String, color: Color) -> void:
	ChatManager.message_received.emit(text, color)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNAL
# ═══════════════════════════════════════════════════════════════════════════

func _start_trade(player_a_id: int, player_b_id: int) -> void:
	var trade_id: int = _next_trade_id
	_next_trade_id += 1

	_active_trades[trade_id] = {
		"player_a": player_a_id,
		"player_b": player_b_id,
		"a_items": [],
		"b_items": [],
		"a_coins": 0,
		"b_coins": 0,
		"a_confirmed": false,
		"b_confirmed": false,
	}
	_player_trade_map[player_a_id] = trade_id
	_player_trade_map[player_b_id] = trade_id

	var a_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(player_a_id)
	var b_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(player_b_id)
	var a_name: String = a_node.username if is_instance_valid(a_node) else "Unknown"
	var b_name: String = b_node.username if is_instance_valid(b_node) else "Unknown"

	_send_trade_message.rpc_id(player_a_id, "Trade started with %s! Use /trade status, /trade coins <amount>, /trade confirm, or /trade cancel." % b_name, Color.GREEN)
	_send_trade_message.rpc_id(player_b_id, "Trade started with %s! Use /trade status, /trade coins <amount>, /trade confirm, or /trade cancel." % a_name, Color.GREEN)

	trade_started.emit(player_a_id, player_b_id)
	print("TradeManager: Trade %d started between %s and %s" % [trade_id, a_name, b_name])


func _execute_trade(trade_id: int) -> void:
	var trade: Dictionary = _active_trades[trade_id]
	var a_id: int = trade.player_a
	var b_id: int = trade.player_b
	var a_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(a_id)
	var b_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(b_id)

	if not is_instance_valid(a_node) or not is_instance_valid(b_node):
		_end_trade(trade_id)
		return

	var a_inv: PlayerInventory = a_node.player_inventory
	var b_inv: PlayerInventory = b_node.player_inventory

	# Validate coins
	if a_inv.monies_amount < trade.a_coins or b_inv.monies_amount < trade.b_coins:
		_send_trade_message.rpc_id(a_id, "Trade failed — insufficient coins.", Color.RED)
		_send_trade_message.rpc_id(b_id, "Trade failed — insufficient coins.", Color.RED)
		_end_trade(trade_id)
		return

	# Transfer coins
	a_inv.monies_amount -= trade.a_coins
	a_inv.monies_amount += trade.b_coins
	b_inv.monies_amount -= trade.b_coins
	b_inv.monies_amount += trade.a_coins

	a_inv.set_monies_rpc.rpc(a_inv.monies_amount)
	b_inv.set_monies_rpc.rpc(b_inv.monies_amount)

	# Transfer items: A's items -> B, B's items -> A
	for item_info in trade.a_items:
		var slot = a_inv.inventory_component.slots[item_info.slot_index]
		if slot.has_item():
			var item: ItemData = slot.item.duplicate(true)
			a_inv.inventory_component.remove_item(slot.item)
			b_inv.add_item_instance(item)

	for item_info in trade.b_items:
		var slot = b_inv.inventory_component.slots[item_info.slot_index]
		if slot.has_item():
			var item: ItemData = slot.item.duplicate(true)
			b_inv.inventory_component.remove_item(slot.item)
			a_inv.add_item_instance(item)

	_send_trade_message.rpc_id(a_id, "Trade completed successfully!", Color.GREEN)
	_send_trade_message.rpc_id(b_id, "Trade completed successfully!", Color.GREEN)

	trade_completed.emit(a_id, b_id)
	print("TradeManager: Trade %d completed" % trade_id)
	_end_trade(trade_id)


func _end_trade(trade_id: int) -> void:
	if not _active_trades.has(trade_id):
		return
	var trade: Dictionary = _active_trades[trade_id]
	_player_trade_map.erase(trade.player_a)
	_player_trade_map.erase(trade.player_b)
	_active_trades.erase(trade_id)


## Called when a player disconnects — cancel their active trade
func handle_player_disconnect(player_id: int) -> void:
	if _player_trade_map.has(player_id):
		var trade_id: int = _player_trade_map[player_id]
		var trade: Dictionary = _active_trades[trade_id]
		var other_id: int = trade.player_b if trade.player_a == player_id else trade.player_a
		_send_trade_message.rpc_id(other_id, "Trade cancelled — partner disconnected.", Color.RED)
		_end_trade(trade_id)
	_pending_requests.erase(player_id)
