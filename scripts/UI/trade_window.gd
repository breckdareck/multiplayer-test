class_name TradeWindow
extends Panel

var is_dragging := false
var drag_offset := Vector2()
var _built := false
var _target_id: int = 0
var _refresh_timer: float = 0.0
## Latest data snapshot for the trade target (their inventory is server-only).
var _bot_snapshot: Dictionary = {}

const WINDOW_WIDTH: float = 500.0
const WINDOW_HEIGHT: float = 520.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const REFRESH_INTERVAL: float = 0.5
const BUTTON_POOL_SIZE: int = 170

var _title_label: Label
var _my_gold_label: Label
var _bot_gold_label: Label
var _my_inv_container: VBoxContainer
var _bot_inv_container: VBoxContainer
var _my_buttons: Array[Button] = []
var _bot_buttons: Array[Button] = []
# Track which slot index each button maps to
var _my_button_slot: Array[int] = []
var _bot_button_slot: Array[int] = []

var _hover_bg: StyleBoxFlat
var _normal_bg: StyleBoxEmpty


static func create() -> TradeWindow:
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

	window._build_ui()
	BotManager.bot_snapshot_received.connect(window._on_bot_snapshot)
	return window


func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# Title bar
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
	close_btn.pressed.connect(func(): visible = false)
	title_bar.add_child(close_btn)

	# Content margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PADDING))
	margin.add_theme_constant_override("margin_right", int(PADDING))
	margin.add_theme_constant_override("margin_top", int(PADDING))
	margin.add_theme_constant_override("margin_bottom", int(PADDING))
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_child(margin)

	# Two columns side by side
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 8)
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(columns)

	# Left column: Your inventory
	var left := _build_column(columns, "Your Items", Color(0.5, 0.8, 1.0))
	_my_gold_label = left.gold_label
	_my_inv_container = left.container
	_my_buttons = _create_button_pool(_my_inv_container)
	_my_button_slot.resize(BUTTON_POOL_SIZE)
	_my_button_slot.fill(-1)

	# Right column: Bot inventory
	var right := _build_column(columns, "Their Items", Color(1.0, 0.8, 0.5))
	_bot_gold_label = right.gold_label
	_bot_inv_container = right.container
	_bot_buttons = _create_button_pool(_bot_inv_container)
	_bot_button_slot.resize(BUTTON_POOL_SIZE)
	_bot_button_slot.fill(-1)

	_built = true


func _build_column(parent: HBoxContainer, header_text: String, header_color: Color) -> Dictionary:
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

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.3, 0.3, 0.4, 0.5)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	col.add_child(sep)

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


func _create_button_pool(container: VBoxContainer) -> Array[Button]:
	var pool: Array[Button] = []
	for i in BUTTON_POOL_SIZE:
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


func show_for_target(target_id: int) -> void:
	_target_id = target_id
	_refresh_timer = 0.0
	_bot_snapshot = {}
	_request_target_snapshot()
	_refresh_lists()

	var target_name := _get_target_name()
	_title_label.text = "Trade: %s" % target_name

	if not visible:
		var vp_size := get_viewport_rect().size
		global_position = (vp_size - size) * 0.5
		visible = true
	move_to_front()


## Asks the server for a fresh snapshot of the trade target (their inventory
## is server-authoritative — not present on this client).
func _request_target_snapshot() -> void:
	if _target_id != 0:
		BotManager.request_bot_snapshot.rpc_id(1, _target_id)


func _on_bot_snapshot(bot_id: int, snapshot: Dictionary) -> void:
	if bot_id != _target_id or not visible:
		return
	_bot_snapshot = snapshot
	_refresh_lists()


func _refresh_lists() -> void:
	if not _built:
		return

	var local_player := _get_local_player()
	if not is_instance_valid(local_player):
		visible = false
		return

	if is_instance_valid(local_player.player_inventory):
		_my_gold_label.text = "Gold: %d" % local_player.player_inventory.monies_amount
	_bot_gold_label.text = "Gold: %d" % int(_bot_snapshot.get("gold", 0))

	# My items — read live from my own inventory.
	var my_items: Array = []
	if is_instance_valid(local_player.inventory_component):
		var slots: Array = local_player.inventory_component.get_slots()
		for i in slots.size():
			if slots[i].item:
				my_items.append({"index": i, "item": slots[i].item})
	_update_button_list(_my_buttons, _my_button_slot, my_items, true)

	# Their items — from the snapshot (the target's inventory is server-only).
	var their_items: Array = []
	for entry in _bot_snapshot.get("inventory", []):
		var item: ItemData = ItemData.from_dictionary(entry.get("item", {}))
		if item:
			their_items.append({"index": int(entry.get("slot_index", -1)), "item": item})
	_update_button_list(_bot_buttons, _bot_button_slot, their_items, false)


## `items` is an Array of { "index": int, "item": ItemData }.
func _update_button_list(buttons: Array[Button], slot_map: Array[int], items: Array, is_mine: bool) -> void:
	var btn_idx := 0

	for entry in items:
		if btn_idx >= buttons.size():
			break
		var item: ItemData = entry["item"]
		var slot_idx: int = entry["index"]

		var btn := buttons[btn_idx]
		var item_text := item.name
		if item.can_stack and item.current_stack_amount > 1:
			item_text += " x%d" % item.current_stack_amount
		if item is EquipmentData:
			item_text += " (Lv.%d)" % item.item_level

		btn.text = item_text
		btn.tooltip_text = _build_item_tooltip(item)
		btn.add_theme_color_override("font_color", _get_rarity_color(item))
		btn.visible = true

		# Only reconnect if the slot index changed
		if slot_map[btn_idx] != slot_idx:
			_disconnect_all(btn)
			var captured_idx := slot_idx
			if is_mine:
				btn.pressed.connect(func(): _give_item(captured_idx))
			else:
				btn.pressed.connect(func(): _take_item(captured_idx))
			slot_map[btn_idx] = slot_idx

		btn_idx += 1

	# Hide remaining buttons
	for j in range(btn_idx, buttons.size()):
		if buttons[j].visible:
			buttons[j].visible = false
			buttons[j].text = ""
			buttons[j].tooltip_text = ""
			slot_map[j] = -1


func _disconnect_all(btn: Button) -> void:
	for connection in btn.pressed.get_connections():
		btn.pressed.disconnect(connection.callable)


func _give_item(slot_index: int) -> void:
	if _target_id == 0:
		return
	# The transfer runs on the server — a client holds no authoritative copy of
	# the bot's inventory, so it cannot move items locally.
	TradeManager.rpc_transfer_trade_item.rpc_id(1, _target_id, slot_index, true)
	_request_post_transfer_refresh()


func _take_item(slot_index: int) -> void:
	if _target_id == 0:
		return
	TradeManager.rpc_transfer_trade_item.rpc_id(1, _target_id, slot_index, false)
	_request_post_transfer_refresh()


## After a transfer RPC, reset slot maps and pull a fresh target snapshot. The
## server applies the move; the own-inventory sync and the snapshot reply arrive
## ordered after it, and the snapshot reply drives a full list refresh.
func _request_post_transfer_refresh() -> void:
	_my_button_slot.fill(-1)
	_bot_button_slot.fill(-1)
	_request_target_snapshot()


func _build_item_tooltip(item: ItemData) -> String:
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
	# Prefer the snapshot, then the node's username (set on every peer at spawn).
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
	var pid := multiplayer.get_unique_id()
	return PlayerManager.get_player_node(pid)


func _get_rarity_color(item: ItemData) -> Color:
	if item is EquipmentData:
		match item.rarity:
			Constants.ItemRarity.COMMON: return Color(0.7, 0.7, 0.7)
			Constants.ItemRarity.UNCOMMON: return Color(1.0, 1.0, 1.0)
			Constants.ItemRarity.RARE: return Color(1.0, 0.6, 0.2)
			Constants.ItemRarity.EPIC: return Color(0.7, 0.3, 0.9)
			Constants.ItemRarity.LEGENDARY: return Color(1.0, 0.85, 0.0)
	return Color(0.8, 0.8, 0.8)


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


func _process(delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos

	if visible and _target_id != 0:
		_refresh_timer += delta
		if _refresh_timer >= REFRESH_INTERVAL:
			_refresh_timer = 0.0
			_request_target_snapshot()
			_refresh_lists()
