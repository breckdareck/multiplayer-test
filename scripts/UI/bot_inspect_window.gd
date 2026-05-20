class_name BotInspectWindow
extends Panel

var is_dragging := false
var drag_offset := Vector2()
var title_label: Label
var content_container: VBoxContainer
var scroll_container: ScrollContainer
var _current_bot_id: int = 0
var _refresh_timer: float = 0.0
var _built := false
## Latest data snapshot for the inspected bot (populated via BotManager RPC).
var _snapshot: Dictionary = {}

const WINDOW_WIDTH: float = 320.0
const WINDOW_HEIGHT: float = 500.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const ICON_SIZE: float = 32.0
const REFRESH_INTERVAL: float = 0.5

# Stored references for update-in-place
var _name_label: Label
var _level_label: Label
var _hp_value: Label
var _mp_value: Label
var _gold_value: Label
var _map_value: Label
var _action_row: HBoxContainer
var _action_value: Label

var _equip_rows: Array[HBoxContainer] = []  # 5 rows: Weapon, Head, Chest, Legs, Feet
var _stat_rows: Dictionary = {}  # StatType -> value Label
var _inv_total_value: Label
var _inv_equip_value: Label
var _inv_consumable_value: Label
var _inv_other_row: HBoxContainer
var _inv_other_value: Label
var _inv_notable_section: VBoxContainer


static func create() -> BotInspectWindow:
	var window := BotInspectWindow.new()
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

	window._build_ui()
	BotManager.bot_snapshot_received.connect(window._on_bot_snapshot)
	return window


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

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
	root_vbox.add_child(title_bar)

	title_label = Label.new()
	title_label.text = "Inspect"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	title_label.position = Vector2(PADDING, 4)
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(title_label)

	var close_button := Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.add_theme_color_override("font_color", Color.WHITE)
	close_button.add_theme_color_override("font_hover_color", Color.RED)
	close_button.set_anchors_preset(PRESET_TOP_RIGHT)
	close_button.offset_left = -28
	close_button.offset_top = 2
	close_button.offset_right = -4
	close_button.offset_bottom = 26
	close_button.pressed.connect(func(): visible = false)
	title_bar.add_child(close_button)

	# --- Scroll area ---
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.clip_contents = true
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root_vbox.add_child(scroll_container)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PADDING))
	margin.add_theme_constant_override("margin_right", int(PADDING))
	margin.add_theme_constant_override("margin_top", int(PADDING))
	margin.add_theme_constant_override("margin_bottom", int(PADDING))
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(margin)

	content_container = VBoxContainer.new()
	content_container.add_theme_constant_override("separation", 6)
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content_container)


func _build_sections() -> void:
	for child in content_container.get_children():
		child.queue_free()
	_equip_rows.clear()
	_stat_rows.clear()

	# --- Header ---
	_name_label = _make_label("", 14, Color(1.0, 0.95, 0.7))
	content_container.add_child(_name_label)
	_level_label = _make_label("", 11, Color(0.7, 0.8, 0.9))
	content_container.add_child(_level_label)

	var hp_row := _make_stat_row("HP", "", Color(0.9, 0.3, 0.3))
	_hp_value = hp_row.get_child(1)
	content_container.add_child(hp_row)

	var mp_row := _make_stat_row("MP", "", Color(0.3, 0.5, 0.9))
	_mp_value = mp_row.get_child(1)
	content_container.add_child(mp_row)

	var gold_row := _make_stat_row("Gold", "", Color(0.9, 0.8, 0.3))
	_gold_value = gold_row.get_child(1)
	content_container.add_child(gold_row)

	var map_row := _make_stat_row("Map", "", Color(0.6, 0.7, 0.6))
	_map_value = map_row.get_child(1)
	content_container.add_child(map_row)

	_action_row = _make_stat_row("Action", "", Color(0.6, 0.7, 0.6))
	_action_value = _action_row.get_child(1)
	content_container.add_child(_action_row)

	_add_separator()

	# --- Equipment (5 fixed rows) ---
	content_container.add_child(_make_label("Equipment", 12, Color(0.9, 0.85, 0.6)))
	var slot_names := ["Weapon", "Head", "Chest", "Legs", "Feet"]
	for slot_name in slot_names:
		var row := _make_item_row(slot_name, null)
		_equip_rows.append(row)
		content_container.add_child(row)

	_add_separator()

	# --- Stats (fixed rows) ---
	content_container.add_child(_make_label("Stats", 12, Color(0.9, 0.85, 0.6)))
	var stat_entries := [
		["STR", Constants.StatType.STRENGTH],
		["DEX", Constants.StatType.DEXTERITY],
		["INT", Constants.StatType.INTELLIGENCE],
		["LUK", Constants.StatType.LUCK],
		["W.ATK", Constants.StatType.WEAPONATTACK],
		["M.ATK", Constants.StatType.MAGICATTACK],
		["DEF", Constants.StatType.DEFENSE],
		["M.DEF", Constants.StatType.MAGICDEFENSE],
		["CRIT%", Constants.StatType.CRITCHANCE],
		["CRITD%", Constants.StatType.CRITDAMAGE],
	]
	for entry in stat_entries:
		var row := _make_stat_row(entry[0], "", Color(0.8, 0.8, 0.8))
		_stat_rows[entry[1]] = row.get_child(1)
		content_container.add_child(row)

	_add_separator()

	# --- Inventory (fixed rows + notable section) ---
	content_container.add_child(_make_label("Inventory", 12, Color(0.9, 0.85, 0.6)))

	var total_row := _make_stat_row("Total", "", Color(0.8, 0.8, 0.8))
	_inv_total_value = total_row.get_child(1)
	content_container.add_child(total_row)

	var equip_row := _make_stat_row("Equipment", "", Color(0.6, 0.8, 1.0))
	_inv_equip_value = equip_row.get_child(1)
	content_container.add_child(equip_row)

	var consumable_row := _make_stat_row("Consumables", "", Color(0.6, 1.0, 0.6))
	_inv_consumable_value = consumable_row.get_child(1)
	content_container.add_child(consumable_row)

	_inv_other_row = _make_stat_row("Other", "", Color(0.8, 0.8, 0.6))
	_inv_other_value = _inv_other_row.get_child(1)
	content_container.add_child(_inv_other_row)

	_inv_notable_section = VBoxContainer.new()
	_inv_notable_section.add_theme_constant_override("separation", 4)
	content_container.add_child(_inv_notable_section)

	_built = true


func show_bot(bot_id: int) -> void:
	_current_bot_id = bot_id
	_refresh_timer = 0.0
	_snapshot = {}
	_built = false
	_build_sections()
	_update_content()
	_request_snapshot()


## Asks the server for a fresh snapshot of the inspected bot.
func _request_snapshot() -> void:
	if _current_bot_id == 0:
		return
	BotManager.request_bot_snapshot.rpc_id(1, _current_bot_id)


func _on_bot_snapshot(bot_id: int, snapshot: Dictionary) -> void:
	if bot_id != _current_bot_id or not visible:
		return
	_snapshot = snapshot
	_update_content()

	var vp_size := get_viewport_rect().size
	global_position = (vp_size - size) * 0.5
	visible = true
	move_to_front()

	await get_tree().process_frame
	scroll_container.scroll_vertical = 0


## Populates the window from `_snapshot` (filled by the BotManager RPC), so it
## works on a client where the bot's live components hold no data.
func _update_content() -> void:
	if not _built or _snapshot.is_empty():
		return

	var display_name: String = _snapshot.get("name", "")
	if display_name.is_empty():
		display_name = "Bot %d" % _current_bot_id
	title_label.text = "Inspect: %s" % display_name
	_name_label.text = display_name

	_level_label.text = "Level %d %s" % [
		_snapshot.get("level", 1),
		Constants.ClassType.find_key(_snapshot.get("class", 0)),
	]

	_hp_value.text = "%d / %d" % [_snapshot.get("hp", 0), _snapshot.get("max_hp", 0)]
	_mp_value.text = "%d / %d" % [_snapshot.get("mp", 0), _snapshot.get("max_mp", 0)]
	_gold_value.text = str(_snapshot.get("gold", 0))
	_map_value.text = _snapshot.get("map", "")

	var action: String = _snapshot.get("action", "")
	_action_row.visible = not action.is_empty()
	_action_value.text = action

	# --- Equipment (5 fixed rows: Weapon, Head, Chest, Legs, Feet) ---
	var equipment: Dictionary = _snapshot.get("equipment", {})
	var eq_keys := [
		"WEAPON",
		str(Constants.ArmorType.HEAD), str(Constants.ArmorType.CHEST),
		str(Constants.ArmorType.LEGS), str(Constants.ArmorType.FEET),
	]
	for i in 5:
		var eq_item_dict: Dictionary = equipment.get(eq_keys[i], {})
		var eq_item: ItemData = ItemData.from_dictionary(eq_item_dict) if not eq_item_dict.is_empty() else null
		_update_item_row(_equip_rows[i], eq_item)

	# --- Stats ---
	var stats: Dictionary = _snapshot.get("stats", {})
	for stat_type in _stat_rows:
		var value_label: Label = _stat_rows[stat_type]
		if stats.has(stat_type):
			var s: Dictionary = stats[stat_type]
			var total: int = s.get("total", 0)
			var bonus: int = s.get("bonus", 0)
			if bonus > 0:
				value_label.text = "%d (%d+%d)" % [total, s.get("base", 0), bonus]
			else:
				value_label.text = "%d" % total
		else:
			value_label.text = "0"

	# --- Inventory ---
	var inventory: Array = _snapshot.get("inventory", [])
	var equip_count := 0
	var consumable_count := 0
	var other_count := 0
	var notable: Array = []
	for entry in inventory:
		var inv_item_dict: Dictionary = entry.get("item", {})
		if inv_item_dict.is_empty():
			continue
		var inv_item: ItemData = ItemData.from_dictionary(inv_item_dict)
		if not inv_item:
			continue
		if inv_item is EquipmentData:
			equip_count += 1
			if notable.size() < 5:
				notable.append(inv_item)
		elif inv_item is ConsumableData:
			consumable_count += 1
		else:
			other_count += 1

	_inv_total_value.text = str(inventory.size())
	_inv_equip_value.text = str(equip_count)
	_inv_consumable_value.text = str(consumable_count)
	_inv_other_value.text = str(other_count)
	_inv_other_row.visible = other_count > 0

	for child in _inv_notable_section.get_children():
		child.queue_free()
	for i in notable.size():
		if i == 0:
			_inv_notable_section.add_child(_make_label("Notable Items:", 10, Color(0.6, 0.6, 0.7)))
		var n_item: ItemData = notable[i]
		_inv_notable_section.add_child(_make_label("  %s (Lv.%d)" % [n_item.name, n_item.item_level], 9, Color(0.6, 0.7, 0.8)))


# --- Node Factories (return nodes, don't add to tree) ---

func _make_label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	return label


func _make_stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var label := Label.new()
	label.text = label_text
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	label.custom_minimum_size.x = 80
	row.add_child(label)

	var value := Label.new()
	value.text = value_text
	value.add_theme_font_size_override("font_size", 10)
	value.add_theme_color_override("font_color", value_color)
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(value)

	return row


func _make_item_row(slot_name: String, item: ItemData) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = slot_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	name_label.custom_minimum_size.x = 55
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(name_label)

	# Added missing placeholder TextureRect so icon slots can be safely indexed/replaced later
	var icon := TextureRect.new()
	icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(icon)

	var info := Label.new()
	info.add_theme_font_size_override("font_size", 10)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(info)

	_update_item_row(row, item)
	return row


func _update_item_row(row: HBoxContainer, item: ItemData) -> void:
	var icon_rect: TextureRect = row.get_child(1)
	var info_label: Label = row.get_child(2)

	if not is_instance_valid(item):
		icon_rect.texture = null
		icon_rect.visible = false
		info_label.text = "Empty"
		info_label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		row.tooltip_text = ""
		return

	if item.icon:
		icon_rect.texture = item.icon
		icon_rect.visible = true
	else:
		icon_rect.texture = null
		icon_rect.visible = false

	info_label.text = "%s Lv.%d" % [item.name, item.item_level]

	var rarity_color := Color(0.8, 0.8, 0.8)
	if item is EquipmentData:
		match item.rarity:
			Constants.ItemRarity.COMMON: rarity_color = Color(0.7, 0.7, 0.7)
			Constants.ItemRarity.UNCOMMON: rarity_color = Color(1.0, 1.0, 1.0)
			Constants.ItemRarity.RARE: rarity_color = Color(1.0, 0.6, 0.2)
			Constants.ItemRarity.EPIC: rarity_color = Color(0.7, 0.3, 0.9)
			Constants.ItemRarity.LEGENDARY: rarity_color = Color(1.0, 0.85, 0.0)
	info_label.add_theme_color_override("font_color", rarity_color)

	var tooltip := item.name
	if item is EquipmentData:
		var eq := item as EquipmentData
		for stat_type in eq.bonus_stats:
			var stat_data: StatData = eq.bonus_stats[stat_type]
			if stat_data.flat_bonus_value > 0:
				tooltip += "\n%s: +%d" % [Constants.StatType.find_key(stat_type), stat_data.flat_bonus_value]
	row.tooltip_text = tooltip


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.3, 0.3, 0.4, 0.5)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	content_container.add_child(sep)


# --- Draggable ---

func _process(delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos

	if visible and _current_bot_id != 0:
		_refresh_timer += delta
		if _refresh_timer >= REFRESH_INTERVAL:
			_refresh_timer = 0.0
			_request_snapshot()


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
