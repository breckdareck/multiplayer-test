@tool
extends Control

# ── Theme palette ─────────────────────────────────────────────
const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BLUE   = Color(0.42, 0.68, 1.00)
const C_PURPLE = Color(0.75, 0.48, 1.00)
const C_GOLD   = Color(1.00, 0.82, 0.28)
const C_RED_D  = Color(0.90, 0.30, 0.30)   # debuff accent
const C_GREEN  = Color(0.42, 0.85, 0.52)   # buff accent
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_ERR    = Color(1.00, 0.35, 0.35)

# ── Widget refs ───────────────────────────────────────────────
var tabs: TabContainer
var resource_tree: Tree
var status_label: Label
var file_dialog: FileDialog

var name_edit: LineEdit
var is_debuff_check: CheckBox
var duration_spin: SpinBox
var stack_mode_opt: OptionButton
var max_stacks_row: HBoxContainer
var max_stacks_spin: SpinBox
var desc_edit: TextEdit
var mod_rows_box: VBoxContainer
var mod_rows: Array = []

# Dynamic header that recolors on debuff toggle
var header_card_panel: PanelContainer = null
var header_card_label: Label = null

var _last_card_outer: PanelContainer = null

# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	name = "Buff Creator"
	custom_minimum_size = Vector2(260, 0)
	_build_ui()
	_refresh_browser()


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
	status_label.text = "Create or browse existing buffs."
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
	title.text = "BUFF CREATOR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_GREEN)
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

	# ── Buff Info Card ───────────────────────────────────────
	var info_c = _make_card(vbox, "BUFF INFO", C_GREEN)
	# Store refs to recolor header when debuff toggled
	header_card_panel = _last_card_outer.get_child(0).get_child(0) as PanelContainer
	header_card_label = header_card_panel.get_child(0) as Label

	name_edit = _row(info_c, "Name", LineEdit.new()) as LineEdit
	name_edit.placeholder_text = "e.g. Power Surge"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var debuff_hbox = HBoxContainer.new()
	var debuff_lbl = Label.new()
	debuff_lbl.text = "Is Debuff"
	debuff_lbl.custom_minimum_size.x = 80
	debuff_lbl.add_theme_color_override("font_color", C_DIM)
	debuff_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	is_debuff_check = CheckBox.new()
	is_debuff_check.text = "Yes (harmful to targets)"
	is_debuff_check.toggled.connect(_on_debuff_toggled)
	debuff_hbox.add_child(debuff_lbl)
	debuff_hbox.add_child(is_debuff_check)
	info_c.add_child(debuff_hbox)

	duration_spin = _row(info_c, "Duration", SpinBox.new()) as SpinBox
	duration_spin.min_value = 0; duration_spin.max_value = 3600
	duration_spin.value = 10; duration_spin.step = 0.5
	duration_spin.suffix = "s"
	duration_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_c.add_child(_lbl("  (0 = permanent until manually removed)", C_DIM, 10))

	info_c.add_child(_lbl("Description", C_DIM, 10))
	desc_edit = TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 54)
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info_c.add_child(desc_edit)

	# ── Stack Behavior Card ──────────────────────────────────
	var stack_c = _make_card(vbox, "STACK BEHAVIOR", C_PURPLE)
	stack_mode_opt = _row(stack_c, "Mode", OptionButton.new()) as OptionButton
	stack_mode_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_mode_opt.add_item("REFRESH — reset duration on reapply",  BuffData.StackBehavior.REFRESH)
	stack_mode_opt.add_item("STACK — add a stack each application", BuffData.StackBehavior.STACK)
	stack_mode_opt.add_item("IGNORE — keep existing, ignore new",   BuffData.StackBehavior.IGNORE)
	stack_mode_opt.item_selected.connect(_on_stack_mode_changed)

	max_stacks_row = HBoxContainer.new()
	var ms_lbl = Label.new()
	ms_lbl.text = "Max Stacks"
	ms_lbl.custom_minimum_size.x = 80
	ms_lbl.add_theme_color_override("font_color", C_DIM)
	ms_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	max_stacks_spin = SpinBox.new()
	max_stacks_spin.min_value = 1; max_stacks_spin.max_value = 99; max_stacks_spin.value = 1
	max_stacks_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	max_stacks_row.add_child(ms_lbl)
	max_stacks_row.add_child(max_stacks_spin)
	max_stacks_row.visible = false
	stack_c.add_child(max_stacks_row)

	# ── Stat Modifiers Card ──────────────────────────────────
	var mod_c = _make_card(vbox, "STAT MODIFIERS", C_GOLD)

	# Column headers
	var col_hbox = HBoxContainer.new()
	col_hbox.add_theme_constant_override("separation", 3)
	col_hbox.add_child(_col_lbl("Stat", 0))
	col_hbox.add_child(_col_lbl("Value", 58))
	col_hbox.add_child(_col_lbl("Type", 72))
	mod_c.add_child(col_hbox)

	mod_rows_box = VBoxContainer.new()
	mod_rows_box.add_theme_constant_override("separation", 3)
	mod_c.add_child(mod_rows_box)
	mod_c.add_child(_btn("+ Add Stat Modifier", false, _add_mod_row.bind(-1, 5, false)))

	return scroll


# ─────────────────────────────────────────────────────────────
# SIGNAL HANDLERS
# ─────────────────────────────────────────────────────────────
func _on_debuff_toggled(pressed: bool) -> void:
	var accent = C_RED_D if pressed else C_GREEN
	if header_card_panel:
		var hs = StyleBoxFlat.new()
		hs.bg_color = accent.darkened(0.6)
		hs.corner_radius_top_left = 3; hs.corner_radius_top_right = 3
		hs.set_content_margin_all(5)
		header_card_panel.add_theme_stylebox_override("panel", hs)
	if header_card_label:
		header_card_label.text = "DEBUFF INFO" if pressed else "BUFF INFO"
		header_card_label.add_theme_color_override("font_color", accent)


func _on_stack_mode_changed(index: int) -> void:
	max_stacks_row.visible = (stack_mode_opt.get_selected_id() == BuffData.StackBehavior.STACK)


# ─────────────────────────────────────────────────────────────
# MODIFIER ROWS
# ─────────────────────────────────────────────────────────────
func _add_mod_row(preset_stat: int = -1, preset_val: int = 5, preset_pct: bool = false) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)

	var stat_opt = OptionButton.new()
	stat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.StatType:
		stat_opt.add_item(key, Constants.StatType[key])
	if preset_stat >= 0:
		stat_opt.select(stat_opt.get_item_index(preset_stat))

	var val_spin = SpinBox.new()
	val_spin.min_value = 1; val_spin.max_value = 9999; val_spin.value = preset_val
	val_spin.custom_minimum_size.x = 58

	var type_opt = OptionButton.new()
	type_opt.add_item("Flat")
	type_opt.add_item("% Bonus")
	type_opt.select(1 if preset_pct else 0)
	type_opt.custom_minimum_size.x = 72

	var rem = Button.new()
	rem.text = "✕"
	rem.custom_minimum_size.x = 26
	rem.add_theme_color_override("font_color", C_ERR)

	hbox.add_child(stat_opt)
	hbox.add_child(val_spin)
	hbox.add_child(type_opt)
	hbox.add_child(rem)
	mod_rows_box.add_child(hbox)

	var row = {"hbox": hbox, "stat": stat_opt, "val": val_spin, "type": type_opt}
	mod_rows.append(row)
	rem.pressed.connect(func(): mod_rows.erase(row); hbox.queue_free())


# ─────────────────────────────────────────────────────────────
# BROWSER
# ─────────────────────────────────────────────────────────────
func _refresh_browser() -> void:
	resource_tree.clear()
	var root_item = resource_tree.create_item()
	_scan_into_tree("res://resources/Buffs", root_item)
	_set_status("Browser refreshed.")


func _scan_into_tree(path: String, parent: TreeItem) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var entries: Array[String] = []
	var f = dir.get_next()
	while f != "":
		entries.append(f); f = dir.get_next()
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
			if res is BuffData:
				var ti = resource_tree.create_item(parent)
				var display = res.buff_name if not res.buff_name.is_empty() else entry.get_basename()
				ti.set_text(0, ("%s  (%ss)" % [display, res.duration]) if res.duration > 0 else display)
				ti.set_metadata(0, full)


func _on_load_selected() -> void:
	var sel = resource_tree.get_selected()
	if not sel or sel.get_metadata(0) == null:
		_set_status("Select a buff first.", true); return
	var res = load(sel.get_metadata(0) as String)
	if not res is BuffData:
		_set_status("Could not load resource.", true); return
	_load_from_resource(res as BuffData)
	tabs.current_tab = 1
	_set_status("Loaded: %s" % (sel.get_metadata(0) as String).get_file())


func _load_from_resource(res: BuffData) -> void:
	name_edit.text = res.buff_name
	desc_edit.text = res.description
	duration_spin.value = res.duration
	is_debuff_check.button_pressed = res.is_debuff
	_on_debuff_toggled(res.is_debuff)
	stack_mode_opt.select(stack_mode_opt.get_item_index(int(res.stack_behavior)))
	_on_stack_mode_changed(0)
	max_stacks_spin.value = res.max_stacks
	# Rebuild modifier rows
	for row in mod_rows: row.hbox.queue_free()
	mod_rows.clear()
	for stat_type in res.stat_modifiers:
		var sd: StatData = res.stat_modifiers[stat_type]
		if sd.flat_bonus_value > 0:
			_add_mod_row(int(stat_type), sd.flat_bonus_value, false)
		if sd.percent_bonus_value > 0:
			_add_mod_row(int(stat_type), int(sd.percent_bonus_value), true)


# ─────────────────────────────────────────────────────────────
# FILE OPERATIONS
# ─────────────────────────────────────────────────────────────
func _on_new_pressed() -> void:
	name_edit.text = ""
	desc_edit.text = ""
	duration_spin.value = 10
	is_debuff_check.button_pressed = false
	_on_debuff_toggled(false)
	stack_mode_opt.select(0)
	max_stacks_row.visible = false
	max_stacks_spin.value = 1
	for row in mod_rows: row.hbox.queue_free()
	mod_rows.clear()
	tabs.current_tab = 1
	_set_status("Ready for new buff.")


func _on_save_pressed() -> void:
	_on_save_as_pressed()


func _on_save_as_pressed() -> void:
	var n = name_edit.text.strip_edges()
	if n.is_empty():
		_set_status("Name cannot be empty.", true); return
	var safe = n.replace(" ", "_")
	var prefix = "DB_" if is_debuff_check.button_pressed else "B_"
	file_dialog.current_path = "res://resources/Buffs/%s%s.tres" % [prefix, safe]
	file_dialog.popup_centered(Vector2i(620, 420))


func _on_file_selected(path: String) -> void:
	var res = _build_resource()
	if not res: return
	var err = ResourceSaver.save(res, path)
	if err == OK:
		_set_status("Saved: " + path.get_file())
		_refresh_browser()
	else:
		_set_status("Save failed (err %d)" % err, true)


func _build_resource() -> BuffData:
	var buff = BuffData.new()
	buff.buff_name       = name_edit.text.strip_edges()
	buff.description     = desc_edit.text
	buff.is_debuff       = is_debuff_check.button_pressed
	buff.duration        = duration_spin.value
	buff.stack_behavior  = stack_mode_opt.get_selected_id() as BuffData.StackBehavior
	buff.max_stacks      = int(max_stacks_spin.value)
	buff.stat_modifiers  = {}
	for row in mod_rows:
		var st: Constants.StatType = (row.stat as OptionButton).get_selected_id()
		var v: int = int((row.val as SpinBox).value)
		var is_pct: bool = ((row.type as OptionButton).selected == 1)
		if not buff.stat_modifiers.has(st):
			var sd = StatData.new(); sd.stat_type = st
			buff.stat_modifiers[st] = sd
		var sd: StatData = buff.stat_modifiers[st]
		if is_pct:
			sd.percent_bonus_value += float(v)
		else:
			sd.flat_bonus_value += v
	return buff


# ─────────────────────────────────────────────────────────────
# STYLE HELPERS
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
		s.bg_color = C_GREEN.darkened(0.58)
		s.border_color = C_GREEN
		s.set_border_width_all(1)
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_color_override("font_color", C_GREEN)
	return b


func _lbl(text: String, color: Color = Color.WHITE, size: int = 11) -> Label:
	var l = Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.add_theme_font_size_override("font_size", size)
	return l


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
