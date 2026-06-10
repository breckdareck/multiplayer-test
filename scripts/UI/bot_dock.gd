class_name BotDock
extends Panel
##
## Multi-bot live roster window — opened from the debug console via `botdock`
## (or the "Roster" quick-action). Host-only — bots are server-side; on a
## client the table would be empty.
##
## Layout: a live summary toolbar (counts, churn status, quick actions), the
## ONLINE table (HP/MP bars, color-coded class/personality/action, watched-row
## highlight), and the OFFLINE identity book from saves/bot_roster.json with
## per-row "Log In" (the same path churn login uses).
##
## Single-bot deep-dive remains BotInspectWindow (opened by /bot inspect and by
## this dock's "Inspect" row button).

const WINDOW_WIDTH: float = 880.0
const WINDOW_HEIGHT: float = 480.0
const TITLE_HEIGHT: float = 28.0
const PADDING: float = 8.0
const REFRESH_INTERVAL: float = 0.5

## Column layout — keep in sync with header + row builders.
const COL_WIDTHS := {
	"id": 40, "name": 110, "class": 64, "pers": 76, "lv": 44, "hp": 92, "mp": 92,
	"action": 160, "map": 110, "weapon": 110,
}
const COLUMNS := ["id", "name", "class", "pers", "lv", "hp", "mp", "action", "map", "weapon"]
const ACTIONS_WIDTH := 300  # combined min width of the row's action buttons

const CLASS_COLORS := {
	"SWORD": Color(0.95, 0.55, 0.40),
	"BOW": Color(0.55, 0.85, 0.50),
	"STAFF": Color(0.50, 0.70, 1.00),
	"DAGGER": Color(0.80, 0.55, 1.00),
}
const PERSONALITY_COLORS := {
	"butcher": Color(1.00, 0.45, 0.45),
	"bragger": Color(1.00, 0.85, 0.40),
	"quiet": Color(0.62, 0.66, 0.72),
	"helper": Color(0.50, 0.88, 0.55),
	"wanderer": Color(0.70, 0.60, 1.00),
}
const ACTION_COLORS := {
	"fight": Color(1.00, 0.48, 0.43),
	"retreat": Color(1.00, 0.62, 0.26),
	"travel": Color(0.48, 0.72, 1.00),
	"regroup": Color(0.43, 0.91, 0.91),
	"loot": Color(1.00, 0.85, 0.40),
	"wander": Color(0.66, 0.70, 0.76),
	"idle": Color(0.55, 0.58, 0.62),
}

const ROW_EVEN := Color(1, 1, 1, 0.03)
const ROW_ODD := Color(1, 1, 1, 0.00)
const ROW_WATCHED := Color(0.95, 0.80, 0.35, 0.14)

var is_dragging := false
var drag_offset := Vector2()
var _title_label: Label
var _summary_label: Label
var _rows_container: VBoxContainer
var _empty_label: Label
var _offline_header: Label
var _offline_container: VBoxContainer
var _refresh_timer: float = 0.0
var _row_by_bot: Dictionary = {}  # bot_id -> { row, panel_style, fields, hp, mp, watch_btn }
## Signature of the offline list currently rendered, so it only rebuilds when
## the identity set actually changes.
var _offline_signature: String = ""


static func create() -> BotDock:
	var window := BotDock.new()
	window.custom_minimum_size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.size = Vector2(WINDOW_WIDTH, WINDOW_HEIGHT)
	window.visible = false
	window.clip_contents = true
	window.mouse_filter = Control.MOUSE_FILTER_STOP
	window.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.10, 0.13, 0.96)
	bg.border_color = Color(0.35, 0.32, 0.25, 1.0)
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
	title_bg.bg_color = Color(0.17, 0.16, 0.20, 1.0)
	title_bg.set_corner_radius_all(4)
	title_bg.corner_radius_bottom_left = 0
	title_bg.corner_radius_bottom_right = 0
	title_bar.add_theme_stylebox_override("panel", title_bg)
	root_vbox.add_child(title_bar)

	_title_label = Label.new()
	_title_label.text = "Bot Roster"
	_title_label.add_theme_font_size_override("font_size", 13)
	_title_label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.55, 1.0))
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

	# --- Summary toolbar: live counts + quick actions ---
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 6)
	var toolbar_margin := MarginContainer.new()
	toolbar_margin.add_theme_constant_override("margin_left", int(PADDING))
	toolbar_margin.add_theme_constant_override("margin_right", int(PADDING))
	toolbar_margin.add_theme_constant_override("margin_top", 4)
	toolbar_margin.add_theme_constant_override("margin_bottom", 2)
	toolbar_margin.add_child(toolbar)
	root_vbox.add_child(toolbar_margin)

	_summary_label = _styled_label("", 11, Color(0.75, 0.78, 0.85))
	_summary_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(_summary_label)
	toolbar.add_child(_toolbar_button("Spawn", func():
		BotManager.handle_command(["spawn", "random",
			["SWORD", "BOW", "STAFF", "DAGGER"].pick_random()] as Array, multiplayer.get_unique_id())))
	toolbar.add_child(_toolbar_button("Churn Now", func():
		BotManager.handle_command(["churn", "now"] as Array, multiplayer.get_unique_id())))
	toolbar.add_child(_toolbar_button("Banter", func():
		BotManager.handle_command(["banter"] as Array, multiplayer.get_unique_id())))
	var despawn_all := _toolbar_button("Despawn All", func(): BotManager.despawn_all_bots())
	despawn_all.add_theme_color_override("font_color", Color(1.0, 0.55, 0.55))
	toolbar.add_child(despawn_all)

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
	content_margin.add_theme_constant_override("margin_top", 2)
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

	# --- Offline identity book (saves/bot_roster.json) ---
	_offline_header = _styled_label("", 11, Color(0.65, 0.68, 0.75))
	var off_margin := MarginContainer.new()
	off_margin.add_theme_constant_override("margin_top", 8)
	off_margin.add_child(_offline_header)
	content_vbox.add_child(off_margin)

	_offline_container = VBoxContainer.new()
	_offline_container.add_theme_constant_override("separation", 2)
	content_vbox.add_child(_offline_container)


func _build_header() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for col in COLUMNS:
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


func _toolbar_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 11)
	b.pressed.connect(handler)
	return b


## A slim colored bar with a centered value label (HP / MP cells).
func _make_bar(fill_color: Color, width: int) -> Dictionary:
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(width, 15)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.show_percentage = false
	bar.min_value = 0.0
	bar.max_value = 1.0
	var bg_sb := StyleBoxFlat.new()
	bg_sb.bg_color = Color(0, 0, 0, 0.5)
	bg_sb.set_corner_radius_all(3)
	var fill_sb := StyleBoxFlat.new()
	fill_sb.bg_color = fill_color
	fill_sb.set_corner_radius_all(3)
	bar.add_theme_stylebox_override("background", bg_sb)
	bar.add_theme_stylebox_override("fill", fill_sb)

	var lbl := Label.new()
	lbl.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 9)
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.95))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(lbl)
	return {"bar": bar, "label": lbl}


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
## despawned, updates fields in place for everyone else. Avoids tearing down
## the whole table on every refresh tick.
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
	_title_label.text = "Bot Roster  (%d online)" % _row_by_bot.size()

	_apply_row_styles()
	_update_summary()
	_refresh_offline()


## Row striping + watched-row highlight, recomputed over the live visual order.
func _apply_row_styles() -> void:
	var watched: int = BotManager.get_watched_bot() if BotManager.has_method("get_watched_bot") else 0
	var index := 0
	for child in _rows_container.get_children():
		if child == _empty_label or not (child is PanelContainer):
			continue
		var bot_id: int = child.get_meta("bot_id", 0)
		var style: StyleBoxFlat = _row_by_bot.get(bot_id, {}).get("panel_style")
		if style == null:
			continue
		if bot_id == watched:
			style.bg_color = ROW_WATCHED
		else:
			style.bg_color = ROW_EVEN if index % 2 == 0 else ROW_ODD
		index += 1
		var btn: Button = _row_by_bot[bot_id].watch_btn
		if is_instance_valid(btn):
			btn.text = "Unwatch" if bot_id == watched else "Watch"


func _update_summary() -> void:
	var fighting := 0
	var traveling := 0
	for bot_id in BotManager.active_bots:
		var brain = BotManager.get_bot_brain(bot_id)
		if brain == null:
			continue
		match String(brain.current_action):
			"fight": fighting += 1
			"travel": traveling += 1
	var churn_cfg: Dictionary = BotManager.bot_config.get("churn", {})
	var churn_str := "churn OFF"
	if churn_cfg.get("enabled", false):
		churn_str = "churn ON (next ~%ds)" % int(maxf(BotManager._churn_timer, 0.0))
	_summary_label.text = "%d online · %d fighting · %d traveling · %s" % [
		BotManager.active_bots.size(), fighting, traveling, churn_str]


func _add_row(bot_id: int) -> void:
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = ROW_ODD
	panel_style.set_corner_radius_all(3)
	panel_style.content_margin_left = 2
	panel_style.content_margin_right = 2
	panel_style.content_margin_top = 1
	panel_style.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.set_meta("bot_id", bot_id)
	_rows_container.add_child(panel)
	# Keep the empty label at the end so it disappears behind data rows.
	_rows_container.move_child(_empty_label, _rows_container.get_child_count() - 1)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)

	var fields: Dictionary = {}
	var hp: Dictionary = {}
	var mp: Dictionary = {}
	for col in COLUMNS:
		if col == "hp" or col == "mp":
			var made := _make_bar(
				Color(0.80, 0.25, 0.25) if col == "hp" else Color(0.25, 0.45, 0.85),
				COL_WIDTHS[col])
			row.add_child(made.bar)
			if col == "hp": hp = made
			else: mp = made
			continue
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
	var despawn_btn := _row_button("Logoff", func(): _on_despawn(bot_id))
	despawn_btn.add_theme_color_override("font_color", Color(1.0, 0.5, 0.5))
	actions_box.add_child(despawn_btn)

	_row_by_bot[bot_id] = {
		"row": panel, "panel_style": panel_style, "fields": fields,
		"hp": hp, "mp": mp, "watch_btn": watch_btn,
	}


func _update_row(bot_id: int) -> void:
	var info: Dictionary = BotManager.active_bots.get(bot_id, {})
	var data: Dictionary = _row_by_bot[bot_id]
	var fields: Dictionary = data.fields

	fields.id.text = str(bot_id)
	fields.name.text = String(info.get("username", "?"))

	var class_key: String = String(Constants.ClassType.find_key(info.get("class_type", 0)))
	fields["class"].text = class_key
	fields["class"].add_theme_color_override("font_color", CLASS_COLORS.get(class_key, Color.WHITE))

	var pers: String = String(info.get("personality", "—"))
	fields.pers.text = pers
	fields.pers.add_theme_color_override("font_color",
		PERSONALITY_COLORS.get(pers, Color(0.85, 0.85, 0.9)))

	var map_id: String = String(info.get("map_id", "?"))
	fields.map.text = MapManager._map_display_name(map_id)
	fields.map.tooltip_text = map_id

	var node := PlayerManager.get_player_node(bot_id)
	if is_instance_valid(node):
		fields.lv.text = "Lv.%s" % (str(node.level_component.level) if is_instance_valid(node.level_component) else "?")
		if is_instance_valid(node.health_component):
			_set_bar(data.hp, node.health_component.current_health, node.health_component.max_health)
		if "mana_component" in node and is_instance_valid(node.mana_component):
			_set_bar(data.mp, node.mana_component.current_mana, node.mana_component.max_mana)
		fields.weapon.text = _weapon_name_for(node)
	else:
		fields.lv.text = "?"
		_set_bar(data.hp, 0, 0)
		_set_bar(data.mp, 0, 0)
		fields.weapon.text = "?"

	var brain = BotManager.get_bot_brain(bot_id)
	if brain != null:
		var action: String = String(brain.current_action)
		var action_color: Color = ACTION_COLORS.get(action, Color(0.8, 0.8, 0.85))
		# Annotate with current target when fighting / chasing, and with an
		# active companion command (those override normal priorities).
		if is_instance_valid(brain.target_enemy):
			action += " → " + String(brain.target_enemy.monster_name if "monster_name" in brain.target_enemy else brain.target_enemy.name)
		if not brain.companion_mode.is_empty():
			action += "  [%s]" % brain.companion_mode
		fields.action.text = action
		fields.action.add_theme_color_override("font_color", action_color)
	else:
		fields.action.text = "(no brain)"
		fields.action.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))


func _set_bar(bar_data: Dictionary, current: int, max_value: int) -> void:
	if bar_data.is_empty():
		return
	var bar: ProgressBar = bar_data.bar
	var lbl: Label = bar_data.label
	if max_value <= 0:
		bar.value = 0.0
		lbl.text = "?"
		return
	bar.value = clampf(float(current) / float(max_value), 0.0, 1.0)
	lbl.text = "%d/%d" % [current, max_value]


func _weapon_name_for(node: Node) -> String:
	# Equipment is keyed by EquipmentType; reach in defensively because the bot
	# may not have a weapon slot wired yet.
	if not "equipment_component" in node: return "—"
	var eq = node.equipment_component
	if not is_instance_valid(eq) or not "slots_data" in eq: return "—"
	for key in eq.slots_data:
		var slot = eq.slots_data[key]
		if slot and slot.item and "name" in slot.item:
			if str(key).to_lower().find("weapon") >= 0:
				return String(slot.item.name)
	return "—"


# --- Offline identity book ----------------------------------------------------

## Rebuilds the offline list only when the identity SET changes (names are
## stable between churn events; per-tick rebuild would just flicker buttons).
func _refresh_offline() -> void:
	var offline: Array = BotManager._offline_identities()
	var roster: Dictionary = BotManager.get_roster()
	var sig_parts: PackedStringArray = []
	for entry in offline:
		sig_parts.append(String(entry.name))
	sig_parts.sort()
	var signature := ",".join(sig_parts)
	_offline_header.text = "OFFLINE IDENTITIES  (%d — churn logs these in over time)" % offline.size()
	if signature == _offline_signature:
		return
	_offline_signature = signature

	for child in _offline_container.get_children():
		child.queue_free()
	for entry in offline:
		var identity_name: String = String(entry.name)
		var roster_entry: Dictionary = roster.get(identity_name, {})
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.modulate = Color(1, 1, 1, 0.75)

		var dot := _styled_label("○", 11, Color(0.55, 0.58, 0.62))
		dot.custom_minimum_size = Vector2(COL_WIDTHS.id, 0)
		row.add_child(dot)

		var name_lbl := _styled_label(identity_name, 11, Color(0.85, 0.85, 0.9))
		name_lbl.custom_minimum_size = Vector2(COL_WIDTHS.name, 0)
		row.add_child(name_lbl)

		var class_key: String = String(roster_entry.get("class",
			Constants.ClassType.find_key(entry.class_type)))
		var class_lbl := _styled_label(class_key, 11, CLASS_COLORS.get(class_key, Color.WHITE))
		class_lbl.custom_minimum_size = Vector2(COL_WIDTHS["class"], 0)
		row.add_child(class_lbl)

		var pers: String = String(roster_entry.get("personality", "—"))
		var pers_lbl := _styled_label(pers, 11, PERSONALITY_COLORS.get(pers, Color(0.85, 0.85, 0.9)))
		pers_lbl.custom_minimum_size = Vector2(COL_WIDTHS.pers, 0)
		row.add_child(pers_lbl)

		var seen_lbl := _styled_label("seen %s" % BotManager._format_ago(int(roster_entry.get("last_seen", 0))),
			11, Color(0.6, 0.63, 0.68))
		seen_lbl.custom_minimum_size = Vector2(120, 0)
		row.add_child(seen_lbl)

		var rep: Dictionary = roster_entry.get("rep", {})
		var rep_lbl := _styled_label(
			"knows %d player(s)" % rep.size() if not rep.is_empty() else "knows nobody",
			11, Color(0.6, 0.63, 0.68))
		rep_lbl.custom_minimum_size = Vector2(130, 0)
		row.add_child(rep_lbl)

		var login_btn := _row_button("Log In", func(): _on_login(identity_name))
		login_btn.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6))
		row.add_child(login_btn)

		_offline_container.add_child(row)


func _on_login(identity_name: String) -> void:
	BotManager.login_identity(identity_name)
	_offline_signature = ""  # force the offline list to rebuild next tick


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
	_offline_signature = ""  # the identity returns to the offline book


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
