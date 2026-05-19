class_name BotInspectWindow
extends Panel

var is_dragging := false
var drag_offset := Vector2()
var title_label: Label
var content_container: VBoxContainer
var close_button: Button

const WINDOW_WIDTH: float = 320.0
const WINDOW_HEIGHT: float = 500.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const ICON_SIZE: float = 32.0


static func create() -> BotInspectWindow:
	var window := BotInspectWindow.new()
	window.custom_minimum_size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.visible = false
	window.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	bg.border_color = Color(0.3, 0.3, 0.4, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	window.add_theme_stylebox_override("panel", bg)

	window._build_ui()
	return window


func _build_ui() -> void:
	# Title bar
	var title_bar := Panel.new()
	title_bar.custom_minimum_size = Vector2(0, TITLE_HEIGHT)
	title_bar.set_anchors_preset(PRESET_TOP_WIDE)
	title_bar.size = Vector2(WINDOW_WIDTH, TITLE_HEIGHT)
	var title_bg := StyleBoxFlat.new()
	title_bg.bg_color = Color(0.18, 0.18, 0.22, 1.0)
	title_bg.set_corner_radius_all(4)
	title_bg.corner_radius_bottom_left = 0
	title_bg.corner_radius_bottom_right = 0
	title_bar.add_theme_stylebox_override("panel", title_bg)
	add_child(title_bar)

	title_label = Label.new()
	title_label.text = "Bot Inspect"
	title_label.add_theme_font_size_override("font_size", 13)
	title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	title_label.position = Vector2(PADDING, 4)
	title_bar.add_child(title_label)

	close_button = Button.new()
	close_button.text = "X"
	close_button.flat = true
	close_button.add_theme_font_size_override("font_size", 12)
	close_button.add_theme_color_override("font_color", Color.WHITE)
	close_button.add_theme_color_override("font_hover_color", Color.RED)
	close_button.position = Vector2(WINDOW_WIDTH - 28, 2)
	close_button.size = Vector2(24, 24)
	close_button.pressed.connect(func(): visible = false)
	title_bar.add_child(close_button)

	# Scrollable content
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(0, TITLE_HEIGHT)
	scroll.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT - TITLE_HEIGHT)
	scroll.set_anchors_preset(PRESET_FULL_RECT)
	scroll.offset_top = TITLE_HEIGHT
	add_child(scroll)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(PADDING))
	margin.add_theme_constant_override("margin_right", int(PADDING))
	margin.add_theme_constant_override("margin_top", int(PADDING))
	margin.add_theme_constant_override("margin_bottom", int(PADDING))
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(margin)

	content_container = VBoxContainer.new()
	content_container.add_theme_constant_override("separation", 6)
	content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_child(content_container)


func show_bot(bot_id: int) -> void:
	var player_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(player_node):
		return

	var bot_info: Dictionary = BotManager.active_bots.get(bot_id, {})
	var bot_name: String = bot_info.get("username", "Bot %d" % bot_id)

	title_label.text = "Inspect: %s" % bot_name

	# Clear old content
	for child in content_container.get_children():
		child.queue_free()

	_add_header_section(player_node, bot_name)
	_add_separator()
	_add_equipment_section(player_node)
	_add_separator()
	_add_stats_section(player_node)
	_add_separator()
	_add_inventory_section(player_node)

	# Position near center of screen
	var vp_size := get_viewport_rect().size
	global_position = (vp_size - size) * 0.5
	visible = true
	move_to_front()


func _add_header_section(player_node: Node, bot_name: String) -> void:
	var class_str := "Unknown"
	if is_instance_valid(player_node.class_component):
		class_str = Constants.ClassType.find_key(player_node.class_component.current_class)
	var level := 1
	if is_instance_valid(player_node.level_component):
		level = player_node.level_component.level

	_add_label("%s" % bot_name, 14, Color(1.0, 0.95, 0.7))
	_add_label("Level %d %s" % [level, class_str], 11, Color(0.7, 0.8, 0.9))

	var hp_str := "?"
	if is_instance_valid(player_node.health_component):
		hp_str = "%d / %d" % [player_node.health_component.current_health, player_node.health_component.max_health]
	var mp_str := "?"
	if is_instance_valid(player_node.mana_component):
		mp_str = "%d / %d" % [player_node.mana_component.current_mana, player_node.mana_component.max_mana]
	var gold := 0
	if is_instance_valid(player_node.player_inventory):
		gold = player_node.player_inventory.monies_amount

	_add_stat_row("HP", hp_str, Color(0.9, 0.3, 0.3))
	_add_stat_row("MP", mp_str, Color(0.3, 0.5, 0.9))
	_add_stat_row("Gold", str(gold), Color(0.9, 0.8, 0.3))

	var map_id := MapManager.get_player_map(player_node.player_id)
	var brain = player_node.get_node_or_null("BotBrain")
	var action := "unknown"
	if brain:
		action = brain.current_action
	_add_stat_row("Map", map_id, Color(0.6, 0.7, 0.6))
	_add_stat_row("Action", action, Color(0.6, 0.7, 0.6))


func _add_equipment_section(player_node: Node) -> void:
	_add_label("Equipment", 12, Color(0.9, 0.85, 0.6))

	if not is_instance_valid(player_node.equipment_component):
		_add_label("  (unavailable)", 10, Color(0.5, 0.5, 0.5))
		return

	var eq = player_node.equipment_component
	var slot_data := [
		["Weapon", eq.weapon_slot],
		["Head", eq.head_slot],
		["Chest", eq.chest_slot],
		["Legs", eq.legs_slot],
		["Feet", eq.feet_slot],
	]

	for entry in slot_data:
		var slot_name: String = entry[0]
		var slot: EquipmentSlot = entry[1]
		if slot and slot.item:
			_add_item_row(slot_name, slot.item)
		else:
			_add_stat_row(slot_name, "(empty)", Color(0.4, 0.4, 0.4))


func _add_stats_section(player_node: Node) -> void:
	_add_label("Stats", 12, Color(0.9, 0.85, 0.6))

	if not is_instance_valid(player_node.stats_component):
		_add_label("  (unavailable)", 10, Color(0.5, 0.5, 0.5))
		return

	var stats: Dictionary = player_node.stats_component.stats
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
		var label_text: String = entry[0]
		var stat_type = entry[1]
		if stats.has(stat_type):
			var stat_data = stats[stat_type]
			var total: int = stat_data.total_value
			var base: int = stat_data.base_value
			var bonus: int = stat_data.combined_bonus_value
			var value_str := "%d" % total
			if bonus > 0:
				value_str = "%d (%d+%d)" % [total, base, bonus]
			_add_stat_row(label_text, value_str, Color(0.8, 0.8, 0.8))


func _add_inventory_section(player_node: Node) -> void:
	_add_label("Inventory", 12, Color(0.9, 0.85, 0.6))

	if not is_instance_valid(player_node.inventory_component):
		_add_label("  (unavailable)", 10, Color(0.5, 0.5, 0.5))
		return

	var equip_count := 0
	var consumable_count := 0
	var other_count := 0
	var total_items := 0

	for slot in player_node.inventory_component.slots:
		if slot.item:
			total_items += 1
			if slot.item is EquipmentData:
				equip_count += 1
			elif slot.item is ConsumableData:
				consumable_count += 1
			else:
				other_count += 1

	_add_stat_row("Total", str(total_items), Color(0.8, 0.8, 0.8))
	_add_stat_row("Equipment", str(equip_count), Color(0.6, 0.8, 1.0))
	_add_stat_row("Consumables", str(consumable_count), Color(0.6, 1.0, 0.6))
	if other_count > 0:
		_add_stat_row("Other", str(other_count), Color(0.8, 0.8, 0.6))

	# Show notable items
	var notable_items: Array[String] = []
	for slot in player_node.inventory_component.slots:
		if slot.item and slot.item is EquipmentData:
			if notable_items.size() < 5:
				notable_items.append("  %s (Lv.%d)" % [slot.item.name, slot.item.item_level])

	if not notable_items.is_empty():
		_add_label("Notable Items:", 10, Color(0.6, 0.6, 0.7))
		for item_text in notable_items:
			_add_label(item_text, 9, Color(0.6, 0.7, 0.8))


# --- UI Helpers ---

func _add_label(text: String, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	content_container.add_child(label)


func _add_stat_row(label_text: String, value_text: String, value_color: Color) -> void:
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

	content_container.add_child(row)


func _add_item_row(slot_name: String, item: ItemData) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var name_label := Label.new()
	name_label.text = slot_name
	name_label.add_theme_font_size_override("font_size", 10)
	name_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	name_label.custom_minimum_size.x = 55
	row.add_child(name_label)

	if item.icon:
		var icon := TextureRect.new()
		icon.texture = item.icon
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(icon)

	var info := Label.new()
	info.text = "%s Lv.%d" % [item.name, item.item_level]
	info.add_theme_font_size_override("font_size", 10)

	var rarity_color := Color(0.8, 0.8, 0.8)
	if item is EquipmentData:
		match item.rarity:
			Constants.ItemRarity.COMMON: rarity_color = Color(0.7, 0.7, 0.7)
			Constants.ItemRarity.UNCOMMON: rarity_color = Color(1.0, 1.0, 1.0)
			Constants.ItemRarity.RARE: rarity_color = Color(1.0, 0.6, 0.2)
			Constants.ItemRarity.EPIC: rarity_color = Color(0.7, 0.3, 0.9)
			Constants.ItemRarity.LEGENDARY: rarity_color = Color(1.0, 0.85, 0.0)
	info.add_theme_color_override("font_color", rarity_color)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)

	# Tooltip with stats
	var tooltip := item.name
	if item is EquipmentData:
		var eq := item as EquipmentData
		for stat_type in eq.bonus_stats:
			var stat_data: StatData = eq.bonus_stats[stat_type]
			if stat_data.flat_bonus_value > 0:
				tooltip += "\n%s: +%d" % [Constants.StatType.find_key(stat_type), stat_data.flat_bonus_value]
	row.tooltip_text = tooltip

	content_container.add_child(row)


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

func _process(_delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos


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
