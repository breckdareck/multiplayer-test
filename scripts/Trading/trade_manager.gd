extends Node

signal trade_started(trade_id: int, player_a: int, player_b: int)
signal trade_updated(trade_id: int)
signal trade_completed(trade_id: int)
signal trade_cancelled(trade_id: int)

var _active_trades: Dictionary = {}
var _player_trade_map: Dictionary = {}
var _next_trade_id: int = 1

const MAX_TRADE_SLOTS: int = 8


func request_trade(initiator_id: int, target_id: int) -> int:
	if not multiplayer.is_server():
		return -1

	if _player_trade_map.has(initiator_id):
		#print("TradeManager: Player %d is already in a trade." % initiator_id)
		return -1
	if _player_trade_map.has(target_id):
		#print("TradeManager: Target %d is already in a trade." % target_id)
		return -1

	var trade_id := _next_trade_id
	_next_trade_id += 1

	var session := {
		"trade_id": trade_id,
		"player_a": initiator_id,
		"player_b": target_id,
		"offer_a": {"items": [], "gold": 0},
		"offer_b": {"items": [], "gold": 0},
		"confirmed_a": false,
		"confirmed_b": false,
		"is_bot_trade": BotManager.is_bot(target_id),
	}

	_active_trades[trade_id] = session
	_player_trade_map[initiator_id] = trade_id
	_player_trade_map[target_id] = trade_id

	#print("TradeManager: Trade %d started between %d and %d." % [trade_id, initiator_id, target_id])
	trade_started.emit(trade_id, initiator_id, target_id)

	if not BotManager.is_bot(initiator_id):
		_sync_trade_to_client(initiator_id, trade_id)

	return trade_id


func add_item_to_trade(player_id: int, slot_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return false

	var session: Dictionary = _active_trades[trade_id]
	var offer_key := "offer_a" if session.player_a == player_id else "offer_b"
	var offer: Dictionary = session[offer_key]

	if offer.items.size() >= MAX_TRADE_SLOTS:
		return false

	var player_node := PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.inventory_component):
		return false

	var slots := player_node.inventory_component.get_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false

	var slot = slots[slot_index]
	if not slot.item:
		return false

	for existing in offer.items:
		if existing.slot_index == slot_index:
			return false

	offer.items.append({"slot_index": slot_index, "item_id": slot.item.item_id, "item_name": slot.item.name})

	session.confirmed_a = false
	session.confirmed_b = false

	_sync_trade_to_client(session.player_a, trade_id)
	trade_updated.emit(trade_id)
	return true


func remove_item_from_trade(player_id: int, trade_slot_index: int) -> bool:
	if not multiplayer.is_server():
		return false
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return false

	var session: Dictionary = _active_trades[trade_id]
	var offer_key := "offer_a" if session.player_a == player_id else "offer_b"
	var offer: Dictionary = session[offer_key]

	if trade_slot_index < 0 or trade_slot_index >= offer.items.size():
		return false

	offer.items.remove_at(trade_slot_index)
	session.confirmed_a = false
	session.confirmed_b = false

	_sync_trade_to_client(session.player_a, trade_id)
	trade_updated.emit(trade_id)
	return true


func set_trade_gold(player_id: int, amount: int) -> bool:
	if not multiplayer.is_server():
		return false
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return false

	var session: Dictionary = _active_trades[trade_id]
	var offer_key := "offer_a" if session.player_a == player_id else "offer_b"

	var player_node := PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.player_inventory):
		return false

	amount = clampi(amount, 0, player_node.player_inventory.monies_amount)
	session[offer_key].gold = amount
	session.confirmed_a = false
	session.confirmed_b = false

	_sync_trade_to_client(session.player_a, trade_id)
	trade_updated.emit(trade_id)
	return true


func confirm_trade(player_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return false

	var session: Dictionary = _active_trades[trade_id]
	if session.player_a == player_id:
		session.confirmed_a = true
	else:
		session.confirmed_b = true

	if session.is_bot_trade:
		session.confirmed_b = _bot_evaluate_trade(trade_id)
		if not session.confirmed_b:
			#print("TradeManager: Bot rejected trade %d." % trade_id)
			_sync_trade_to_client(session.player_a, trade_id)
			return false

	if session.confirmed_a and session.confirmed_b:
		_execute_trade(trade_id)
		return true

	_sync_trade_to_client(session.player_a, trade_id)
	trade_updated.emit(trade_id)
	return true


func cancel_trade(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return

	var session: Dictionary = _active_trades[trade_id]
	#print("TradeManager: Trade %d cancelled by %d." % [trade_id, player_id])

	_player_trade_map.erase(session.player_a)
	_player_trade_map.erase(session.player_b)
	_active_trades.erase(trade_id)

	if not BotManager.is_bot(session.player_a):
		_client_trade_closed.rpc_id(session.player_a, "Trade cancelled.")
	if not BotManager.is_bot(session.player_b):
		_client_trade_closed.rpc_id(session.player_b, "Trade cancelled.")

	trade_cancelled.emit(trade_id)


func _execute_trade(trade_id: int) -> void:
	var session: Dictionary = _active_trades[trade_id]
	var node_a := PlayerManager.get_player_node(session.player_a)
	var node_b := PlayerManager.get_player_node(session.player_b)

	if not is_instance_valid(node_a) or not is_instance_valid(node_b):
		cancel_trade(session.player_a)
		return

	var inv_a: InventoryComponent = node_a.inventory_component
	var inv_b: InventoryComponent = node_b.inventory_component
	var pinv_a: PlayerInventory = node_a.player_inventory
	var pinv_b: PlayerInventory = node_b.player_inventory

	if not is_instance_valid(inv_a) or not is_instance_valid(inv_b):
		cancel_trade(session.player_a)
		return

	var offer_a: Dictionary = session.offer_a
	var offer_b: Dictionary = session.offer_b

	# Collect actual items from slots before removing
	var items_from_a: Array = []
	var slots_a := inv_a.get_slots()
	for entry in offer_a.items:
		var idx: int = entry.slot_index
		if idx >= 0 and idx < slots_a.size() and slots_a[idx].item:
			items_from_a.append(slots_a[idx].item)

	var items_from_b: Array = []
	var slots_b := inv_b.get_slots()
	for entry in offer_b.items:
		var idx: int = entry.slot_index
		if idx >= 0 and idx < slots_b.size() and slots_b[idx].item:
			items_from_b.append(slots_b[idx].item)

	# Remove items from sources
	for item in items_from_a:
		inv_a.remove_item(item, "traded")
	for item in items_from_b:
		inv_b.remove_item(item, "traded")

	# Add items to recipients
	for item in items_from_a:
		inv_b.server_add_item_instance(item.to_dictionary())
	for item in items_from_b:
		inv_a.server_add_item_instance(item.to_dictionary())

	# Transfer gold
	if offer_a.gold > 0:
		pinv_a.monies_amount -= offer_a.gold
		pinv_b.monies_amount += offer_a.gold
	if offer_b.gold > 0:
		pinv_b.monies_amount -= offer_b.gold
		pinv_a.monies_amount += offer_b.gold

	#print("TradeManager: Trade %d completed. %d items A→B, %d items B→A, gold A→B: %d, B→A: %d" % [trade_id, items_from_a.size(), items_from_b.size(), offer_a.gold, offer_b.gold])

	_player_trade_map.erase(session.player_a)
	_player_trade_map.erase(session.player_b)
	_active_trades.erase(trade_id)

	if not BotManager.is_bot(session.player_a):
		_client_trade_closed.rpc_id(session.player_a, "Trade completed!")
	if not BotManager.is_bot(session.player_b):
		_client_trade_closed.rpc_id(session.player_b, "Trade completed!")

	trade_completed.emit(trade_id)


func _bot_evaluate_trade(trade_id: int) -> bool:
	var session: Dictionary = _active_trades[trade_id]
	var bot_id: int = session.player_b
	var bot_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(bot_node):
		return false

	var class_type: Constants.ClassType = Constants.ClassType.BEGINNER
	if is_instance_valid(bot_node.class_component):
		class_type = bot_node.class_component.current_class

	var offer_a: Dictionary = session.offer_a
	var offer_b: Dictionary = session.offer_b

	# Score incoming items (what bot receives)
	var incoming_value: float = float(offer_a.gold)
	var inv_a := PlayerManager.get_player_node(session.player_a).inventory_component
	var slots_a := inv_a.get_slots()
	for entry in offer_a.items:
		var idx: int = entry.slot_index
		if idx >= 0 and idx < slots_a.size() and slots_a[idx].item:
			var score := BotEquipmentLogic.score_item(slots_a[idx].item, class_type)
			incoming_value += maxf(score, 0.0) * 10.0

	# Score outgoing items (what bot gives away)
	var outgoing_value: float = float(offer_b.gold)
	var inv_b := bot_node.inventory_component
	var slots_b := inv_b.get_slots()
	for entry in offer_b.items:
		var idx: int = entry.slot_index
		if idx >= 0 and idx < slots_b.size() and slots_b[idx].item:
			var score := BotEquipmentLogic.score_item(slots_b[idx].item, class_type)
			outgoing_value += maxf(score, 0.0) * 10.0

	return incoming_value >= outgoing_value


func _sync_trade_to_client(player_id: int, trade_id: int) -> void:
	if BotManager.is_bot(player_id):
		return

	var session: Dictionary = _active_trades.get(trade_id, {})
	if session.is_empty():
		return

	var data := {
		"trade_id": trade_id,
		"partner_id": session.player_b if session.player_a == player_id else session.player_a,
		"my_offer": session.offer_a if session.player_a == player_id else session.offer_b,
		"partner_offer": session.offer_b if session.player_a == player_id else session.offer_a,
		"my_confirmed": session.confirmed_a if session.player_a == player_id else session.confirmed_b,
		"partner_confirmed": session.confirmed_b if session.player_a == player_id else session.confirmed_a,
		"is_bot_trade": session.is_bot_trade,
	}

	# Add partner name
	var partner_id: int = data.partner_id
	if BotManager.is_bot(partner_id) and partner_id in BotManager.active_bots:
		data["partner_name"] = BotManager.active_bots[partner_id].username
	else:
		var pinfo = PlayerManager.get_player_info(partner_id)
		data["partner_name"] = pinfo.get("username", str(partner_id))

	_client_receive_trade_data.rpc_id(player_id, data)


# --- RPCs ---

@rpc("any_peer", "call_local", "reliable")
func rpc_request_trade(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	var target_id := PlayerManager.get_player_id_from_name(target_name)
	if target_id == -1:
		# Check bot names
		for bot_id in BotManager.active_bots:
			if BotManager.active_bots[bot_id].username.to_lower() == target_name.to_lower():
				target_id = bot_id
				break
	if target_id == -1:
		return

	request_trade(sender_id, target_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_add_item(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	add_item_to_trade(sender_id, slot_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_remove_item(trade_slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	remove_item_from_trade(sender_id, trade_slot_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_gold(amount: int) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	set_trade_gold(sender_id, amount)


@rpc("any_peer", "call_local", "reliable")
func rpc_confirm_trade() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	confirm_trade(sender_id)


@rpc("any_peer", "call_local", "reliable")
func rpc_cancel_trade() -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	cancel_trade(sender_id)


var _trade_window: TradeWindow = null


func _get_or_create_trade_window() -> TradeWindow:
	if is_instance_valid(_trade_window):
		return _trade_window
	_trade_window = TradeWindow.create()
	var local_player := PlayerManager.get_player_node(multiplayer.get_unique_id())
	if is_instance_valid(local_player):
		var container = local_player.get_node_or_null("CanvasLayer/MoveableWindows")
		if container:
			container.add_child(_trade_window)
			return _trade_window
	# Fallback: add to scene tree root
	get_tree().current_scene.add_child(_trade_window)
	return _trade_window


@rpc("authority", "call_local", "reliable")
func _client_receive_trade_data(data: Dictionary) -> void:
	var target_id: int = data.get("partner_id", -1)
	if target_id == -1:
		return
	var window := _get_or_create_trade_window()
	window.show_for_target(target_id)


@rpc("authority", "call_local", "reliable")
func _client_trade_closed(message: String) -> void:
	if is_instance_valid(_trade_window):
		_trade_window.visible = false
	if not message.is_empty():
		ChatManager.add_system_message(message, Color.CYAN)
