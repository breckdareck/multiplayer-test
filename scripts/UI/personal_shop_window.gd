class_name PersonalShopWindow
extends Panel

## Draggable UI panel for Free Market personal shops.
##
## Two modes:
##  - OWNER: manage your own shop — name it, list/unlist inventory items.
##  - BROWSE: read-only view of another player's shop — buy listed items.
##
## All coin/item mutations are server-authoritative. This window only sends
## intents (list / unlist / open / close / buy) and renders server snapshots.

enum Mode { OWNER, BROWSE }

const WINDOW_WIDTH: float = 460.0
const WINDOW_HEIGHT: float = 480.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const ROW_POOL_SIZE: int = 64

var _mode: int = Mode.OWNER
var _browse_seller_id: int = 0
var _shop_open: bool = false
var _built := false

var is_dragging := false
var drag_offset := Vector2()

var _title_label: Label
var _name_input: LineEdit
var _open_close_btn: Button
var _owner_row: HBoxContainer
var _status_label: Label
var _list_container: VBoxContainer
var _list_rows: Array[Button] = []
var _list_caption: Label

var _hover_bg: StyleBoxFlat
var _normal_bg: StyleBoxEmpty


static func create() -> PersonalShopWindow:
	var window := PersonalShopWindow.new()
	window.custom_minimum_size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.visible = false
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	bg.border_color = Color(0.3, 0.3, 0.4, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	window.add_theme_stylebox_override("panel", bg)

	window._hover_bg = StyleBoxFlat.new()
	window._hover_bg.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	window._hover_bg.set_corner_radius_all(2)
	window._normal_bg = StyleBoxEmpty.new()

	window._build_ui()
	return window


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# --- Title bar ---
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
	_title_label.text = "Personal Shop"
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
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	# --- Content margin ---
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PADDING))
	margin.add_theme_constant_override("margin_right", int(PADDING))
	margin.add_theme_constant_override("margin_top", int(PADDING))
	margin.add_theme_constant_override("margin_bottom", int(PADDING))
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(col)

	# --- Owner controls row (name input + open/close) ---
	_owner_row = HBoxContainer.new()
	_owner_row.add_theme_constant_override("separation", 6)
	col.add_child(_owner_row)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Shop name..."
	_name_input.max_length = 40
	_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_input.add_theme_font_size_override("font_size", 11)
	_owner_row.add_child(_name_input)

	_open_close_btn = Button.new()
	_open_close_btn.text = "Open Shop"
	_open_close_btn.custom_minimum_size = Vector2(90, 24)
	_open_close_btn.add_theme_font_size_override("font_size", 11)
	_open_close_btn.pressed.connect(_on_open_close_pressed)
	_owner_row.add_child(_open_close_btn)

	# --- Status / helper line ---
	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_status_label)

	# --- List caption ---
	_list_caption = Label.new()
	_list_caption.text = "Listings"
	_list_caption.add_theme_font_size_override("font_size", 12)
	_list_caption.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	col.add_child(_list_caption)

	var sep := HSeparator.new()
	col.add_child(sep)

	# --- Scrollable list ---
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.add_theme_constant_override("separation", 2)
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_container)

	for i in ROW_POOL_SIZE:
		var btn := Button.new()
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(0, 26)
		btn.add_theme_font_size_override("font_size", 10)
		btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))
		btn.add_theme_stylebox_override("hover", _hover_bg)
		btn.add_theme_stylebox_override("normal", _normal_bg)
		btn.add_theme_stylebox_override("pressed", _hover_bg)
		btn.add_theme_stylebox_override("focus", _normal_bg)
		btn.mouse_filter = Control.MOUSE_FILTER_STOP
		btn.visible = false
		_list_container.add_child(btn)
		_list_rows.append(btn)

	_built = true


# === PUBLIC API (called by PersonalShopManager) ===

func is_browsing() -> bool:
	return _mode == Mode.BROWSE


## Seller id of the shop currently shown in browse mode (0 if not browsing).
func get_browse_seller_id() -> int:
	return _browse_seller_id if _mode == Mode.BROWSE else 0


## Opens the owner-side management view. `server_open` is true when this is a
## refresh driven by a server snapshot of an already-open shop.
func show_owner_view(shop_name: String, listings: Array, server_open: bool = true) -> void:
	_mode = Mode.OWNER
	_browse_seller_id = 0
	_shop_open = server_open

	# Keep whatever the player typed; only overwrite from the server name.
	if not shop_name.is_empty():
		_name_input.text = shop_name

	_title_label.text = "My Shop"
	_owner_row.visible = true
	_open_close_btn.text = "Close Shop" if _shop_open else "Open Shop"
	_name_input.editable = not _shop_open
	_list_caption.text = "Your Listings (%d/%d)" % [listings.size(), PersonalShopManager.MAX_LISTINGS]
	_status_label.text = "Open your shop, then click an inventory item below to list it. Click a listing to unlist it."

	_render_rows(listings, true)
	_show()


## Renders the read-only browse view of another player's shop.
func show_browse_view(seller_id: int, shop_name: String, listings: Array) -> void:
	_mode = Mode.BROWSE
	_browse_seller_id = seller_id
	_title_label.text = shop_name if not shop_name.is_empty() else "Shop"
	_owner_row.visible = false
	_list_caption.text = "Items For Sale"
	_status_label.text = "Click an item to buy it. You must stay near the seller."
	_render_rows(listings, false)
	_show()


## Server told us our own shop closed (e.g. we left the Free Market).
func on_shop_closed() -> void:
	if _mode == Mode.OWNER:
		_shop_open = false
		_open_close_btn.text = "Open Shop"
		_name_input.editable = true
		_clear_rows()


# === INTERNAL ===

func _on_open_close_pressed() -> void:
	if _mode != Mode.OWNER:
		return
	if _open_close_btn.text == "Open Shop":
		_shop_open = true
		_name_input.editable = false
		_open_close_btn.text = "Close Shop"
		PersonalShopManager.request_open_shop.rpc_id(1, _name_input.text)
	else:
		_shop_open = false
		_name_input.editable = true
		_open_close_btn.text = "Open Shop"
		PersonalShopManager.request_close_shop.rpc_id(1)
		_clear_rows()


## Renders either the seller's listings or, in OWNER mode, also the inventory
## items available to list.
func _render_rows(listings: Array, is_owner: bool) -> void:
	_clear_rows()
	var row_idx := 0

	# 1. Active listings.
	for listing in listings:
		if row_idx >= _list_rows.size():
			break
		var item: ItemData = ItemData.from_dictionary(listing.get("item", {}))
		if not item:
			continue
		var price: int = int(listing.get("price", 0))
		var listing_id: int = int(listing.get("listing_id", -1))
		var btn := _list_rows[row_idx]
		btn.text = "%s   -   %d coins%s" % [item.name, price,
			"  (click to unlist)" if is_owner else "  (click to buy)"]
		btn.tooltip_text = _item_tooltip(item)
		btn.add_theme_color_override("font_color", _rarity_color(item))
		btn.visible = true
		_disconnect_all(btn)
		if is_owner:
			var lid := listing_id
			btn.pressed.connect(func(): _unlist(lid))
		else:
			var seller := _browse_seller_id
			var lid2 := listing_id
			btn.pressed.connect(func(): _buy(seller, lid2))
		row_idx += 1

	# 2. Owner mode: list inventory items that can be put up for sale.
	if is_owner:
		if row_idx < _list_rows.size():
			var header := _list_rows[row_idx]
			header.text = "--- Your Inventory (click to list) ---"
			header.tooltip_text = ""
			header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			header.visible = true
			header.disabled = true
			_disconnect_all(header)
			row_idx += 1

		var local := PlayerManager.get_player_node(multiplayer.get_unique_id())
		if is_instance_valid(local) and is_instance_valid(local.inventory_component):
			var slots: Array = local.inventory_component.get_slots()
			for i in slots.size():
				if row_idx >= _list_rows.size():
					break
				var slot: SlotData = slots[i]
				if not slot.item:
					continue
				var inv_item: ItemData = slot.item
				var btn2 := _list_rows[row_idx]
				var stack_txt := ""
				if inv_item.can_stack and inv_item.current_stack_amount > 1:
					stack_txt = " x%d" % inv_item.current_stack_amount
				btn2.text = "%s%s" % [inv_item.name, stack_txt]
				btn2.tooltip_text = _item_tooltip(inv_item)
				btn2.add_theme_color_override("font_color", _rarity_color(inv_item))
				btn2.disabled = false
				btn2.visible = true
				_disconnect_all(btn2)
				var slot_idx := i
				var suggested := maxi(1, inv_item.base_value)
				btn2.pressed.connect(func(): _prompt_list(slot_idx, inv_item.name, suggested))
				row_idx += 1


func _clear_rows() -> void:
	for btn in _list_rows:
		btn.visible = false
		btn.disabled = false
		btn.text = ""
		btn.tooltip_text = ""
		_disconnect_all(btn)


func _disconnect_all(btn: Button) -> void:
	for connection in btn.pressed.get_connections():
		btn.pressed.disconnect(connection.callable)


# --- Listing price prompt ---

var _price_dialog: AcceptDialog = null
var _price_spin: SpinBox = null
var _pending_slot: int = -1


func _prompt_list(slot_index: int, item_name: String, suggested_price: int) -> void:
	_pending_slot = slot_index
	if not is_instance_valid(_price_dialog):
		_price_dialog = AcceptDialog.new()
		_price_dialog.title = "Set Price"
		_price_dialog.ok_button_text = "List Item"
		var vb := VBoxContainer.new()
		var lbl := Label.new()
		lbl.name = "PromptLabel"
		vb.add_child(lbl)
		_price_spin = SpinBox.new()
		_price_spin.min_value = 1
		_price_spin.max_value = 999999999
		_price_spin.step = 1
		vb.add_child(_price_spin)
		_price_dialog.add_child(vb)
		_price_dialog.confirmed.connect(_on_price_confirmed)
		add_child(_price_dialog)
	var prompt_lbl := _price_dialog.find_child("PromptLabel", true, false)
	if prompt_lbl is Label:
		prompt_lbl.text = "Price (coins) for: %s" % item_name
	_price_spin.value = suggested_price
	_price_dialog.popup_centered(Vector2i(260, 110))


func _on_price_confirmed() -> void:
	if _pending_slot < 0:
		return
	PersonalShopManager.request_list_item.rpc_id(1, _pending_slot, int(_price_spin.value))
	_pending_slot = -1


func _unlist(listing_id: int) -> void:
	PersonalShopManager.request_unlist_item.rpc_id(1, listing_id)


func _buy(seller_id: int, listing_id: int) -> void:
	if seller_id == 0:
		return
	PersonalShopManager.request_buy_listing.rpc_id(1, seller_id, listing_id)


# --- Display helpers ---

func _item_tooltip(item: ItemData) -> String:
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


func _rarity_color(item: ItemData) -> Color:
	if item is EquipmentData:
		match item.rarity:
			Constants.ItemRarity.COMMON: return Color(0.7, 0.7, 0.7)
			Constants.ItemRarity.UNCOMMON: return Color(1.0, 1.0, 1.0)
			Constants.ItemRarity.RARE: return Color(1.0, 0.6, 0.2)
			Constants.ItemRarity.EPIC: return Color(0.7, 0.3, 0.9)
			Constants.ItemRarity.LEGENDARY: return Color(1.0, 0.85, 0.0)
	return Color(0.8, 0.8, 0.8)


func _show() -> void:
	if not visible:
		var vp_size := get_viewport_rect().size
		global_position = (vp_size - size) * 0.5
		visible = true
	move_to_front()


# --- Draggable ---

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


func _process(_delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos
