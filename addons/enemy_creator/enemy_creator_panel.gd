@tool
extends Control

# ── Theme palette ─────────────────────────────────────────────
const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BLUE   = Color(0.42, 0.68, 1.00)
const C_RED    = Color(0.95, 0.38, 0.38)
const C_ORANGE = Color(1.00, 0.62, 0.28)
const C_GRAY   = Color(0.38, 0.40, 0.46)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_OK     = Color(0.28, 0.90, 0.45)
const C_ERR    = Color(1.00, 0.35, 0.35)

# ── Widget refs ───────────────────────────────────────────────
var tabs: TabContainer
var resource_tree: Tree
var status_label: Label
var file_dialog: FileDialog

var name_edit: LineEdit
var level_spin: SpinBox
var speed_spin: SpinBox
var drop_rows_box: VBoxContainer
var drop_rows: Array = []

# Available item names scanned from resources/Items/
var available_items: Array[String] = []

var _last_card_outer: PanelContainer = null

# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	name = "Enemy Creator"
	custom_minimum_size = Vector2(260, 0)
	_scan_available_items()
	_build_ui()
	_refresh_browser()
	_add_drop_row()   # start with one blank row


# ─────────────────────────────────────────────────────────────
# ITEM SCANNING
# ─────────────────────────────────────────────────────────────
func _scan_available_items() -> void:
	available_items.clear()
	_scan_items_recursive("res://resources/Items")
	available_items.sort()


func _scan_items_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var f = dir.get_next()
	while f != "":
		var full = path.path_join(f)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(full)):
			if not f.begins_with("."):
				_scan_items_recursive(full)
		elif f.get_extension() in ["tres", "res"]:
			var res = load(full)
			if res is ItemData and not res.name.is_empty() and not available_items.has(res.name):
				available_items.append(res.name)
		f = dir.get_next()


func _refresh_items() -> void:
	_scan_available_items()
	# Update every existing drop row's OptionButton
	for row in drop_rows:
		var opt = row.item_opt as OptionButton
		var current = opt.get_item_text(opt.selected)
		opt.clear()
		for item_name in available_items:
			opt.add_item(item_name)
		# Try to re-select previous value
		for i in range(opt.item_count):
			if opt.get_item_text(i) == current:
				opt.select(i); break
	_set_status("Item list refreshed (%d items found)." % available_items.size())


# ─────────────────────────────────────────────────────────────
# UI CONSTRUCTION
# ─────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var root = VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	root.add_child(_build_toolbar())

	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)

	var browse = _build_browse_tab()
	browse.name = "Browse"
	tabs.add_child(browse)

	var edit = _build_edit_tab()
	edit.name = "Create / Edit"
	tabs.add_child(edit)

	var bar = PanelContainer.new()
	_style_panel(bar, C_DARK)
	var bm = MarginContainer.new()
	_margin(bm, 8, 3, 8, 4)
	status_label = Label.new()
	status_label.text = "Create or browse existing enemies."
	status_label.add_theme_color_override("font_color", C_DIM)
	status_label.add_theme_font_size_override("font_size", 10)
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bm.add_child(status_label)
	bar.add_child(bm)
	root.add_child(bar)

	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.add_filter("*.tres", "Godot Resource")
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


func _build_toolbar() -> PanelContainer:
	var panel = PanelContainer.new()
	_style_panel(panel, C_DARK)
	var m = MarginContainer.new()
	_margin(m, 8, 6, 8, 6)
	panel.add_child(m)
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)
	m.add_child(hbox)

	var title = Label.new()
	title.text = "ENEMY CREATOR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_RED)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(title)
	hbox.add_child(_btn("New",  false, _on_new_pressed))
	hbox.add_child(_btn("Save", true,  _on_save_pressed))
	hbox.add_child(_btn("As…",  false, _on_save_as_pressed))
	return panel


func _build_browse_tab() -> Control:
	var m = MarginContainer.new()
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_margin(m, 6, 6, 6, 6)
	var vbox = VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	m.add_child(vbox)

	var row = HBoxContainer.new()
	row.add_child(_btn("⟳ Refresh", false, _refresh_browser))
	row.add_child(_btn("Load Selected →", true, _on_load_selected))
	vbox.add_child(row)

	resource_tree = Tree.new()
	resource_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	resource_tree.hide_root = true
	resource_tree.item_activated.connect(_on_load_selected)
	vbox.add_child(resource_tree)

	var hint = Label.new()
	hint.text = "Double-click to load into the editor."
	hint.add_theme_color_override("font_color", C_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	vbox.add_child(hint)
	return m


func _build_edit_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m = MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_margin(m, 6, 8, 6, 8)
	scroll.add_child(m)
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 8)
	m.add_child(vbox)

	# ── Basic Info Card ──────────────────────────────────────
	var info_c = _make_card(vbox, "BASIC INFO", C_BLUE)
	name_edit = _row(info_c, "Name", LineEdit.new()) as LineEdit
	name_edit.placeholder_text = "e.g. Slime"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	level_spin = _row(info_c, "Level", SpinBox.new()) as SpinBox
	level_spin.min_value = 1; level_spin.max_value = 999; level_spin.value = 1
	level_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	speed_spin = _row(info_c, "Move Speed", SpinBox.new()) as SpinBox
	speed_spin.min_value = 10; speed_spin.max_value = 500
	speed_spin.value = 60; speed_spin.step = 0.5
	speed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Drop Table Card ──────────────────────────────────────
	var drop_c = _make_card(vbox, "DROP TABLE", C_ORANGE)

	# Item list refresh button
	var refresh_row = HBoxContainer.new()
	var items_lbl = Label.new()
	items_lbl.text = "%d items available" % available_items.size()
	items_lbl.add_theme_color_override("font_color", C_DIM)
	items_lbl.add_theme_font_size_override("font_size", 10)
	items_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	refresh_row.add_child(items_lbl)
	var refresh_items_btn = _btn("⟳ Items", false, func():
		_refresh_items()
		items_lbl.text = "%d items available" % available_items.size()
	)
	refresh_row.add_child(refresh_items_btn)
	drop_c.add_child(refresh_row)

	# Column headers
	var header_hbox = HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 3)
	header_hbox.add_child(_col_lbl("Item", 0))
	header_hbox.add_child(_col_lbl("Chance", 58))
	header_hbox.add_child(_col_lbl("Min", 40))
	header_hbox.add_child(_col_lbl("Max", 40))
	drop_c.add_child(header_hbox)

	drop_rows_box = VBoxContainer.new()
	drop_rows_box.add_theme_constant_override("separation", 3)
	drop_c.add_child(drop_rows_box)

	drop_c.add_child(_btn("+ Add Drop Entry", false, _add_drop_row))

	# ── Setup Notes Card ─────────────────────────────────────
	var note_c = _make_card(vbox, "NEXT STEPS AFTER SAVING", C_GRAY)
	var note = Label.new()
	note.text = (
		"Open the saved .tres in the inspector\n"
		+ "and assign:\n\n"
		+ "  • sprite_frames\n"
		+ "  • character_collision_shape\n"
		+ "  • body_hitbox_shape\n"
		+ "  • attack_hitbox_shape\n\n"
		+ "Then duplicate enemy_template.tscn\n"
		+ "and set the EnemyData on the root node."
	)
	note.add_theme_color_override("font_color", C_DIM)
	note.add_theme_font_size_override("font_size", 10)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note_c.add_child(note)

	return scroll


# ─────────────────────────────────────────────────────────────
# DROP ROWS
# ─────────────────────────────────────────────────────────────
func _add_drop_row(preset_item: String = "", preset_chance: float = 0.9, preset_min: int = 1, preset_max: int = 1) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)

	# Item OptionButton (populated from scanned items)
	var item_opt = OptionButton.new()
	item_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if available_items.is_empty():
		item_opt.add_item("(no items found)")
	else:
		for item_name in available_items:
			item_opt.add_item(item_name)
		# Select preset
		if not preset_item.is_empty():
			for i in range(item_opt.item_count):
				if item_opt.get_item_text(i) == preset_item:
					item_opt.select(i); break

	var chance_spin = SpinBox.new()
	chance_spin.min_value = 1; chance_spin.max_value = 100
	chance_spin.value = preset_chance * 100
	chance_spin.suffix = "%"
	chance_spin.custom_minimum_size.x = 58

	var min_spin = SpinBox.new()
	min_spin.min_value = 1; min_spin.max_value = 9999
	min_spin.value = preset_min
	min_spin.custom_minimum_size.x = 46

	var max_spin = SpinBox.new()
	max_spin.min_value = 1; max_spin.max_value = 9999
	max_spin.value = preset_max
	max_spin.custom_minimum_size.x = 46

	var rem = Button.new()
	rem.text = "✕"
	rem.custom_minimum_size.x = 26
	rem.add_theme_color_override("font_color", C_ERR)

	hbox.add_child(item_opt)
	hbox.add_child(chance_spin)
	hbox.add_child(min_spin)
	hbox.add_child(max_spin)
	hbox.add_child(rem)
	drop_rows_box.add_child(hbox)

	var row = {
		"hbox":     hbox,
		"item_opt": item_opt,
		"chance":   chance_spin,
		"min":      min_spin,
		"max":      max_spin,
	}
	drop_rows.append(row)
	rem.pressed.connect(func(): drop_rows.erase(row); hbox.queue_free())


# ─────────────────────────────────────────────────────────────
# BROWSER
# ─────────────────────────────────────────────────────────────
func _refresh_browser() -> void:
	resource_tree.clear()
	var root_item = resource_tree.create_item()
	_scan_into_tree("res://resources/Enemies", root_item)
	_set_status("Browser refreshed.")


func _scan_into_tree(path: String, parent: TreeItem) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var entries: Array[String] = []
	var f = dir.get_next()
	while f != "":
		entries.append(f)
		f = dir.get_next()
	entries.sort()
	for entry in entries:
		var full = path.path_join(entry)
		if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(full)):
			if not entry.begins_with("."):
				var folder = resource_tree.create_item(parent)
				folder.set_text(0, "📁 " + entry)
				folder.set_selectable(0, false)
				_scan_into_tree(full, folder)
		elif entry.get_extension() in ["tres", "res"]:
			var res = load(full)
			if res is EnemyData:
				var ti = resource_tree.create_item(parent)
				var display = res.monster_name if not res.monster_name.is_empty() else entry.get_basename()
				ti.set_text(0, "Lv%d  %s" % [res.monster_level, display])
				ti.set_metadata(0, full)


func _on_load_selected() -> void:
	var sel = resource_tree.get_selected()
	if not sel or sel.get_metadata(0) == null:
		_set_status("Select an enemy first.", true); return
	var res = load(sel.get_metadata(0) as String)
	if not res is EnemyData:
		_set_status("Could not load resource.", true); return
	_load_from_resource(res as EnemyData)
	tabs.current_tab = 1
	_set_status("Loaded: %s" % (sel.get_metadata(0) as String).get_file())


func _load_from_resource(res: EnemyData) -> void:
	name_edit.text = res.monster_name
	level_spin.value = res.monster_level
	speed_spin.value = res.movement_speed
	# Clear existing rows
	for row in drop_rows: row.hbox.queue_free()
	drop_rows.clear()
	# Recreate rows from resource
	for drop_res in res.item_drops:
		var dr: ItemDropResource = drop_res
		_add_drop_row(dr.item_name, dr.drop_chance, dr.min_amount, dr.max_amount)
	if drop_rows.is_empty():
		_add_drop_row()


# ─────────────────────────────────────────────────────────────
# FILE OPERATIONS
# ─────────────────────────────────────────────────────────────
func _on_new_pressed() -> void:
	name_edit.text = ""
	level_spin.value = 1
	speed_spin.value = 60
	for row in drop_rows: row.hbox.queue_free()
	drop_rows.clear()
	_add_drop_row()
	tabs.current_tab = 1
	_set_status("Ready for new enemy.")


func _on_save_pressed() -> void:
	_on_save_as_pressed()


func _on_save_as_pressed() -> void:
	var n = name_edit.text.strip_edges()
	if n.is_empty():
		_set_status("Name cannot be empty.", true); return
	var safe = n.replace(" ", "_")
	file_dialog.current_path = "res://resources/Enemies/%s/ED_%s.tres" % [safe, safe]
	file_dialog.popup_centered(Vector2i(620, 420))


func _on_file_selected(path: String) -> void:
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var res = _build_resource()
	if not res: return
	var err = ResourceSaver.save(res, path)
	if err == OK:
		_set_status("Saved: " + path.get_file() + "  —  set sprite & collision in inspector.")
		_refresh_browser()
	else:
		_set_status("Save failed (err %d)" % err, true)


func _build_resource() -> EnemyData:
	var enemy = EnemyData.new()
	enemy.monster_name   = name_edit.text.strip_edges()
	enemy.monster_level  = int(level_spin.value)
	enemy.movement_speed = speed_spin.value
	enemy.item_drops = []
	for row in drop_rows:
		var opt = row.item_opt as OptionButton
		if opt.item_count == 0:
			continue
		var item_name = opt.get_item_text(opt.selected)
		if item_name.is_empty() or item_name == "(no items found)":
			continue
		var drop = ItemDropResource.new()
		drop.item_name   = item_name
		drop.drop_chance = (row.chance as SpinBox).value / 100.0
		drop.min_amount  = int((row.min as SpinBox).value)
		drop.max_amount  = int((row.max as SpinBox).value)
		drop.resource_local_to_scene = true
		enemy.item_drops.append(drop)
	return enemy


# ─────────────────────────────────────────────────────────────
# STYLE HELPERS  (duplicated from item creator for self-containment)
# ─────────────────────────────────────────────────────────────
func _make_card(parent: Control, title: String, accent: Color) -> VBoxContainer:
	var panel = PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style = StyleBoxFlat.new()
	style.bg_color = C_CARD
	style.border_color = accent.darkened(0.45)
	style.set_border_width_all(1)
	style.corner_radius_top_left    = 4; style.corner_radius_top_right    = 4
	style.corner_radius_bottom_left = 4; style.corner_radius_bottom_right = 4
	style.set_content_margin_all(0)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	_last_card_outer = panel

	var outer = VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	panel.add_child(outer)

	var hdr = PanelContainer.new()
	var hs = StyleBoxFlat.new()
	hs.bg_color = accent.darkened(0.6)
	hs.corner_radius_top_left = 3; hs.corner_radius_top_right = 3
	hs.set_content_margin_all(5)
	hdr.add_theme_stylebox_override("panel", hs)
	var hl = Label.new()
	hl.text = title
	hl.add_theme_color_override("font_color", accent)
	hl.add_theme_font_size_override("font_size", 10)
	hdr.add_child(hl)
	outer.add_child(hdr)

	var cm = MarginContainer.new()
	_margin(cm, 8, 6, 8, 8)
	var content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 5)
	cm.add_child(content)
	outer.add_child(cm)
	return content


func _row(parent: Control, label: String, widget: Control) -> Control:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 80
	lbl.add_theme_color_override("font_color", C_DIM)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	hbox.add_child(widget)
	parent.add_child(hbox)
	return widget


func _col_lbl(text: String, min_w: int) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", C_DIM)
	l.add_theme_font_size_override("font_size", 10)
	if min_w > 0:
		l.custom_minimum_size.x = min_w
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _btn(text: String, accent: bool, callable: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.pressed.connect(callable)
	if accent:
		var s = StyleBoxFlat.new()
		s.bg_color = C_RED.darkened(0.52)
		s.border_color = C_RED
		s.set_border_width_all(1)
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_color_override("font_color", C_RED)
	return b


func _style_panel(p: PanelContainer, color: Color) -> void:
	var s = StyleBoxFlat.new()
	s.bg_color = color
	s.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", s)


func _margin(m: MarginContainer, l: int, t: int, r: int, b: int) -> void:
	m.add_theme_constant_override("margin_left",   l)
	m.add_theme_constant_override("margin_top",    t)
	m.add_theme_constant_override("margin_right",  r)
	m.add_theme_constant_override("margin_bottom", b)


func _set_status(msg: String, is_error: bool = false) -> void:
	status_label.text = msg
	status_label.add_theme_color_override("font_color", C_ERR if is_error else C_DIM)


# Reference C_ERR for remove buttons
const C_ERR_LOCAL = Color(1.00, 0.35, 0.35)
