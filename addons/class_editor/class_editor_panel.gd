@tool
extends Control

# ── Theme palette ─────────────────────────────────────────────
const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BLUE   = Color(0.42, 0.68, 1.00)
const C_TEAL   = Color(0.30, 0.85, 0.78)   # class editor accent
const C_PURPLE = Color(0.75, 0.48, 1.00)
const C_GOLD   = Color(1.00, 0.82, 0.28)
const C_GREEN  = Color(0.42, 0.85, 0.52)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_ERR    = Color(1.00, 0.35, 0.35)
const C_OK     = Color(0.42, 0.85, 0.52)

# Stat display names in order (matching Constants.StatType)
const STAT_NAMES = [
	"Strength", "Intelligence", "Dexterity", "Luck",
	"Health", "Mana", "HP Regen", "MP Regen",
	"Defense", "Mag Defense", "Crit Chance", "Crit Damage",
	"Weapon Atk", "Magic Atk"
]
const STAT_COUNT = 14

const CLASS_NAMES = ["Swordsman", "Archer", "Mage", "Rogue", "Beginner"]

# ── Widget refs ───────────────────────────────────────────────
var tabs: TabContainer
var resource_tree: Tree
var status_label: Label
var file_dialog: FileDialog

var class_name_edit: LineEdit
var class_type_opt: OptionButton
var desc_edit: TextEdit
var primary_stat_opt: OptionButton
var secondary_stat_opt: OptionButton

# base_stats[i] and stat_bonuses[i] SpinBoxes for 14 stat types
var base_stat_spins: Array = []    # Array[SpinBox]
var stat_bonus_spins: Array = []   # Array[SpinBox]

var _last_card_outer: PanelContainer = null
var _current_path: String = ""


# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	name = "Class Editor"
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

	# ── Status bar ─────────────────────────────────────────
	var bar = PanelContainer.new()
	_style_panel(bar, C_DARK)
	var bm = MarginContainer.new()
	_margin(bm, 8, 3, 8, 4)
	status_label = Label.new()
	status_label.text = "Create or browse existing classes."
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
	title.text = "CLASS EDITOR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_TEAL)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(title)
	hbox.add_child(_btn("New",  false, _on_new_pressed))
	hbox.add_child(_btn("Save", true,  _on_save_pressed))
	hbox.add_child(_btn("As…",  false, _on_save_as_pressed))
	return panel


# ── Browse tab ────────────────────────────────────────────────
func _build_browse_tab() -> Control:
	var vbox = VBoxContainer.new()

	var refresh_btn = _btn("↻  Refresh", false, _refresh_browser)
	var rm = MarginContainer.new()
	_margin(rm, 6, 4, 6, 4)
	rm.add_child(refresh_btn)
	vbox.add_child(rm)

	resource_tree = Tree.new()
	resource_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	resource_tree.hide_root = true
	resource_tree.item_activated.connect(_on_tree_item_activated)
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_border_width_all(1)
	sb.border_color = Color(C_TEAL, 0.25)
	sb.set_corner_radius_all(4)
	resource_tree.add_theme_stylebox_override("panel", sb)
	vbox.add_child(resource_tree)

	var hint = Label.new()
	hint.text = "Double-click to load for editing."
	hint.add_theme_color_override("font_color", C_DIM)
	hint.add_theme_font_size_override("font_size", 10)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hm = MarginContainer.new()
	_margin(hm, 6, 4, 6, 6)
	hm.add_child(hint)
	vbox.add_child(hm)

	return vbox


func _refresh_browser() -> void:
	if not is_instance_valid(resource_tree):
		return
	resource_tree.clear()
	var root_item = resource_tree.create_item()
	_scan_browser("res://resources/Player/Classes/", root_item)


func _scan_browser(path: String, parent_item: TreeItem) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full = path + fname
			if dir.current_is_dir():
				var folder = resource_tree.create_item(parent_item)
				folder.set_text(0, "📁 " + fname)
				folder.set_selectable(0, false)
				_scan_browser(full + "/", folder)
			elif fname.ends_with(".tres") or fname.ends_with(".res"):
				var res = load(full)
				if res is ClassData:
					var item = resource_tree.create_item(parent_item)
					var label = res._class_name if res._class_name != "" else fname
					item.set_text(0, "⚔ " + label)
					item.set_metadata(0, full)
		fname = dir.get_next()


func _on_tree_item_activated() -> void:
	var sel = resource_tree.get_selected()
	if sel and sel.get_metadata(0) != null:
		var res = load(sel.get_metadata(0))
		if res is ClassData:
			_load_from_resource(res, sel.get_metadata(0))
			tabs.current_tab = 1


# ── Edit tab ─────────────────────────────────────────────────
func _build_edit_tab() -> Control:
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 6)
	var vm = MarginContainer.new()
	_margin(vm, 6, 6, 6, 6)
	vm.add_child(vbox)
	scroll.add_child(vm)

	# ── CLASS INFO card (teal) ─────────────────────────────
	var info_c = _make_card(vbox, "CLASS INFO", C_TEAL)

	class_name_edit = LineEdit.new()
	class_name_edit.placeholder_text = "e.g. Swordsman"
	_row(info_c, "Name", class_name_edit)

	class_type_opt = OptionButton.new()
	for cn in CLASS_NAMES:
		class_type_opt.add_item(cn)
	_row(info_c, "Class Type", class_type_opt)

	primary_stat_opt = OptionButton.new()
	secondary_stat_opt = OptionButton.new()
	for sn in STAT_NAMES:
		primary_stat_opt.add_item(sn)
		secondary_stat_opt.add_item(sn)
	_row(info_c, "Primary Stat", primary_stat_opt)
	_row(info_c, "Secondary Stat", secondary_stat_opt)

	var desc_lbl = Label.new()
	desc_lbl.text = "Description"
	desc_lbl.add_theme_color_override("font_color", C_DIM)
	desc_lbl.add_theme_font_size_override("font_size", 10)
	info_c.add_child(desc_lbl)
	desc_edit = TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 54)
	desc_edit.placeholder_text = "Class description…"
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info_c.add_child(desc_edit)

	# ── BASE STATS card (blue) ─────────────────────────────
	var stats_c = _make_card(vbox, "BASE STATS", C_BLUE)

	var stats_hint = Label.new()
	stats_hint.text = "Starting stat values for this class."
	stats_hint.add_theme_color_override("font_color", C_DIM)
	stats_hint.add_theme_font_size_override("font_size", 10)
	stats_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stats_c.add_child(stats_hint)

	base_stat_spins.clear()
	for i in STAT_COUNT:
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 9999
		spin.value = 4 if i < 4 else 0  # first 4 default to 4 (STR/INT/DEX/LUCK)
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row(stats_c, STAT_NAMES[i], spin)
		base_stat_spins.append(spin)

	# ── STAT BONUSES card (gold) ───────────────────────────
	var bonus_c = _make_card(vbox, "STAT BONUSES PER LEVEL", C_GOLD)

	var bonus_hint = Label.new()
	bonus_hint.text = "Added to stats each time the player levels up."
	bonus_hint.add_theme_color_override("font_color", C_DIM)
	bonus_hint.add_theme_font_size_override("font_size", 10)
	bonus_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bonus_c.add_child(bonus_hint)

	stat_bonus_spins.clear()
	for i in STAT_COUNT:
		var spin = SpinBox.new()
		spin.min_value = 0
		spin.max_value = 999
		spin.value = 0
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_row(bonus_c, STAT_NAMES[i], spin)
		stat_bonus_spins.append(spin)

	# ── NOTES card (dim) ──────────────────────────────────
	var notes_c = _make_card(vbox, "NOTES", C_DIM)
	var notes_lbl = Label.new()
	notes_lbl.text = (
		"After saving, assign SpriteFrames per level and\n" +
		"link Ability resources through the Godot inspector.\n" +
		"Register new classes in ResourceManager."
	)
	notes_lbl.add_theme_color_override("font_color", C_DIM)
	notes_lbl.add_theme_font_size_override("font_size", 10)
	notes_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notes_c.add_child(notes_lbl)

	# ── Save button ────────────────────────────────────────
	var save_btn = _btn("  Save Class  ", true, _on_save_pressed)
	var sbm = MarginContainer.new()
	_margin(sbm, 0, 4, 0, 2)
	sbm.add_child(save_btn)
	vbox.add_child(sbm)

	return scroll


# ─────────────────────────────────────────────────────────────
# LOAD / SAVE
# ─────────────────────────────────────────────────────────────
func _load_from_resource(res: ClassData, path: String = "") -> void:
	_current_path = path
	class_name_edit.text = res._class_name
	class_type_opt.selected = int(res.class_type)
	primary_stat_opt.selected = int(res.primary_stat)
	secondary_stat_opt.selected = int(res.secondary_stat)
	desc_edit.text = res.description

	for i in STAT_COUNT:
		var stat_type = i as Constants.StatType
		base_stat_spins[i].value = res.base_stats.get(stat_type, 0)
		stat_bonus_spins[i].value = res.stat_bonuses.get(stat_type, 0)

	_set_status("Loaded: " + res._class_name)


func _build_resource() -> ClassData:
	var res = ClassData.new()
	res._class_name = class_name_edit.text.strip_edges()
	res.class_type = class_type_opt.selected as Constants.ClassType
	res.primary_stat = primary_stat_opt.selected as Constants.StatType
	res.secondary_stat = secondary_stat_opt.selected as Constants.StatType
	res.description = desc_edit.text.strip_edges()

	res.base_stats = {}
	res.stat_bonuses = {}
	for i in STAT_COUNT:
		var stat_type = i as Constants.StatType
		var base_val = int(base_stat_spins[i].value)
		var bonus_val = int(stat_bonus_spins[i].value)
		if base_val != 0:
			res.base_stats[stat_type] = base_val
		if bonus_val != 0:
			res.stat_bonuses[stat_type] = bonus_val

	return res


func _on_new_pressed() -> void:
	_current_path = ""
	class_name_edit.text = ""
	class_type_opt.selected = 0
	primary_stat_opt.selected = 0
	secondary_stat_opt.selected = 0
	desc_edit.text = ""
	for i in STAT_COUNT:
		base_stat_spins[i].value = 4 if i < 4 else 0
		stat_bonus_spins[i].value = 0
	tabs.current_tab = 1
	_set_status("New class — fill in the fields and save.")


func _on_save_pressed() -> void:
	if _current_path == "":
		_on_save_as_pressed()
		return
	_do_save(_current_path)


func _on_save_as_pressed() -> void:
	var cname = class_name_edit.text.strip_edges()
	if cname == "":
		cname = "NewClass"
	var dir = "res://resources/Player/Classes/"
	file_dialog.current_dir = dir
	file_dialog.current_file = cname + ".tres"
	file_dialog.popup_centered(Vector2i(700, 500))


func _on_file_selected(path: String) -> void:
	_do_save(path)


func _do_save(path: String) -> void:
	var cname = class_name_edit.text.strip_edges()
	if cname == "":
		_set_status("Error: Class name cannot be empty.", true)
		return

	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var res = _build_resource()
	var err = ResourceSaver.save(res, path)
	if err == OK:
		_current_path = path
		_set_status("Saved → " + path.get_file())
		_refresh_browser()
	else:
		_set_status("Save failed (error %d)" % err, true)


# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────
func _make_card(parent: Control, title: String, accent: Color) -> VBoxContainer:
	var outer = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_border_width_all(1)
	sb.border_color = Color(accent, 0.35)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(0)
	outer.add_theme_stylebox_override("panel", sb)
	outer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(outer)
	_last_card_outer = outer

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	outer.add_child(col)

	# Header bar
	var header = PanelContainer.new()
	var hsb = StyleBoxFlat.new()
	hsb.bg_color = Color(accent, 0.18)
	hsb.set_border_width_all(0)
	hsb.set_corner_radius_all(0)
	hsb.corner_radius_top_left = 5
	hsb.corner_radius_top_right = 5
	hsb.set_content_margin_all(0)
	header.add_theme_stylebox_override("panel", hsb)
	col.add_child(header)

	var hm = MarginContainer.new()
	_margin(hm, 8, 4, 8, 4)
	header.add_child(hm)

	var hlbl = Label.new()
	hlbl.text = title
	hlbl.add_theme_font_size_override("font_size", 10)
	hlbl.add_theme_color_override("font_color", accent)
	hm.add_child(hlbl)

	# Content area
	var content_margin = MarginContainer.new()
	_margin(content_margin, 10, 8, 10, 10)
	col.add_child(content_margin)

	var content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	content_margin.add_child(content)
	return content


func _row(parent: Control, label: String, widget: Control) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	parent.add_child(hbox)
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 80
	lbl.add_theme_color_override("font_color", C_DIM)
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(lbl)
	widget.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(widget)


func _btn(text: String, accent: bool, callable: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.pressed.connect(callable)
	b.add_theme_font_size_override("font_size", 10)
	if accent:
		var sb = StyleBoxFlat.new()
		sb.bg_color = Color(C_TEAL, 0.15)
		sb.set_border_width_all(1)
		sb.border_color = Color(C_TEAL, 0.70)
		sb.set_corner_radius_all(3)
		sb.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_color_override("font_color", C_TEAL)
	return b


func _style_panel(p: PanelContainer, color: Color) -> void:
	var sb = StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_border_width_all(0)
	sb.set_content_margin_all(0)
	p.add_theme_stylebox_override("panel", sb)


func _margin(m: MarginContainer, l: int, t: int, r: int, b: int) -> void:
	m.add_theme_constant_override("margin_left",   l)
	m.add_theme_constant_override("margin_top",    t)
	m.add_theme_constant_override("margin_right",  r)
	m.add_theme_constant_override("margin_bottom", b)


func _set_status(msg: String, is_err: bool = false) -> void:
	if is_instance_valid(status_label):
		status_label.text = msg
		status_label.add_theme_color_override(
			"font_color", C_ERR if is_err else C_DIM
		)
