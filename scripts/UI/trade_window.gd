class_name TradeWindow
extends Panel

## Trade window with two modes:
##  * BOT mode — instant give/take button lists (the player's inventory and the
##    bot's inventory). Used for trading with bots, which have no client/UI.
##  * PLAYER mode — a face-to-face dual-offer window: the player's inventory,
##    their own offer, the partner's offer, gold fields and Confirm buttons.
##    Items move into the offer only via server-validated RPCs.

enum Mode { BOT, PLAYER }

var _mode: int = Mode.BOT
var is_dragging := false
var drag_offset := Vector2()
var _built := false
var _target_id: int = 0
var _refresh_timer: float = 0.0

## BOT mode: latest snapshot of the bot (its inventory is server-only).
var _bot_snapshot: Dictionary = {}

## PLAYER mode: latest authoritative trade state from the server.
var _trade_data: Dictionary = {}
var _my_confirmed: bool = false
var _partner_confirmed: bool = false
## PLAYER mode: inventory slot indices currently placed in this player's offer.
## Rebuilt from authoritative server data on every trade update.
var _offered_local_slots: Array[int] = []

const WINDOW_WIDTH: float = 520.0
const WINDOW_HEIGHT: float = 560.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const REFRESH_INTERVAL: float = 0.5
const BUTTON_POOL_SIZE: int = 170
const OFFER_POOL_SIZE: int = 8

var _title_label: Label
var _my_gold_label: Label
var _bot_gold_label: Label
var _my_inv_container: VBoxContainer
var _bot_inv_container: VBoxContainer
var _my_buttons: Array[Button] = []
var _bot_buttons: Array[Button] = []
var _my_button_slot: Array[int] = []
var _bot_button_slot: Array[int] = []

# PLAYER mode extra widgets
var _my_offer_container: VBoxContainer
var _partner_offer_container: VBoxContainer
var _my_offer_buttons: Array[Button] = []
var _partner_offer_labels: Array[Label] = []
var _my_gold_field: LineEdit
var _my_offer_gold_label: Label
var _partner_gold_label: Label
var _confirm_button: Button
var _my_status_label: Label
var _partner_status_label: Label

var _hover_bg: StyleBoxFlat
var _normal_bg: StyleBoxEmpty


## Creates a bot-trade window (instant give/take).
static func create_bot_window() -> TradeWindow:
	var window := _new_window()
	window._mode = Mode.BOT
	window._build_bot_ui()
	BotManager.bot_snapshot_received.connect(window._on_bot_snapshot)
	return window


## Creates a player-to-player trade window (dual offer/confirm).
static func create_player_window() -> TradeWindow:
	var window := _new_window()
	window._mode = Mode.PLAYER
	window._build_player_ui()
	TradeManager.trade_session_updated.connect(window._on_trade_session_updated)
	TradeManager.trade_session_closed.connect(window._on_trade_session_closed)
	return window


## Backwards-compatible alias — older callers used create() for the bot window.
static func create() -> TradeWindow:
	return create_bot_window()


static func _new_window() -> TradeWindow:
	var window := TradeWindow.new()
	window.custom_minimum_size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.visible = false
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	bg.border_color = Color(0.3, 0.3, 0.4, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	window.add_theme_stylebox_override("panel", bg)

	window._hover_bg = StyleBoxFlat.new()
	window._hover_bg.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	window._hover_bg.set_corner_radius_all(2)
	window._normal_bg = StyleBoxEmpty.new()
	return window


#=============================================================================
# SHARED UI PIECES
#=============================================================================

func _build_title_bar(root: VBoxContainer) -> void:
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0, TITLE_HEIGHT)
	title_bar.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	title_bar.mouse_filter = Control.MOUSE_FILTER_PASS
	var title_bg := StyleBoxFlat.new()
	title_bg.bg_color = Color(0.18, 0.18, 0.22, 1.0)
	title_bg.set_corner_radius_all(4)
	title_bg.corner_radius_bottom_left = 0
	title_bg.corner_radius_bottom_right = 0
	title_bar.add_theme_stylebox_override("panel", title_bg)
	root.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "Trade"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	_title_label.position = Vector2(PADDING, 4)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(_title_label)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.flat = true
	close_btn.add_theme_font_size_override("font_size", 12)
	close_btn.add_theme_color_override("font_color", Color.WHITE)
	close_btn.add_theme_color_override("font_hover_color", Color.RED)
	close_btn.set_anchors_preset(PRESET_TOP_RIGHT)
	close_btn.offset_left = -28
	close_btn.offset_top = 2
	close_btn.offset_right = -4
	close_btn.offset_bottom = 26
	close_btn.pressed.connect(_on_close_pressed)
	title_bar.add_child(close_btn)


func _build_content_margin(root: VBoxContainer) -> MarginContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PADDING))
	margin.add_theme_constant_override("margin_right", int(PADDING))
	margin.add_theme_constant_override("margin_top", int(PADDING))
	margin.add_theme_constant_override("margin_bottom", int(PADDING))
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(margin)
	return margin


func _make_separator() -> HSeparator:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.3, 0.3, 0.4, 0.5)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep


func _create_button_pool(container: VBoxContainer, count: int) -> Array[Button]:
	var pool: Array[Button] = []
	for i in count:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 22)
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
		btn.add_theme_stylebox_override("hover", _hover_bg)
		btn.add_theme_stylebox_override("normal", _normal_bg)
		btn.add_theme_stylebox_override("pressed", _hover_bg)
		btn.add_theme_stylebox_override("focus", _normal_bg)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.visible = false
		container.add_child(btn)
		pool.append(btn)
	return pool


#=============================================================================
# BOT MODE UI
#=============================================================================

func _build_bot_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_build_title_bar(root)
	var margin := _build_content_margin(root)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)

	var left := _build_inv_column(columns, "Your Items", Color(0.5, 0.8, 1.0))
	_my_gold_label = left.gold_label
	_my_inv_container = left.container
	_my_buttons = _create_button_pool(_my_inv_container, BUTTON_POOL_SIZE)
	_my_button_slot.resize(BUTTON_POOL_SIZE)
	_my_button_slot.fill(-1)

	var right := _build_inv_column(columns, "Their Items", Color(1.0, 0.8, 0.5))
	_bot_gold_label = right.gold_label
	_bot_inv_container = right.container
	_bot_buttons = _create_button_pool(_bot_inv_container, BUTTON_POOL_SIZE)
	_bot_button_slot.resize(BUTTON_POOL_SIZE)
	_bot_button_slot.fill(-1)

	_built = true


func _build_inv_column(parent: HBoxContainer, header_text: String, header_color: Color) -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(col)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", header_color)
	col.add_child(header)

	var gold := Label.new()
	gold.text = "Gold: 0"
	gold.add_theme_font_size_override("font_size", 10)
	gold.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	col.add_child(gold)

	col.add_child(_make_separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 1)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(container)

	return {"gold_label": gold, "container": container}


#=============================================================================
# PLAYER MODE UI
#=============================================================================

func _build_player_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	_build_title_bar(root)
	var margin := _build_content_margin(root)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(body)

	# --- Top: two offer panels side by side ---
	var offers := HBoxContainer.new()
	offers.add_theme_constant_override("separation", 8)
	offers.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	offers.custom_minimum_size = Vector2(0, 200)
	body.add_child(offers)

	var my_col := _build_offer_column(offers, "Your Offer", Color(0.5, 0.8, 1.0), true)
	_my_offer_container = my_col.container
	_my_status_label = my_col.status
	_my_offer_gold_label = my_col.gold_label
	_my_offer_buttons = _create_button_pool(_my_offer_container, OFFER_POOL_SIZE)

	var their_col := _build_offer_column(offers, "Their Offer", Color(1.0, 0.8, 0.5), false)
	_partner_offer_container = their_col.container
	_partner_status_label = their_col.status
	_partner_gold_label = their_col.gold_label
	for i in OFFER_POOL_SIZE:
		var lbl := Label.new()
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.custom_minimum_size = Vector2(0, 22)
		lbl.visible = false
		_partner_offer_container.add_child(lbl)
		_partner_offer_labels.append(lbl)

	# --- Gold offer row ---
	var gold_row := HBoxContainer.new()
	gold_row.add_theme_constant_override("separation", 6)
	body.add_child(gold_row)
	var gold_caption := Label.new()
	gold_caption.text = "Your Gold:"
	gold_caption.add_theme_font_size_override("font_size", 11)
	gold_caption.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	gold_row.add_child(gold_caption)
	_my_gold_field = LineEdit.new()
	_my_gold_field.text = "0"
	_my_gold_field.custom_minimum_size = Vector2(110, 24)
	_my_gold_field.add_theme_font_size_override("font_size", 11)
	_my_gold_field.text_submitted.connect(_on_gold_submitted)
	_my_gold_field.focus_exited.connect(func(): _on_gold_submitted(_my_gold_field.text))
	gold_row.add_child(_my_gold_field)

	body.add_child(_make_separator())

	# --- Bottom: the player's own inventory list ---
	var inv_header := Label.new()
	inv_header.text = "Your Inventory  (click to add)"
	inv_header.add_theme_font_size_override("font_size", 11)
	inv_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.85))
	body.add_child(inv_header)

	_my_gold_label = Label.new()
	_my_gold_label.text = "Gold: 0"
	_my_gold_label.add_theme_font_size_override("font_size", 10)
	_my_gold_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	body.add_child(_my_gold_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)

	_my_inv_container = VBoxContainer.new()
	_my_inv_container.add_theme_constant_override("separation", 1)
	_my_inv_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_my_inv_container)
	_my_buttons = _create_button_pool(_my_inv_container, BUTTON_POOL_SIZE)
	_my_button_slot.resize(BUTTON_POOL_SIZE)
	_my_button_slot.fill(-1)

	# --- Action buttons ---
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	body.add_child(actions)

	_confirm_button = Button.new()
	_confirm_button.text = "Confirm"
	_confirm_button.custom_minimum_size = Vector2(140, 30)
	_confirm_button.add_theme_font_size_override("font_size", 12)
	_confirm_button.pressed.connect(_on_confirm_pressed)
	actions.add_child(_confirm_button)

	var cancel_button := Button.new()
	cancel_button.text = "Cancel"
	cancel_button.custom_minimum_size = Vector2(140, 30)
	cancel_button.add_theme_font_size_override("font_size", 12)
	cancel_button.pressed.connect(_on_cancel_pressed)
	actions.add_child(cancel_button)

	_built = true


func _build_offer_column(parent: HBoxContainer, header_text: String, header_color: Color, is_mine: bool) -> Dictionary:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 3)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel_bg := StyleBoxFlat.new()
	panel_bg.bg_color = Color(0.08, 0.08, 0.11, 1.0)
	panel_bg.set_corner_radius_all(3)
	panel_bg.set_content_margin_all(5)
	var wrapper := PanelContainer.new()
	wrapper.add_theme_stylebox_override("panel", panel_bg)
	wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	wrapper.add_child(col)
	parent.add_child(wrapper)

	var header := Label.new()
	header.text = header_text
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", header_color)
	col.add_child(header)

	var hint := Label.new()
	hint.text = "(click an item below to remove)" if is_mine else ""
	hint.add_theme_font_size_override("font_size", 8)
	hint.add_theme_color_override("font_color", Color(0.55, 0.55, 0.6))
	col.add_child(hint)

	var gold := Label.new()
	gold.text = "Gold: 0"
	gold.add_theme_font_size_override("font_size", 10)
	gold.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	col.add_child(gold)

	col.add_child(_make_separator())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 1)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(container)

	var status := Label.new()
	status.text = "Not confirmed"
	status.add_theme_font_size_override("font_size", 10)
	status.add_theme_color_override("font_color", Color(0.8, 0.5, 0.5))
	col.add_child(status)

	return {"container": container, "gold_label": gold, "status": status}


#=============================================================================
# SHOW / TARGETING
#=============================================================================

## BOT mode: open the window for a bot target.
func show_for_target(target_id: int) -> void:
	_target_id = target_id
	_refresh_timer = 0.0
	_bot_snapshot = {}
	if _mode == Mode.BOT:
		_request_target_snapshot()
		_refresh_bot_lists()
	var target_name := _get_target_name()
	_title_label.text = "Trade: %s" % target_name
	_present()


## PLAYER mode: open the window for a confirmed trade session.
func open_session(partner_id: int, partner_name: String) -> void:
	_target_id = partner_id
	_refresh_timer = 0.0
	_trade_data = {}
	_my_confirmed = false
	_partner_confirmed = false
	_my_button_slot.fill(-1)
	_title_label.text = "Trade: %s" % partner_name
	_refresh_player_inventory_list()
	_refresh_offers()
	_present()


func _present() -> void:
	if not visible:
		var vp_size := get_viewport_rect().size
		global_position = (vp_size - size) * 0.5
		visible = true
	move_to_front()


func _on_close_pressed() -> void:
	if _mode == Mode.PLAYER and _target_id != 0:
		TradeManager.rpc_cancel_trade.rpc_id(1)
	visible = false


#=============================================================================
# BOT MODE: LIST REFRESH + TRANSFER
#=============================================================================

func _request_target_snapshot() -> void:
	if _target_id != 0:
		BotManager.request_bot_snapshot.rpc_id(1, _target_id)


func _on_bot_snapshot(bot_id: int, snapshot: Dictionary) -> void:
	if _mode != Mode.BOT or bot_id != _target_id or not visible:
		return
	_bot_snapshot = snapshot
	_refresh_bot_lists()


func _refresh_bot_lists() -> void:
	if not _built:
		return

	var local_player := _get_local_player()
	if not is_instance_valid(local_player):
		visible = false
		return

	if is_instance_valid(local_player.player_inventory):
		_my_gold_label.text = "Gold: %d" % local_player.player_inventory.monies_amount
	_bot_gold_label.text = "Gold: %d" % int(_bot_snapshot.get("gold", 0))

	var my_items: Array = []
	if is_instance_valid(local_player.inventory_component):
		var slots: Array = local_player.inventory_component.get_slots()
		for i in slots.size():
			if slots[i].item:
				my_items.append({"index": i, "item": slots[i].item})
	_update_button_list(_my_buttons, _my_button_slot, my_items, _give_item)

	var their_items: Array = []
	for entry in _bot_snapshot.get("inventory", []):
		var item: ItemData = ItemData.from_dictionary(entry.get("item", {}))
		if item:
			their_items.append({"index": int(entry.get("slot_index", -1)), "item": item})
	_update_button_list(_bot_buttons, _bot_button_slot, their_items, _take_item)


func _give_item(slot_index: int) -> void:
	if _target_id == 0:
		return
	TradeManager.rpc_transfer_trade_item.rpc_id(1, _target_id, slot_index, true)
	_request_post_transfer_refresh()


func _take_item(slot_index: int) -> void:
	if _target_id == 0:
		return
	TradeManager.rpc_transfer_trade_item.rpc_id(1, _target_id, slot_index, false)
	_request_post_transfer_refresh()


func _request_post_transfer_refresh() -> void:
	_my_button_slot.fill(-1)
	_bot_button_slot.fill(-1)
	_request_target_snapshot()


#=============================================================================
# PLAYER MODE: SERVER STATE + LIST REFRESH
#=============================================================================

func _on_trade_session_updated(data: Dictionary) -> void:
	if _mode != Mode.PLAYER:
		return
	_trade_data = data
	_target_id = data.get("partner_id", _target_id)
	_my_confirmed = data.get("my_confirmed", false)
	_partner_confirmed = data.get("partner_confirmed", false)
	var partner_name: String = data.get("partner_name", "")
	if not partner_name.is_empty():
		_title_label.text = "Trade: %s" % partner_name
	# Derive the offered-slot set straight from the authoritative server data —
	# avoids any client/server drift if an add/remove RPC is rejected.
	_offered_local_slots.clear()
	for item_dict in data.get("my_offer", {}).get("items", []):
		var idx: int = int(item_dict.get("trade_slot_index", -1))
		if idx >= 0:
			_offered_local_slots.append(idx)
	_refresh_player_inventory_list()
	_refresh_offers()


func _on_trade_session_closed(_message: String) -> void:
	if _mode != Mode.PLAYER:
		return
	_target_id = 0
	_trade_data = {}
	visible = false


## Lists the player's own inventory. Items already placed in the offer are
## hidden so a slot cannot be offered twice.
func _refresh_player_inventory_list() -> void:
	if not _built:
		return
	var local_player := _get_local_player()
	if not is_instance_valid(local_player):
		visible = false
		return

	if is_instance_valid(local_player.player_inventory):
		_my_gold_label.text = "Gold: %d" % local_player.player_inventory.monies_amount

	# Hide slots already placed in the offer so a slot cannot be offered twice.
	var offered_indices := _offered_slot_indices()

	var my_items: Array = []
	if is_instance_valid(local_player.inventory_component):
		var slots: Array = local_player.inventory_component.get_slots()
		for i in slots.size():
			if slots[i].item and not offered_indices.has(i):
				my_items.append({"index": i, "item": slots[i].item})
	_update_button_list(_my_buttons, _my_button_slot, my_items, _offer_item)


func _offered_slot_indices() -> Dictionary:
	var d := {}
	for idx in _offered_local_slots:
		d[idx] = true
	return d


func _refresh_offers() -> void:
	if not _built:
		return

	var my_offer: Dictionary = _trade_data.get("my_offer", {})
	var partner_offer: Dictionary = _trade_data.get("partner_offer", {})

	# My offer — each entry is removable on click.
	var my_items: Array = my_offer.get("items", [])
	for i in _my_offer_buttons.size():
		var btn := _my_offer_buttons[i]
		if i < my_items.size():
			var item := ItemData.from_dictionary(my_items[i])
			btn.text = _item_label(item) if item else str(my_items[i].get("name", "?"))
			btn.tooltip_text = _build_item_tooltip(item) if item else ""
			if item:
				btn.add_theme_color_override("font_color", _get_rarity_color(item))
			btn.visible = true
			_disconnect_all(btn)
			var captured := i
			btn.pressed.connect(func(): _remove_offer_item(captured))
		else:
			btn.visible = false
			btn.text = ""
			_disconnect_all(btn)

	# Partner offer — read-only.
	var their_items: Array = partner_offer.get("items", [])
	for i in _partner_offer_labels.size():
		var lbl := _partner_offer_labels[i]
		if i < their_items.size():
			var item := ItemData.from_dictionary(their_items[i])
			lbl.text = _item_label(item) if item else str(their_items[i].get("name", "?"))
			if item:
				lbl.add_theme_color_override("font_color", _get_rarity_color(item))
			lbl.visible = true
		else:
			lbl.visible = false
			lbl.text = ""

	_my_status_label.text = "CONFIRMED" if _my_confirmed else "Not confirmed"
	_my_status_label.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if _my_confirmed else Color(0.8, 0.5, 0.5))
	_partner_status_label.text = "CONFIRMED" if _partner_confirmed else "Not confirmed"
	_partner_status_label.add_theme_color_override("font_color",
			Color(0.4, 0.9, 0.4) if _partner_confirmed else Color(0.8, 0.5, 0.5))
	_my_offer_gold_label.text = "Gold: %d" % int(my_offer.get("gold", 0))
	_partner_gold_label.text = "Gold: %d" % int(partner_offer.get("gold", 0))

	if _confirm_button:
		_confirm_button.text = "Unconfirm" if _my_confirmed else "Confirm"

	# Keep the gold field in sync with the server's clamped value while the
	# player is not actively editing it.
	if not _my_gold_field.has_focus():
		_my_gold_field.text = str(int(my_offer.get("gold", 0)))


func _offer_item(slot_index: int) -> void:
	if _target_id == 0:
		return
	if not _offered_local_slots.has(slot_index):
		_offered_local_slots.append(slot_index)
	TradeManager.rpc_add_item.rpc_id(1, slot_index)
	_refresh_player_inventory_list()


func _remove_offer_item(trade_slot_index: int) -> void:
	if _target_id == 0:
		return
	# The offer list and the local slot list stay index-aligned.
	if trade_slot_index >= 0 and trade_slot_index < _offered_local_slots.size():
		_offered_local_slots.remove_at(trade_slot_index)
	TradeManager.rpc_remove_item.rpc_id(1, trade_slot_index)
	_refresh_player_inventory_list()


func _on_gold_submitted(text: String) -> void:
	if _target_id == 0 or _mode != Mode.PLAYER:
		return
	var amount := maxi(0, int(text))
	TradeManager.rpc_set_gold.rpc_id(1, amount)


func _on_confirm_pressed() -> void:
	if _target_id == 0:
		return
	if _my_confirmed:
		TradeManager.rpc_unconfirm_trade.rpc_id(1)
	else:
		TradeManager.rpc_confirm_trade.rpc_id(1)


func _on_cancel_pressed() -> void:
	if _target_id != 0:
		TradeManager.rpc_cancel_trade.rpc_id(1)
	visible = false


#=============================================================================
# SHARED LIST HELPERS
#=============================================================================

## `items` is an Array of { "index": int, "item": ItemData }. `on_click` is
## called with the slot index when a button is pressed.
func _update_button_list(buttons: Array[Button], slot_map: Array[int], items: Array, on_click: Callable) -> void:
	var btn_idx := 0
	for entry in items:
		if btn_idx >= buttons.size():
			break
		var item: ItemData = entry["item"]
		var slot_idx: int = entry["index"]

		var btn := buttons[btn_idx]
		btn.text = _item_label(item)
		btn.tooltip_text = _build_item_tooltip(item)
		btn.add_theme_color_override("font_color", _get_rarity_color(item))
		btn.visible = true

		if slot_map[btn_idx] != slot_idx:
			_disconnect_all(btn)
			var captured_idx := slot_idx
			btn.pressed.connect(func(): on_click.call(captured_idx))
			slot_map[btn_idx] = slot_idx

		btn_idx += 1

	for j in range(btn_idx, buttons.size()):
		if buttons[j].visible:
			buttons[j].visible = false
			buttons[j].text = ""
			buttons[j].tooltip_text = ""
			slot_map[j] = -1


func _item_label(item: ItemData) -> String:
	if not item:
		return "?"
	var text := item.name
	if item.can_stack and item.current_stack_amount > 1:
		text += " x%d" % item.current_stack_amount
	if item is EquipmentData:
		text += " (Lv.%d)" % item.item_level
	return text


func _disconnect_all(btn: Button) -> void:
	for connection in btn.pressed.get_connections():
		btn.pressed.disconnect(connection.callable)


func _build_item_tooltip(item: ItemData) -> String:
	if not item:
		return ""
	var tip := item.name
	if item is EquipmentData:
		var eq := item as EquipmentData
		tip += "\nLevel %d" % eq.item_level
		var rarity_name: String = Constants.ItemRarity.find_key(eq.rarity)
		if rarity_name:
			tip += " | %s" % rarity_name
		for stat_type in eq.bonus_stats:
			var stat_data: StatData = eq.bonus_stats[stat_type]
			if stat_data.flat_bonus_value > 0:
				tip += "\n%s: +%d" % [Constants.StatType.find_key(stat_type), stat_data.flat_bonus_value]
	elif item is ConsumableData:
		if not item.description.is_empty():
			tip += "\n%s" % item.description
	return tip


func _get_target_name() -> String:
	var snap_name: String = _bot_snapshot.get("name", "")
	if not snap_name.is_empty():
		return snap_name
	var player_node := PlayerManager.get_player_node(_target_id)
	if is_instance_valid(player_node) and not player_node.username.is_empty():
		return player_node.username
	if BotManager.is_bot(_target_id):
		var bot_info: Dictionary = BotManager.active_bots.get(_target_id, {})
		return bot_info.get("username", "Bot %d" % _target_id)
	return str(_target_id)


func _get_local_player() -> MultiplayerPlayerV2:
	return PlayerManager.get_player_node(multiplayer.get_unique_id())


func _get_rarity_color(item: ItemData) -> Color:
	if item is EquipmentData:
		match item.rarity:
			Constants.ItemRarity.COMMON: return Color(0.7, 0.7, 0.7)
			Constants.ItemRarity.UNCOMMON: return Color(1.0, 1.0, 1.0)
			Constants.ItemRarity.RARE: return Color(1.0, 0.6, 0.2)
			Constants.ItemRarity.EPIC: return Color(0.7, 0.3, 0.9)
			Constants.ItemRarity.LEGENDARY: return Color(1.0, 0.85, 0.0)
	return Color(0.8, 0.8, 0.8)


#=============================================================================
# DRAGGABLE WINDOW
#=============================================================================

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var title_rect := Rect2(global_position, Vector2(size.x, TITLE_HEIGHT))
			if title_rect.has_point(get_global_mouse_position()):
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				move_to_front()
		else:
			is_dragging = false


func _process(delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos

	if not visible or _target_id == 0:
		return

	_refresh_timer += delta
	if _refresh_timer < REFRESH_INTERVAL:
		return
	_refresh_timer = 0.0

	if _mode == Mode.BOT:
		_request_target_snapshot()
		_refresh_bot_lists()
	else:
		# Keep the inventory list fresh (items may be picked up / used elsewhere).
		_refresh_player_inventory_list()
