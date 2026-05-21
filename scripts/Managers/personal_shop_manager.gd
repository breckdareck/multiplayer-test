# personal_shop_manager.gd - AutoLoad singleton
# Server-authoritative personal shops for the Free Market zone.
#
# A player opens a personal shop by listing items from their inventory with a
# coin price. Other players nearby can browse a read-only view and buy items.
# All coin/item transfers happen on the server; clients only send intents.
extends Node

## Emitted on every peer when the set of open shops changes (a shop opens or
## closes). The UI uses this to refresh "Browse Shop" availability.
signal shops_changed()

## Maximum number of distinct listings a single shop can hold.
const MAX_LISTINGS: int = 12

## Map id where personal shops are allowed to operate.
const FREE_MARKET_MAP: String = "free_market"

# === SERVER STATE ===
# { seller_id: { "shop_name": String, "listings": Array[Dictionary] } }
# Each listing: { "listing_id": int, "item": ItemData, "price": int }
var _shops: Dictionary = {}
var _next_listing_id: int = 1

# === CLIENT STATE ===
# Lightweight mirror so clients know which sellers have an open shop without
# leaking listing contents. { seller_id: shop_name }
var _open_shop_names: Dictionary = {}
# Seller id this client explicitly asked to browse; lets the next browse-data
# RPC open the window even though the same RPC is also used for push refreshes.
var _pending_browse: int = 0


# === HELPERS ===

func is_shop_open(seller_id: int) -> bool:
	if multiplayer.is_server():
		return _shops.has(seller_id)
	return _open_shop_names.has(seller_id)


func get_shop_name(seller_id: int) -> String:
	if multiplayer.is_server():
		return _shops.get(seller_id, {}).get("shop_name", "")
	return _open_shop_names.get(seller_id, "")


func _get_player(peer_id: int) -> Node:
	return PlayerManager.get_player_node(peer_id)


## Builds the slim, network-safe view of a shop's listings.
func _serialize_listings(seller_id: int) -> Array:
	var out: Array = []
	if not _shops.has(seller_id):
		return out
	for listing in _shops[seller_id].listings:
		var item: ItemData = listing.item
		out.append({
			"listing_id": listing.listing_id,
			"item": item.to_dictionary(),
			"price": listing.price,
		})
	return out


# === SERVER: SHOP LIFECYCLE ===

## [Client -> Server] Open (or rename) the caller's personal shop.
@rpc("any_peer", "call_local", "reliable")
func request_open_shop(shop_name: String) -> void:
	if not multiplayer.is_server():
		return
	var seller_id := multiplayer.get_remote_sender_id()
	if seller_id == 0:
		seller_id = multiplayer.get_unique_id()

	# Personal shops are a Free Market feature only.
	if MapManager.get_player_map(seller_id) != FREE_MARKET_MAP:
		_notify(seller_id, "You can only open a shop in the Free Market.", Color.ORANGE)
		return

	var clean_name := shop_name.strip_edges()
	if clean_name.is_empty():
		var p := _get_player(seller_id)
		clean_name = "%s's Shop" % (p.username if is_instance_valid(p) and not p.username.is_empty() else "Player")
	clean_name = clean_name.substr(0, 40)

	if not _shops.has(seller_id):
		_shops[seller_id] = {"shop_name": clean_name, "listings": []}
	else:
		_shops[seller_id].shop_name = clean_name

	_broadcast_shop_open_state(seller_id, true, clean_name)
	_sync_owner_shop(seller_id)


## [Client -> Server] Close the caller's personal shop. Unlisted items stay in
## the seller's inventory (they were never removed).
@rpc("any_peer", "call_local", "reliable")
func request_close_shop() -> void:
	if not multiplayer.is_server():
		return
	var seller_id := multiplayer.get_remote_sender_id()
	if seller_id == 0:
		seller_id = multiplayer.get_unique_id()
	_close_shop(seller_id)


func _close_shop(seller_id: int) -> void:
	if not multiplayer.is_server() or not _shops.has(seller_id):
		return

	# Return every held listing item to the seller so closing the shop never
	# destroys items. If the seller's node is gone (disconnect), the items are
	# still recorded in their inventory before the disconnect save flushes.
	var seller := _get_player(seller_id)
	if is_instance_valid(seller) and is_instance_valid(seller.inventory_component):
		for listing in _shops[seller_id].listings:
			seller.inventory_component.server_add_item_instance(listing.item.to_dictionary())

	_shops.erase(seller_id)
	_broadcast_shop_open_state(seller_id, false, "")
	if not BotManager.is_bot(seller_id):
		_client_shop_closed.rpc_id(seller_id)


## Called by PlayerManager / MapManager when a player disconnects or leaves the
## Free Market — their shop must not linger.
func handle_player_left(seller_id: int) -> void:
	if multiplayer.is_server():
		_close_shop(seller_id)


# === SERVER: LISTINGS ===

## [Client -> Server] List one unit of an inventory item for sale at `price`.
@rpc("any_peer", "call_local", "reliable")
func request_list_item(slot_index: int, price: int) -> void:
	if not multiplayer.is_server():
		return
	var seller_id := multiplayer.get_remote_sender_id()
	if seller_id == 0:
		seller_id = multiplayer.get_unique_id()

	if not _shops.has(seller_id):
		return
	if _shops[seller_id].listings.size() >= MAX_LISTINGS:
		_notify(seller_id, "Your shop is full.", Color.ORANGE)
		return
	if price < 1:
		_notify(seller_id, "Price must be at least 1 coin.", Color.ORANGE)
		return

	var seller := _get_player(seller_id)
	if not is_instance_valid(seller) or not is_instance_valid(seller.inventory_component):
		return

	var slots: Array = seller.inventory_component.get_slots()
	if slot_index < 0 or slot_index >= slots.size():
		return
	var slot: SlotData = slots[slot_index]
	if not slot.item:
		return

	# Remove one unit from the seller's inventory and hold it in the listing.
	# Holding the item server-side guarantees it can't be sold/dropped twice.
	var item: ItemData = slot.item
	var listed_item: ItemData
	if item.can_stack and item.current_stack_amount > 1:
		listed_item = item.duplicate_with_path(true)
		listed_item.current_stack_amount = 1
		seller.inventory_component.remove_item_from_stack(item, 1, "listed")
	else:
		listed_item = item
		seller.inventory_component.remove_item(item, "listed")

	var listing := {
		"listing_id": _next_listing_id,
		"item": listed_item,
		"price": clampi(price, 1, 999999999),
	}
	_next_listing_id += 1
	_shops[seller_id].listings.append(listing)

	_sync_owner_shop(seller_id)
	_sync_browsers(seller_id)


## [Client -> Server] Remove a listing and return the held item to the seller.
@rpc("any_peer", "call_local", "reliable")
func request_unlist_item(listing_id: int) -> void:
	if not multiplayer.is_server():
		return
	var seller_id := multiplayer.get_remote_sender_id()
	if seller_id == 0:
		seller_id = multiplayer.get_unique_id()

	if not _shops.has(seller_id):
		return

	var listings: Array = _shops[seller_id].listings
	for i in listings.size():
		if listings[i].listing_id == listing_id:
			var held_item: ItemData = listings[i].item
			var seller := _get_player(seller_id)
			if is_instance_valid(seller) and is_instance_valid(seller.inventory_component):
				if seller.inventory_component.get_empty_slots().is_empty() \
						and not seller.inventory_component.item_locations.has(held_item.item_id):
					_notify(seller_id, "Your inventory is full.", Color.ORANGE)
					return
				seller.inventory_component.server_add_item_instance(held_item.to_dictionary())
			listings.remove_at(i)
			_sync_owner_shop(seller_id)
			_sync_browsers(seller_id)
			return


# === SERVER: BROWSING & BUYING ===

## [Client -> Server] Ask for a read-only snapshot of `seller_id`'s shop.
@rpc("any_peer", "call_local", "reliable")
func request_browse_shop(seller_id: int) -> void:
	if not multiplayer.is_server():
		return
	var browser_id := multiplayer.get_remote_sender_id()
	if browser_id == 0:
		browser_id = multiplayer.get_unique_id()

	if not _shops.has(seller_id):
		_client_browse_failed.rpc_id(browser_id, "That shop is no longer open.")
		return
	if browser_id == seller_id:
		return  # use the owner panel instead
	if not _is_within_range(browser_id, seller_id):
		_client_browse_failed.rpc_id(browser_id, "You are too far from the shop.")
		return

	_client_receive_browse_data.rpc_id(browser_id, seller_id,
		_shops[seller_id].shop_name, _serialize_listings(seller_id))


## [Client -> Server] Buy a listing. Atomic: validates coins, range, and that
## the listing still exists, then transfers coins and the item server-side.
@rpc("any_peer", "call_local", "reliable")
func request_buy_listing(seller_id: int, listing_id: int) -> void:
	if not multiplayer.is_server():
		return
	var buyer_id := multiplayer.get_remote_sender_id()
	if buyer_id == 0:
		buyer_id = multiplayer.get_unique_id()

	if buyer_id == seller_id:
		return
	if not _shops.has(seller_id):
		_client_browse_failed.rpc_id(buyer_id, "That shop is no longer open.")
		return

	# Locate the listing.
	var listings: Array = _shops[seller_id].listings
	var listing_index := -1
	for i in listings.size():
		if listings[i].listing_id == listing_id:
			listing_index = i
			break
	if listing_index == -1:
		_notify(buyer_id, "That item was already sold.", Color.ORANGE)
		_sync_browser(buyer_id, seller_id)
		return

	if not _is_within_range(buyer_id, seller_id):
		_notify(buyer_id, "You are too far from the shop.", Color.ORANGE)
		return

	var buyer := _get_player(buyer_id)
	var seller := _get_player(seller_id)
	if not is_instance_valid(buyer) or not is_instance_valid(buyer.inventory_component) \
			or not is_instance_valid(buyer.player_inventory):
		return
	if not is_instance_valid(seller) or not is_instance_valid(seller.player_inventory):
		_notify(buyer_id, "The seller is no longer available.", Color.ORANGE)
		return

	var listing: Dictionary = listings[listing_index]
	var price: int = listing.price
	var item: ItemData = listing.item

	# --- Atomic validation block ---
	if buyer.player_inventory.monies_amount < price:
		_notify(buyer_id, "You don't have enough coins.", Color.ORANGE)
		return
	if buyer.inventory_component.get_empty_slots().is_empty() \
			and not buyer.inventory_component.item_locations.has(item.item_id):
		_notify(buyer_id, "Your inventory is full.", Color.ORANGE)
		return

	# --- Commit: remove listing first so it can't be double-bought. ---
	listings.remove_at(listing_index)
	buyer.player_inventory.monies_amount -= price
	seller.player_inventory.monies_amount += price
	buyer.inventory_component.server_add_item_instance(item.to_dictionary())

	var item_name: String = item.name
	_notify(buyer_id, "Bought %s for %d coins." % [item_name, price], Color(0.5, 0.9, 0.5))
	_notify(seller_id, "Sold %s for %d coins." % [item_name, price], Color(0.5, 0.9, 0.5))

	_sync_owner_shop(seller_id)
	_sync_browsers(seller_id)


## Distance gate — a browsing player must be physically near the seller.
func _is_within_range(a_id: int, b_id: int) -> bool:
	const MAX_RANGE_SQ: float = 160.0 * 160.0
	var a := _get_player(a_id)
	var b := _get_player(b_id)
	if not is_instance_valid(a) or not is_instance_valid(b):
		return false
	if MapManager.get_player_map(a_id) != MapManager.get_player_map(b_id):
		return false
	return a.global_position.distance_squared_to(b.global_position) <= MAX_RANGE_SQ


# === SERVER -> CLIENT SYNC HELPERS ===

func _broadcast_shop_open_state(seller_id: int, is_open: bool, shop_name: String) -> void:
	# Tell every real client (host included) so their "browse" prompts update.
	_client_shop_state.rpc(seller_id, is_open, shop_name)


func _sync_owner_shop(seller_id: int) -> void:
	if BotManager.is_bot(seller_id) or not _shops.has(seller_id):
		return
	_client_receive_owner_data.rpc_id(seller_id,
		_shops[seller_id].shop_name, _serialize_listings(seller_id))


## Pushes a fresh snapshot to every player currently browsing this shop.
func _sync_browsers(seller_id: int) -> void:
	if not _shops.has(seller_id):
		return
	for browser_id in _browsers_of(seller_id):
		_sync_browser(browser_id, seller_id)


func _sync_browser(browser_id: int, seller_id: int) -> void:
	if BotManager.is_bot(browser_id):
		return
	if not _shops.has(seller_id):
		_client_browse_failed.rpc_id(browser_id, "That shop is no longer open.")
		return
	_client_receive_browse_data.rpc_id(browser_id, seller_id,
		_shops[seller_id].shop_name, _serialize_listings(seller_id))


## Real players on the same map as the seller (potential browsers). The client
## window itself filters to whoever actually has the browse panel open.
func _browsers_of(seller_id: int) -> Array:
	var map_id := MapManager.get_player_map(seller_id)
	if map_id.is_empty():
		return []
	var out: Array = []
	for pid in MapManager.get_real_players_on_map(map_id):
		if pid != seller_id:
			out.append(pid)
	return out


func _notify(player_id: int, message: String, color: Color) -> void:
	if player_id == multiplayer.get_unique_id():
		ChatManager.add_system_message(message, color)
	elif not BotManager.is_bot(player_id):
		ChatManager.add_system_message.rpc_id(player_id, message, color)


# === CLIENT RPCs ===

@rpc("authority", "call_local", "reliable")
func _client_shop_state(seller_id: int, is_open: bool, shop_name: String) -> void:
	if is_open:
		_open_shop_names[seller_id] = shop_name
	else:
		_open_shop_names.erase(seller_id)
	shops_changed.emit()


@rpc("authority", "call_local", "reliable")
func _client_receive_owner_data(shop_name: String, listings: Array) -> void:
	# Only refresh if the owner panel is actually open — a background sale should
	# update the panel in place, not pop a closed window back open.
	if is_instance_valid(_shop_window) and not _shop_window.visible:
		return
	var window := _get_or_create_window()
	window.show_owner_view(shop_name, listings)


@rpc("authority", "call_local", "reliable")
func _client_receive_browse_data(seller_id: int, shop_name: String, listings: Array) -> void:
	# A push refresh (seller sold/unlisted) reaches every player on the map. Only
	# act on it when this client actually has that shop's browse window open, so
	# we don't pop a window open for non-browsers. An explicit browse request,
	# though, must always open the window — distinguished by _pending_browse.
	if seller_id != _pending_browse and is_instance_valid(_shop_window):
		if not _shop_window.visible or not _shop_window.is_browsing() \
				or _shop_window.get_browse_seller_id() != seller_id:
			return
	_pending_browse = 0
	var window := _get_or_create_window()
	window.show_browse_view(seller_id, shop_name, listings)


@rpc("authority", "call_local", "reliable")
func _client_shop_closed() -> void:
	if is_instance_valid(_shop_window):
		_shop_window.on_shop_closed()


@rpc("authority", "call_local", "reliable")
func _client_browse_failed(reason: String) -> void:
	ChatManager.add_system_message(reason, Color.ORANGE)
	if is_instance_valid(_shop_window) and _shop_window.is_browsing():
		_shop_window.visible = false


# === CLIENT WINDOW MANAGEMENT ===

var _shop_window: PersonalShopWindow = null


func _get_or_create_window() -> PersonalShopWindow:
	if is_instance_valid(_shop_window):
		return _shop_window
	_shop_window = PersonalShopWindow.create()
	var local_player := PlayerManager.get_player_node(multiplayer.get_unique_id())
	if is_instance_valid(local_player):
		var container = local_player.get_node_or_null("CanvasLayer/MoveableWindows")
		if container:
			container.add_child(_shop_window)
			return _shop_window
	get_tree().current_scene.add_child(_shop_window)
	return _shop_window


## Opens the owner-side shop management panel for the local player. The panel
## starts in a "not yet open" state; the player names the shop and clicks
## "Open Shop", which sends request_open_shop to the server.
func open_my_shop_panel() -> void:
	if MapManager.current_map_id != FREE_MARKET_MAP:
		ChatManager.add_system_message("You can only open a shop in the Free Market.", Color.ORANGE)
		return
	var window := _get_or_create_window()
	var already_open := is_shop_open(multiplayer.get_unique_id())
	window.show_owner_view(get_shop_name(multiplayer.get_unique_id()), [], already_open)
	# If the shop is already open, pull a fresh authoritative snapshot.
	if already_open:
		request_open_shop.rpc_id(1, get_shop_name(multiplayer.get_unique_id()))


## Opens the read-only browse panel for another player's shop.
func browse_player_shop(seller_id: int) -> void:
	if not is_shop_open(seller_id):
		ChatManager.add_system_message("That player does not have a shop open.", Color.ORANGE)
		return
	_pending_browse = seller_id
	request_browse_shop.rpc_id(1, seller_id)
