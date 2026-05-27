class_name BotDock
extends Panel
##
## Multi-bot live roster window — opened from the debug console via `botdock`
## (or the "Roster" quick-action). Lists every active bot in a table with
## per-row Watch / Inspect / Come / Despawn buttons. Host-only — bots are
## server-side; on a client the table would be empty.
##
## Single-bot deep-dive remains the existing BotInspectWindow (opened by
## /bot inspect <id> and by this dock's "Inspect" row button).

const WINDOW_WIDTH: float = 760.0
const WINDOW_HEIGHT: float = 360.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const REFRESH_INTERVAL: float = 0.5

## Column layout — keep in sync with header + row builders.
const COL_WIDTHS := {
	"id": 44, "name": 110, "class": 70, "lv": 36, "hp": 80, "mp": 80,
	"action": 130, "map": 70, "weapon": 110,
}
const ACTIONS_WIDTH := 320  # combined min width of the row's action buttons

var is_dragging := false
var drag_offset := Vector2()
var _title_label: Label
var _rows_container: VBoxContainer
var _empty_label: Label
var _refresh_timer: float = 0.0
var _row_by_bot: Dictionary = {}  # bot_id -> { row: HBoxContainer, fields: Dictionary, watch_btn: Button }


static func create() -> BotDock:
	var window := BotDock.new()
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
	return window


func _build_ui() -> void:
	var root_vbox := VBoxContainer.new()
	root_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root_vbox.add_theme_constant_override("separation", 0)
	add_child(root_vbox)

	# --- Title bar (draggable) ---
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

	_title_label = Label.new()
	_title_label.text = "Bot Roster"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6, 1.0))
	_title_label.position = Vector2(PADDING, 4)
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_bar.add_child(_title_label)

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

	# --- Scrollable content (header + rows together so they scroll horizontally
	# in lock-step). Vertical scrolling moves the header off-screen, which is
	# acceptable for a debug tool.
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.clip_contents = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	root_vbox.add_child(scroll)

	var content_margin := MarginContainer.new()
	content_margin.add_theme_constant_override("margin_left", int(PADDING))
	content_margin.add_theme_constant_override("margin_right", int(PADDING))
	content_margin.add_theme_constant_override("margin_top", int(PADDING))
	content_margin.add_theme_constant_override("margin_bottom", int(PADDING))
	# Note: do NOT set SIZE_EXPAND_FILL on the content — we want it to take its
	# natural width so the ScrollContainer reveals a horizontal scroll bar when
	# the table is wider than the window.
	scroll.add_child(content_margin)

	var content_vbox := VBoxContainer.new()
	content_vbox.add_theme_constant_override("separation", 2)
	content_margin.add_child(content_vbox)

	content_vbox.add_child(_build_header())

	_rows_container = VBoxContainer.new()
	_rows_container.add_theme_constant_override("separation", 2)
	content_vbox.add_child(_rows_container)

	_empty_label = Label.new()
	_empty_label.text = "(no active bots — try /bot spawn random SWORD)"
	_empty_label.modulate = Color(1, 1, 1, 0.5)
	_rows_container.add_child(_empty_label)


func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for col in ["id", "name", "class", "lv", "hp", "mp", "action", "map", "weapon"]:
		var lab := _styled_label(col.to_upper(), 11, Color(0.7, 0.75, 0.85))
		lab.custom_minimum_size = Vector2(COL_WIDTHS[col], 0)
		row.add_child(lab)
	var actions_header := _styled_label("ACTIONS", 11, Color(0.7, 0.75, 0.85))
	actions_header.custom_minimum_size = Vector2(ACTIONS_WIDTH, 0)
	row.add_child(actions_header)
	return row


func _styled_label(text: String, font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


# --- Refresh -----------------------------------------------------------------

func _process(delta: float) -> void:
	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp_size := get_viewport_rect().size
		new_pos.x = clampf(new_pos.x, 0, vp_size.x - size.x)
		new_pos.y = clampf(new_pos.y, 0, vp_size.y - size.y)
		global_position = new_pos
	if not visible: return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh()


## Builds new rows for bots that just appeared, removes rows for bots that
## despawned, updates text fields in place for everyone else. Avoids tearing
## down the whole table on every refresh tick.
func _refresh() -> void:
	if not multiplayer.is_server():
		_empty_label.text = "(host-only — open this on the server)"
		_empty_label.visible = true
		return

	var live_ids: Dictionary = {}
	for bot_id in BotManager.active_bots:
		live_ids[bot_id] = true
		if not _row_by_bot.has(bot_id):
			_add_row(bot_id)
		_update_row(bot_id)

	# Reap rows for despawned bots.
	for bot_id in _row_by_bot.keys():
		if not live_ids.has(bot_id):
			var row_data: Dictionary = _row_by_bot[bot_id]
			if is_instance_valid(row_data.row):
				row_data.row.queue_free()
			_row_by_bot.erase(bot_id)

	_empty_label.visible = _row_by_bot.is_empty()
	_title_label.text = "Bot Roster  (%d active)" % _row_by_bot.size()

	# Highlight the currently-watched bot.
	var watched: int = BotManager.get_watched_bot() if BotManager.has_method("get_watched_bot") else 0
	for bot_id in _row_by_bot:
		var btn: Button = _row_by_bot[bot_id].watch_btn
		if is_instance_valid(btn):
			btn.text = "Stop Watch" if bot_id == watched else "Watch"


func _add_row(bot_id: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_rows_container.add_child(row)
	# Make sure empty label is reordered to the end so it disappears behind data rows.
	_rows_container.move_child(_empty_label, _rows_container.get_child_count() - 1)

	var fields: Dictionary = {}
	for col in ["id", "name", "class", "lv", "hp", "mp", "action", "map", "weapon"]:
		var l := _styled_label("", 11, Color.WHITE)
		l.custom_minimum_size = Vector2(COL_WIDTHS[col], 0)
		l.clip_text = true
		row.add_child(l)
		fields[col] = l

	var actions_box := HBoxContainer.new()
	actions_box.custom_minimum_size = Vector2(ACTIONS_WIDTH, 0)
	actions_box.add_theme_constant_override("separation", 4)
	row.add_child(actions_box)

	var watch_btn := _row_button("Watch", func(): _on_watch(bot_id))
	actions_box.add_child(watch_btn)
	actions_box.add_child(_row_button("Inspect", func(): _on_inspect(bot_id)))
	actions_box.add_child(_row_button("Come", func(): _on_come(bot_id)))
	var despawn_btn := _row_button("Despawn", func(): _on_despawn(bot_id))
	despawn_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	actions_box.add_child(despawn_btn)

	_row_by_bot[bot_id] = { "row": row, "fields": fields, "watch_btn": watch_btn }


func _update_row(bot_id: int) -> void:
	var info: Dictionary = BotManager.active_bots.get(bot_id, {})
	var fields: Dictionary = _row_by_bot[bot_id].fields
	fields.id.text = str(bot_id)
	fields.name.text = String(info.get("username", "?"))
	fields["class"].text = String(Constants.ClassType.find_key(info.get("class_type", 0)))
	fields.map.text = String(info.get("map_id", "?"))

	var node := PlayerManager.get_player_node(bot_id)
	if is_instance_valid(node):
		fields.lv.text = str(node.level_component.level) if is_instance_valid(node.level_component) else "?"
		if is_instance_valid(node.health_component):
			fields.hp.text = "%d/%d" % [node.health_component.current_health, node.health_component.max_health]
		if "mana_component" in node and is_instance_valid(node.mana_component):
			fields.mp.text = "%d/%d" % [node.mana_component.current_mana, node.mana_component.max_mana]
		fields.weapon.text = _weapon_name_for(node)
	else:
		fields.lv.text = "?"
		fields.hp.text = "?"
		fields.mp.text = "?"
		fields.weapon.text = "?"

	var brain = BotManager.get_bot_brain(bot_id)
	if brain != null:
		var action: String = String(brain.current_action)
		# Annotate with current target when fighting / chasing.
		if is_instance_valid(brain.target_enemy):
			action += " → " + String(brain.target_enemy.name)
		fields.action.text = action
	else:
		fields.action.text = "(no brain)"


func _weapon_name_for(node: Node) -> String:
	# Equipment is keyed by EquipmentType; reach in defensively because the bot
	# may not have a weapon slot wired yet.
	if not "equipment_component" in node: return "—"
	var eq = node.equipment_component
	if not is_instance_valid(eq) or not "slots_data" in eq: return "—"
	for key in eq.slots_data:
		var slot = eq.slots_data[key]
		if slot and slot.item and "name" in slot.item:
			# Equipment slots include head/chest/legs/feet/weapon; only weapon
			# typically has a recognizable damage value, but for the dock we
			# just report whatever item is in the weapon slot.
			if str(key).to_lower().find("weapon") >= 0:
				return String(slot.item.name)
	return "—"


func _row_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(handler)
	return b


# --- Row actions ------------------------------------------------------------

func _on_watch(bot_id: int) -> void:
	var watched: int = BotManager.get_watched_bot() if BotManager.has_method("get_watched_bot") else 0
	BotManager.watch_bot(0 if bot_id == watched else bot_id)


func _on_inspect(bot_id: int) -> void:
	BotManager.open_inspect_window(bot_id)


func _on_come(bot_id: int) -> void:
	var host := PlayerManager.get_player_node(multiplayer.get_unique_id())
	if not is_instance_valid(host): return
	var host_map: String = MapManager.get_player_map(host.player_id)
	# `request_map_change` always runs a full despawn/respawn cycle, so we only
	# trigger it when the bot is actually on a different map. Otherwise the bot
	# gets re-spawned in place and the previous body is left as a ghost.
	var bot_map: String = MapManager.get_player_map(bot_id) if MapManager.has_method("get_player_map") else ""
	if bot_map != host_map:
		BotManager.active_bots[bot_id].map_id = host_map
		MapManager.request_map_change(bot_id, host_map)
		# The new body isn't live yet; position will be set when the bot
		# rejoins this map on its next refresh tick. Bail here.
		return
	var bot_node := PlayerManager.get_player_node(bot_id)
	if is_instance_valid(bot_node):
		bot_node.global_position = host.global_position


func _on_despawn(bot_id: int) -> void:
	BotManager.despawn_bot(bot_id)


# --- Drag handling (title bar grabs the window) ----------------------------

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
