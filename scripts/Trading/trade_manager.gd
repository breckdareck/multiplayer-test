extends Node

## Server-authoritative player-to-player trading.
##
## Two trade flows live here:
##  * Player <-> Player — a proximity-gated, dual-confirmation offer/swap session.
##    A player sends a trade request; the target accepts; both place items/gold
##    into their offer; both press Confirm; the server atomically swaps.
##  * Player <-> Bot — an instant give/take used by the bot trade window.
##    Bots have no client, so there is no offer/confirm step — and no proximity
##    check, since bots roam constantly and an area gate makes them impractical
##    to trade with.
##
## All inventory mutations happen on the server. Clients only send intent
## (request / accept / decline / offer item / set gold / confirm / cancel).

signal trade_started(trade_id: int, player_a: int, player_b: int)
signal trade_updated(trade_id: int)
signal trade_completed(trade_id: int)
signal trade_cancelled(trade_id: int)

## Client-side signals consumed by the trade UI.
signal trade_request_received(requester_id: int, requester_name: String)
signal trade_session_opened(partner_id: int, partner_name: String)
signal trade_session_updated(data: Dictionary)
signal trade_session_closed(message: String)

var _active_trades: Dictionary = {}        # trade_id -> session Dictionary
var _player_trade_map: Dictionary = {}     # player_id -> trade_id
var _pending_requests: Dictionary = {}     # target_id -> requester_id
var _next_trade_id: int = 1

const MAX_TRADE_SLOTS: int = 8
## Maximum world-space distance between two players for a trade to start/continue.
const TRADE_RANGE: float = 120.0
## Squared range — avoids a sqrt on the per-frame proximity check.
const TRADE_RANGE_SQ: float = TRADE_RANGE * TRADE_RANGE
## How often the server re-checks that both traders are still in range.
const PROXIMITY_CHECK_INTERVAL: float = 0.5

var _proximity_timer: float = 0.0


func _process(delta: float) -> void:
	# has_multiplayer_peer() first: after a disconnect the peer is null and
	# multiplayer.is_server() calls get_unique_id() internally, which errors with
	# no peer. Guard the whole chain.
	if not multiplayer.has_multiplayer_peer() or not multiplayer.is_server() or _active_trades.is_empty():
		return
	_proximity_timer += delta
	if _proximity_timer < PROXIMITY_CHECK_INTERVAL:
		return
	_proximity_timer = 0.0
	_enforce_proximity()


#=============================================================================
# PLAYER <-> PLAYER: REQUEST / ACCEPT
#=============================================================================

## [SERVER] A player asks another nearby player to trade. Returns true if the
## request was sent. Bot targets skip the request step entirely.
func request_trade(initiator_id: int, target_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if initiator_id == target_id:
		return false

	# Bots have no client/UI — go straight to an instant give/take session.
	if BotManager.is_bot(target_id):
		return _start_bot_trade(initiator_id, target_id)

	if _player_trade_map.has(initiator_id):
		_notify_player(initiator_id, "You are already trading.", Color.ORANGE)
		return false
	if _player_trade_map.has(target_id):
		_notify_player(initiator_id, "That player is already trading.", Color.ORANGE)
		return false
	if _pending_requests.has(target_id):
		_notify_player(initiator_id, "That player has a pending trade request.", Color.ORANGE)
		return false

	if not _players_in_range(initiator_id, target_id):
		_notify_player(initiator_id, "You must be closer to trade.", Color.ORANGE)
		return false

	# One outgoing request per player — drop any earlier unanswered one.
	for pending_target in _pending_requests.keys():
		if _pending_requests[pending_target] == initiator_id:
			_pending_requests.erase(pending_target)

	_pending_requests[target_id] = initiator_id
	var initiator_name := _get_player_name(initiator_id)
	_client_receive_trade_request.rpc_id(target_id, initiator_id, initiator_name)
	_notify_player(initiator_id, "Trade request sent to %s." % _get_player_name(target_id), Color.CYAN)
	return true


## [SERVER] The target accepts a pending trade request, opening a session.
func accept_trade_request(target_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	var initiator_id: int = _pending_requests.get(target_id, -1)
	if initiator_id == -1:
		return false
	_pending_requests.erase(target_id)

	# Re-validate: either side may have started another trade, or moved away.
	if _player_trade_map.has(initiator_id) or _player_trade_map.has(target_id):
		_notify_player(target_id, "Trade no longer available.", Color.ORANGE)
		return false
	if not _players_in_range(initiator_id, target_id):
		_notify_player(initiator_id, "Trade partner moved out of range.", Color.ORANGE)
		_notify_player(target_id, "Trade partner moved out of range.", Color.ORANGE)
		return false

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
	}
	_active_trades[trade_id] = session
	_player_trade_map[initiator_id] = trade_id
	_player_trade_map[target_id] = trade_id

	trade_started.emit(trade_id, initiator_id, target_id)
	_open_session_for(initiator_id, trade_id)
	_open_session_for(target_id, trade_id)
	_sync_trade_to_client(initiator_id, trade_id)
	_sync_trade_to_client(target_id, trade_id)
	return true


## [SERVER] The target declines a pending trade request.
func decline_trade_request(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	var initiator_id: int = _pending_requests.get(target_id, -1)
	if initiator_id == -1:
		return
	_pending_requests.erase(target_id)
	_notify_player(initiator_id, "%s declined your trade request." % _get_player_name(target_id), Color.ORANGE)


#=============================================================================
# PLAYER <-> PLAYER: OFFER MANIPULATION
#=============================================================================

## [SERVER] Places the item in inventory `slot_index` into the player's offer.
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
		_notify_player(player_id, "Trade offer is full.", Color.ORANGE)
		return false

	var player_node := PlayerManager.get_player_node(player_id)
	if not is_instance_valid(player_node) or not is_instance_valid(player_node.inventory_component):
		return false

	var slots: Array = player_node.inventory_component.get_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return false

	var slot: SlotData = slots[slot_index]
	if not slot.item:
		return false

	# A slot may only be offered once.
	for existing in offer.items:
		if existing.slot_index == slot_index:
			return false

	offer.items.append({
		"slot_index": slot_index,
		"item_id": slot.item.item_id,
		"item_name": slot.item.name,
	})

	_reset_confirmations(session)
	_sync_both(trade_id)
	trade_updated.emit(trade_id)
	return true


## [SERVER] Removes the entry at `trade_slot_index` from the player's offer.
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
	_reset_confirmations(session)
	_sync_both(trade_id)
	trade_updated.emit(trade_id)
	return true


## [SERVER] Sets the amount of gold the player offers, clamped to what they own.
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
	# A no-op set (e.g. the gold field losing focus on Confirm with an
	# unchanged value) must not reset confirmations — only a real change does.
	if session[offer_key].gold == amount:
		return true
	session[offer_key].gold = amount
	_reset_confirmations(session)
	_sync_both(trade_id)
	trade_updated.emit(trade_id)
	return true


## [SERVER] Marks a player as having confirmed their offer. When both sides have
## confirmed, the trade executes. Any later offer change resets confirmations.
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

	if session.confirmed_a and session.confirmed_b:
		_execute_trade(trade_id)
		return true

	_sync_both(trade_id)
	trade_updated.emit(trade_id)
	return true


## [SERVER] Clears a confirmation without touching the offer (an "unconfirm").
func unconfirm_trade(player_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		return false
	var session: Dictionary = _active_trades[trade_id]
	_reset_confirmations(session)
	_sync_both(trade_id)
	trade_updated.emit(trade_id)
	return true


## [SERVER] Cancels a trade. Offered items were never removed, so there is
## nothing to return — the session is simply discarded.
func cancel_trade(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id == -1:
		# The player may have an outstanding request rather than a live session.
		_cancel_pending_for(player_id)
		return

	_close_session(trade_id, "Trade cancelled.")
	trade_cancelled.emit(trade_id)


## Drops any pending request that names `player_id` as initiator or target.
func _cancel_pending_for(player_id: int) -> void:
	if _pending_requests.has(player_id):
		_pending_requests.erase(player_id)
	for target_id in _pending_requests.keys():
		if _pending_requests[target_id] == player_id:
			_pending_requests.erase(target_id)


#=============================================================================
# PLAYER <-> PLAYER: EXECUTION
#=============================================================================

## Validates both inventories still hold the offered items (and enough gold),
## then atomically swaps items and gold between the two players.
func _execute_trade(trade_id: int) -> void:
	var session: Dictionary = _active_trades.get(trade_id, {})
	if session.is_empty():
		return

	var node_a := PlayerManager.get_player_node(session.player_a)
	var node_b := PlayerManager.get_player_node(session.player_b)
	if not is_instance_valid(node_a) or not is_instance_valid(node_b):
		_close_session(trade_id, "Trade failed: partner unavailable.")
		return

	var inv_a: InventoryComponent = node_a.inventory_component
	var inv_b: InventoryComponent = node_b.inventory_component
	var pinv_a: PlayerInventory = node_a.player_inventory
	var pinv_b: PlayerInventory = node_b.player_inventory
	if not (is_instance_valid(inv_a) and is_instance_valid(inv_b) \
			and is_instance_valid(pinv_a) and is_instance_valid(pinv_b)):
		_close_session(trade_id, "Trade failed: inventory unavailable.")
		return

	# Re-check proximity at the moment of execution.
	if not _players_in_range(session.player_a, session.player_b):
		_close_session(trade_id, "Trade failed: partner out of range.")
		return

	var offer_a: Dictionary = session.offer_a
	var offer_b: Dictionary = session.offer_b

	# --- VALIDATE: offered items still exist in the named slots ---
	var items_from_a := _collect_offered_items(inv_a, offer_a.items)
	if items_from_a.is_empty() and not offer_a.items.is_empty():
		_close_session(trade_id, "Trade failed: an offered item is missing.")
		return
	var items_from_b := _collect_offered_items(inv_b, offer_b.items)
	if items_from_b.is_empty() and not offer_b.items.is_empty():
		_close_session(trade_id, "Trade failed: an offered item is missing.")
		return

	# --- VALIDATE: enough gold on hand ---
	if pinv_a.monies_amount < offer_a.gold or pinv_b.monies_amount < offer_b.gold:
		_close_session(trade_id, "Trade failed: not enough gold.")
		return

	# --- VALIDATE: receiving side has type-appropriate space for the items ---
	# Each side frees its own offered slots before receiving them, so the check
	# simulates the swap against the post-removal slot layout.
	if not _can_receive(inv_a, items_from_b, items_from_a) \
			or not _can_receive(inv_b, items_from_a, items_from_b):
		_close_session(trade_id, "Trade failed: not enough inventory space.")
		return

	# --- COMMIT: all validation passed, perform the swap atomically ---
	# Snapshot item dictionaries before removal (removal mutates the slot data).
	var dicts_from_a: Array = []
	for item in items_from_a:
		dicts_from_a.append(item.to_dictionary())
	var dicts_from_b: Array = []
	for item in items_from_b:
		dicts_from_b.append(item.to_dictionary())

	for item in items_from_a:
		inv_a.remove_item(item, "traded")
	for item in items_from_b:
		inv_b.remove_item(item, "traded")

	for item_dict in dicts_from_a:
		inv_b.server_add_item_instance(item_dict)
	for item_dict in dicts_from_b:
		inv_a.server_add_item_instance(item_dict)

	if offer_a.gold > 0:
		pinv_a.monies_amount -= offer_a.gold
		pinv_b.monies_amount += offer_a.gold
	if offer_b.gold > 0:
		pinv_b.monies_amount -= offer_b.gold
		pinv_a.monies_amount += offer_b.gold

	_player_trade_map.erase(session.player_a)
	_player_trade_map.erase(session.player_b)
	_active_trades.erase(trade_id)

	_client_trade_closed.rpc_id(session.player_a, "Trade completed!")
	_client_trade_closed.rpc_id(session.player_b, "Trade completed!")
	trade_completed.emit(trade_id)


## Simulates whether `incoming` items can land in `inv` after `outgoing` items
## have been removed from it. Respects per-slot item-type restrictions and
## stacking so the check matches what server_add_item_instance will actually do.
func _can_receive(inv: InventoryComponent, incoming: Array, outgoing: Array) -> bool:
	if incoming.is_empty():
		return true

	# Model the inventory as a list of cells after the outgoing removals.
	# Each cell tracks its slot type, occupied item name (or "" if empty) and
	# remaining stack space, so stacking is simulated accurately.
	var sim: Array = []
	var outgoing_set := {}
	for item in outgoing:
		outgoing_set[item] = true

	for sd in inv.get_slots():
		var held: ItemData = sd.item
		# A slot whose item is being traded away counts as empty.
		if held != null and outgoing_set.has(held):
			held = null
		var cell := {
			"type": sd.allowed_item_type,
			"name": "" if held == null else held.name,
			"space": 0,
		}
		if held != null and held.can_stack:
			cell.space = held.max_stack_amount - held.current_stack_amount
		sim.append(cell)

	for item in incoming:
		var remaining: int = item.current_stack_amount if item.can_stack else 1
		# Fill existing same-named stacks first.
		if item.can_stack:
			for cell in sim:
				if remaining <= 0:
					break
				if cell.name == item.name and cell.space > 0:
					var used: int = mini(remaining, cell.space)
					cell.space -= used
					remaining -= used
		# Then drop the rest into empty, type-compatible slots.
		while remaining > 0:
			var slotted := false
			for cell in sim:
				if cell.name != "":
					continue
				if cell.type != Constants.ItemType.ANY and cell.type != item.item_type:
					continue
				cell.name = item.name
				cell.space = (item.max_stack_amount - mini(remaining, item.max_stack_amount)) if item.can_stack else 0
				remaining -= (mini(remaining, item.max_stack_amount) if item.can_stack else 1)
				slotted = true
				break
			if not slotted:
				return false
	return true


## Resolves an offer's slot entries to the live ItemData objects. Returns an
## empty Array if any entry no longer points at its expected item.
func _collect_offered_items(inv: InventoryComponent, offer_items: Array) -> Array:
	var result: Array = []
	var slots: Array = inv.get_slots()
	for entry in offer_items:
		var idx: int = entry.slot_index
		if idx < 0 or idx >= slots.size():
			return []
		var slot: SlotData = slots[idx]
		# The slot must still hold the same item the player offered.
		if not slot.item or slot.item.item_id != entry.item_id:
			return []
		result.append(slot.item)
	return result


#=============================================================================
# PROXIMITY
#=============================================================================

## True when both players exist, share a map, and are within TRADE_RANGE.
func _players_in_range(id_a: int, id_b: int) -> bool:
	var node_a := PlayerManager.get_player_node(id_a)
	var node_b := PlayerManager.get_player_node(id_b)
	if not is_instance_valid(node_a) or not is_instance_valid(node_b):
		return false
	if MapManager.get_player_map(id_a) != MapManager.get_player_map(id_b):
		return false
	return node_a.global_position.distance_squared_to(node_b.global_position) <= TRADE_RANGE_SQ


## Cancels any active trade whose partners have drifted out of range.
func _enforce_proximity() -> void:
	for trade_id in _active_trades.keys():
		var session: Dictionary = _active_trades[trade_id]
		if not _players_in_range(session.player_a, session.player_b):
			_close_session(trade_id, "Trade cancelled: partner out of range.")
			trade_cancelled.emit(trade_id)


#=============================================================================
# BOT TRADE (instant give/take — no offer/confirm step)
#=============================================================================

## Opens the instant bot-trade window on the requesting client. Bots have no
## offer/confirm flow; items move one at a time through _transfer_trade_item.
## Not proximity-gated: bots never stop moving, so a range check makes them
## impractical to trade with. Player-to-player trades remain proximity-gated.
func _start_bot_trade(initiator_id: int, bot_id: int) -> bool:
	if BotManager.is_bot(initiator_id):
		return false
	_client_open_bot_trade.rpc_id(initiator_id, bot_id)
	return true


## [Client/Host -> Server] Immediately moves one item between the requesting
## player and a bot. The bot trade window has no offer/confirm step, so the
## transfer runs server-side where every inventory is authoritative.
@rpc("any_peer", "call_local", "reliable")
func rpc_transfer_trade_item(target_id: int, slot_index: int, giving: bool) -> void:
	if not multiplayer.is_server():
		return
	var sender_id := multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	_transfer_trade_item(sender_id, target_id, slot_index, giving)


## Moves one item between `player_id` and a bot `target_id`. `giving` true =>
## player gives to the bot; false => player takes from the bot.
func _transfer_trade_item(player_id: int, target_id: int, slot_index: int, giving: bool) -> void:
	# This RPC only ever trades with bots — gating here stops it being abused
	# to move items in or out of another real player's inventory.
	if not BotManager.is_bot(target_id):
		return

	var player_node := PlayerManager.get_player_node(player_id)
	var target_node := PlayerManager.get_player_node(target_id)
	if not is_instance_valid(player_node) or not is_instance_valid(target_node):
		return

	var player_inv: InventoryComponent = player_node.inventory_component
	var target_inv: InventoryComponent = target_node.inventory_component
	if not is_instance_valid(player_inv) or not is_instance_valid(target_inv):
		return

	var source_inv: InventoryComponent = player_inv if giving else target_inv
	var dest_inv: InventoryComponent = target_inv if giving else player_inv

	var src_slots := source_inv.get_slots()
	if slot_index < 0 or slot_index >= src_slots.size():
		return
	var slot: SlotData = src_slots[slot_index]
	if not slot.item:
		return

	# Check space before removing — a full destination would otherwise destroy
	# the item (the remove succeeds but the add silently fails).
	if dest_inv.get_empty_slots().is_empty():
		var msg := "Their inventory is full." if giving else "Your inventory is full."
		_notify_player(player_id, msg, Color.ORANGE)
		return

	var item: ItemData = slot.item
	source_inv.remove_item(item, "traded")
	dest_inv.server_add_item_instance(item.to_dictionary())


#=============================================================================
# SYNC HELPERS
#=============================================================================

func _reset_confirmations(session: Dictionary) -> void:
	session.confirmed_a = false
	session.confirmed_b = false


func _sync_both(trade_id: int) -> void:
	var session: Dictionary = _active_trades.get(trade_id, {})
	if session.is_empty():
		return
	_sync_trade_to_client(session.player_a, trade_id)
	_sync_trade_to_client(session.player_b, trade_id)


## Sends one player their view of the trade (their offer, partner's offer,
## both confirmation flags). Includes partner-item display data because a
## client has no authoritative copy of the partner's inventory.
func _sync_trade_to_client(player_id: int, trade_id: int) -> void:
	var session: Dictionary = _active_trades.get(trade_id, {})
	if session.is_empty():
		return

	var is_a = session.player_a == player_id
	var partner_id: int = session.player_b if is_a else session.player_a

	var data := {
		"trade_id": trade_id,
		"partner_id": partner_id,
		"partner_name": _get_player_name(partner_id),
		# The player's own offer carries slot indices so the client can mark
		# those inventory slots as already-offered without local guesswork.
		"my_offer": _offer_display(session.player_a if is_a else session.player_b,
				session.offer_a if is_a else session.offer_b, true),
		"partner_offer": _offer_display(partner_id,
				session.offer_b if is_a else session.offer_a, false),
		"my_confirmed": session.confirmed_a if is_a else session.confirmed_b,
		"partner_confirmed": session.confirmed_b if is_a else session.confirmed_a,
	}
	_client_receive_trade_data.rpc_id(player_id, data)


## Builds a display-ready offer: each item carries its full dictionary so the
## recipient client can render an item it does not own. When `with_slots` is
## true, each item dictionary also carries a "trade_slot_index" field — the
## owner's inventory slot — so the owning client knows which slots are offered.
func _offer_display(owner_id: int, offer: Dictionary, with_slots: bool) -> Dictionary:
	var node := PlayerManager.get_player_node(owner_id)
	var items: Array = []
	if is_instance_valid(node) and is_instance_valid(node.inventory_component):
		var slots: Array = node.inventory_component.get_slots()
		for entry in offer.items:
			var idx: int = entry.slot_index
			var item_dict: Dictionary
			if idx >= 0 and idx < slots.size() and slots[idx].item:
				item_dict = slots[idx].item.to_dictionary()
			else:
				# Item vanished (e.g. dropped) — show a placeholder by name.
				item_dict = {"name": entry.item_name}
			if with_slots:
				item_dict["trade_slot_index"] = idx
			items.append(item_dict)
	return {"items": items, "gold": offer.gold}


## Removes a trade session and tells both clients to close their window.
func _close_session(trade_id: int, message: String) -> void:
	var session: Dictionary = _active_trades.get(trade_id, {})
	if session.is_empty():
		return
	_player_trade_map.erase(session.player_a)
	_player_trade_map.erase(session.player_b)
	_active_trades.erase(trade_id)
	if not BotManager.is_bot(session.player_a):
		_client_trade_closed.rpc_id(session.player_a, message)
	if not BotManager.is_bot(session.player_b):
		_client_trade_closed.rpc_id(session.player_b, message)


func _open_session_for(player_id: int, trade_id: int) -> void:
	if BotManager.is_bot(player_id):
		return
	var session: Dictionary = _active_trades[trade_id]
	var partner_id: int = session.player_b if session.player_a == player_id else session.player_a
	_client_open_session.rpc_id(player_id, partner_id, _get_player_name(partner_id))


func _get_player_name(player_id: int) -> String:
	var node := PlayerManager.get_player_node(player_id)
	if is_instance_valid(node) and not node.username.is_empty():
		return node.username
	if BotManager.is_bot(player_id) and player_id in BotManager.active_bots:
		return BotManager.active_bots[player_id].get("username", "Bot %d" % player_id)
	var info: Dictionary = PlayerManager.get_player_info(player_id)
	return info.get("username", str(player_id))


## Sends a system message to a player — directly if it is the host, else by RPC.
## Delegates to the canonical server->peer seam (CHAT surface).
func _notify_player(player_id: int, message: String, color: Color) -> void:
	ChatManager.notify_peer(player_id, message, color, ChatManager.NotifySurface.CHAT)


#=============================================================================
# DISCONNECT HANDLING
#=============================================================================

## Called by PlayerManager when a peer disconnects. Tears down any trade or
## pending request the player was involved in.
func handle_player_disconnect(player_id: int) -> void:
	if not multiplayer.is_server():
		return
	_cancel_pending_for(player_id)
	var trade_id: int = _player_trade_map.get(player_id, -1)
	if trade_id != -1:
		_close_session(trade_id, "Trade cancelled: partner disconnected.")
		trade_cancelled.emit(trade_id)


#=============================================================================
# RPCs — CLIENT -> SERVER (intent only)
#=============================================================================

func _sender() -> int:
	var sender_id := multiplayer.get_remote_sender_id()
	return sender_id if sender_id != 0 else multiplayer.get_unique_id()


## [CLIENT -> SERVER] Request a trade with a target by name (legacy / chat path).
@rpc("any_peer", "call_local", "reliable")
func rpc_request_trade(target_name: String) -> void:
	if not multiplayer.is_server():
		return
	var target_id := PlayerManager.resolve_by_name(target_name)
	if target_id == -1:
		_notify_player(_sender(), "No player named '%s' found." % target_name, Color.ORANGE)
		return
	request_trade(_sender(), target_id)


## [CLIENT -> SERVER] Request a trade with a target by peer id (context menu).
@rpc("any_peer", "call_local", "reliable")
func rpc_request_trade_with_id(target_id: int) -> void:
	if not multiplayer.is_server():
		return
	request_trade(_sender(), target_id)


## [CLIENT -> SERVER] Accept an incoming trade request.
@rpc("any_peer", "call_local", "reliable")
func rpc_accept_trade_request() -> void:
	if not multiplayer.is_server():
		return
	accept_trade_request(_sender())


## [CLIENT -> SERVER] Decline an incoming trade request.
@rpc("any_peer", "call_local", "reliable")
func rpc_decline_trade_request() -> void:
	if not multiplayer.is_server():
		return
	decline_trade_request(_sender())


@rpc("any_peer", "call_local", "reliable")
func rpc_add_item(slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	add_item_to_trade(_sender(), slot_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_remove_item(trade_slot_index: int) -> void:
	if not multiplayer.is_server():
		return
	remove_item_from_trade(_sender(), trade_slot_index)


@rpc("any_peer", "call_local", "reliable")
func rpc_set_gold(amount: int) -> void:
	if not multiplayer.is_server():
		return
	set_trade_gold(_sender(), amount)


@rpc("any_peer", "call_local", "reliable")
func rpc_confirm_trade() -> void:
	if not multiplayer.is_server():
		return
	confirm_trade(_sender())


@rpc("any_peer", "call_local", "reliable")
func rpc_unconfirm_trade() -> void:
	if not multiplayer.is_server():
		return
	unconfirm_trade(_sender())


@rpc("any_peer", "call_local", "reliable")
func rpc_cancel_trade() -> void:
	if not multiplayer.is_server():
		return
	cancel_trade(_sender())


#=============================================================================
# RPCs — SERVER -> CLIENT
#=============================================================================

## [SERVER -> CLIENT] An incoming trade request — the UI shows an accept popup.
## call_local so a host targeted by a request also sees the popup.
@rpc("authority", "call_local", "reliable")
func _client_receive_trade_request(requester_id: int, requester_name: String) -> void:
	trade_request_received.emit(requester_id, requester_name)


## [SERVER -> CLIENT] A trade session has opened — the UI shows the trade window.
@rpc("authority", "call_local", "reliable")
func _client_open_session(partner_id: int, partner_name: String) -> void:
	trade_session_opened.emit(partner_id, partner_name)


## [SERVER -> CLIENT] Authoritative trade state — the UI refreshes both offers.
@rpc("authority", "call_local", "reliable")
func _client_receive_trade_data(data: Dictionary) -> void:
	trade_session_updated.emit(data)


## [SERVER -> CLIENT] The trade has ended (completed / cancelled / failed).
@rpc("authority", "call_local", "reliable")
func _client_trade_closed(message: String) -> void:
	trade_session_closed.emit(message)
	if not message.is_empty():
		ChatManager.add_system_message(message, Color.CYAN)


## [SERVER -> CLIENT] Opens the instant bot-trade window on the requester.
@rpc("authority", "call_local", "reliable")
func _client_open_bot_trade(bot_id: int) -> void:
	var window := _get_or_create_bot_trade_window()
	if is_instance_valid(window):
		window.show_for_target(bot_id)


#=============================================================================
# BOT TRADE WINDOW (client-side helper)
#=============================================================================

var _bot_trade_window: TradeWindow = null


func _get_or_create_bot_trade_window() -> TradeWindow:
	if is_instance_valid(_bot_trade_window):
		return _bot_trade_window
	_bot_trade_window = TradeWindow.create_bot_window()
	# Mount in the persistent LocalPlayerUI (ADR 0009 Stage B); fall back to the
	# current scene if it isn't up yet.
	var container = MapManager.get_local_ui_moveable_windows()
	if is_instance_valid(container):
		container.add_child(_bot_trade_window)
		return _bot_trade_window
	get_tree().current_scene.add_child(_bot_trade_window)
	return _bot_trade_window
