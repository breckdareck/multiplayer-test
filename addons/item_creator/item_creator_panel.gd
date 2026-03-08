@tool
extends Control

# ── Type constants ────────────────────────────────────────────
const T_BASIC      = 0
const T_WEAPON     = 1
const T_ARMOR      = 2
const T_CONSUMABLE = 3

const EFFECT_SCRIPTS = {
	"Restore Health":   "res://scripts/Resources/ItemSystem/Effects/Effect_RestoreHealth.gd",
	"Grant Experience": "res://scripts/Resources/ItemSystem/Effects/Effect_GrantExperience.gd",
	"Town Portal":      "res://scripts/Resources/ItemSystem/Effects/Effect_TownPotion.gd",
}

# ── Theme palette ─────────────────────────────────────────────
const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BLUE   = Color(0.42, 0.68, 1.00)
const C_GREEN  = Color(0.42, 0.85, 0.52)
const C_GOLD   = Color(1.00, 0.82, 0.28)
const C_PURPLE = Color(0.75, 0.48, 1.00)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_OK     = Color(0.28, 0.90, 0.45)
const C_ERR    = Color(1.00, 0.35, 0.35)

# ── Widget refs ───────────────────────────────────────────────
var tabs: TabContainer
var resource_tree: Tree
var status_label: Label
var file_dialog: FileDialog

var type_btns: Array[Button] = []
var name_edit: LineEdit
var rarity_opt: OptionButton
var level_spin: SpinBox
var desc_edit: TextEdit

# Cards that show/hide per type (outer PanelContainers)
var weapon_outer: PanelContainer
var armor_outer:  PanelContainer
var cons_outer:   PanelContainer
var stat_outer:   PanelContainer

var weapon_type_opt: OptionButton
var attack_speed_spin: SpinBox
var attack_speed_hint: Label
var armor_type_opt: OptionButton
var effect_type_opt: OptionButton
var stat_rows_box: VBoxContainer
var stat_rows: Array = []

# State
var current_type: int = T_BASIC
var _last_card_outer: PanelContainer = null   # trick to capture outer from _make_card

# ── Lifecycle ─────────────────────────────────────────────────
func _ready() -> void:
	name = "Item Creator"
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

	# Status bar
	var bar = PanelContainer.new()
	_style_panel(bar, C_DARK)
	var bm = MarginContainer.new()
	_margin(bm, 8, 3, 8, 4)
	status_label = Label.new()
	status_label.text = "Create or browse existing items."
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
	title.text = "ITEM CREATOR"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", C_BLUE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(title)
	hbox.add_child(_btn("New",   false, _on_new_pressed))
	hbox.add_child(_btn("Save",  true,  _on_save_pressed))
	hbox.add_child(_btn("As…",   false, _on_save_as_pressed))
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

	# ── Type Card ────────────────────────────────────────────
	var type_c = _make_card(vbox, "ITEM TYPE", C_BLUE)
	var bg = ButtonGroup.new()
	var btn_row = HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 2)
	for label in ["Basic", "Weapon", "Armor", "Consumable"]:
		var b = Button.new()
		b.text = label
		b.toggle_mode = true
		b.button_group = bg
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_type_pressed.bind(type_btns.size()))
		type_btns.append(b)
		btn_row.add_child(b)
	type_btns[T_BASIC].button_pressed = true
	type_c.add_child(btn_row)

	# ── Basic Info Card ──────────────────────────────────────
	var info_c = _make_card(vbox, "BASIC INFO", C_BLUE)
	name_edit = _row(info_c, "Name", LineEdit.new()) as LineEdit
	name_edit.placeholder_text = "e.g. Iron Sword"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	rarity_opt = _row(info_c, "Rarity", OptionButton.new()) as OptionButton
	rarity_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.ItemRarity:
		rarity_opt.add_item(key, Constants.ItemRarity[key])

	level_spin = _row(info_c, "Level", SpinBox.new()) as SpinBox
	level_spin.min_value = 1; level_spin.max_value = 200; level_spin.value = 1
	level_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	info_c.add_child(_lbl("Description", C_DIM, 10))
	desc_edit = TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 54)
	desc_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	info_c.add_child(desc_edit)

	# ── Weapon Card ──────────────────────────────────────────
	var weapon_c = _make_card(vbox, "WEAPON SETTINGS", C_GREEN)
	weapon_outer = _last_card_outer
	weapon_type_opt = _row(weapon_c, "Type", OptionButton.new()) as OptionButton
	weapon_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.WeaponType:
		weapon_type_opt.add_item(key, Constants.WeaponType[key])
	attack_speed_spin = _row(weapon_c, "Atk Speed", SpinBox.new()) as SpinBox
	attack_speed_spin.min_value = 1; attack_speed_spin.max_value = 10; attack_speed_spin.value = 4
	attack_speed_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attack_speed_spin.value_changed.connect(func(_v): _update_speed_hint())
	attack_speed_hint = _lbl("Speed: Normal  (1=Slower · 4=Normal · 10=Faster)", C_DIM, 10)
	attack_speed_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	weapon_c.add_child(attack_speed_hint)

	# ── Armor Card ───────────────────────────────────────────
	var armor_c = _make_card(vbox, "ARMOR SETTINGS", C_GREEN)
	armor_outer = _last_card_outer
	armor_type_opt = _row(armor_c, "Slot", OptionButton.new()) as OptionButton
	armor_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.ArmorType:
		armor_type_opt.add_item(key, Constants.ArmorType[key])

	# ── Consumable Card ──────────────────────────────────────
	var cons_c = _make_card(vbox, "CONSUMABLE EFFECT", C_PURPLE)
	cons_outer = _last_card_outer
	effect_type_opt = _row(cons_c, "Effect", OptionButton.new()) as OptionButton
	effect_type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for effect_name in EFFECT_SCRIPTS:
		effect_type_opt.add_item(effect_name)

	# ── Stat Bonuses Card ────────────────────────────────────
	var stat_c = _make_card(vbox, "STAT BONUSES", C_GOLD)
	stat_outer = _last_card_outer
	stat_rows_box = VBoxContainer.new()
	stat_rows_box.add_theme_constant_override("separation", 3)
	stat_c.add_child(stat_rows_box)
	stat_c.add_child(_btn("+ Add Stat Bonus", false, _add_stat_row.bind(-1, 5)))

	_on_type_pressed(T_BASIC)
	return scroll


# ─────────────────────────────────────────────────────────────
# TYPE HANDLING
# ─────────────────────────────────────────────────────────────
func _on_type_pressed(t: int) -> void:
	current_type = t
	weapon_outer.visible = (t == T_WEAPON)
	armor_outer.visible  = (t == T_ARMOR)
	cons_outer.visible   = (t == T_CONSUMABLE)
	stat_outer.visible   = (t == T_WEAPON or t == T_ARMOR)


func _update_speed_hint() -> void:
	var v = int(attack_speed_spin.value)
	var s = match_speed(v)
	attack_speed_hint.text = "Speed: %s  (1=Slower · 4=Normal · 10=Faster)" % s


static func match_speed(v: int) -> String:
	match v:
		1:        return "Slower"
		2, 3:     return "Slow"
		4:        return "Normal"
		5, 6:     return "Fast"
		_:        return "Faster"


# ─────────────────────────────────────────────────────────────
# STAT ROWS
# ─────────────────────────────────────────────────────────────
func _add_stat_row(preset_stat: int = -1, preset_val: int = 5) -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 3)

	var stat_opt = OptionButton.new()
	stat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.StatType:
		stat_opt.add_item(key, Constants.StatType[key])
	if preset_stat >= 0:
		stat_opt.select(stat_opt.get_item_index(preset_stat))

	var val_spin = SpinBox.new()
	val_spin.min_value = 1; val_spin.max_value = 999; val_spin.value = preset_val
	val_spin.custom_minimum_size.x = 55

	var rem = Button.new()
	rem.text = "✕"
	rem.custom_minimum_size.x = 26
	rem.add_theme_color_override("font_color", C_ERR)

	hbox.add_child(stat_opt)
	hbox.add_child(val_spin)
	hbox.add_child(rem)
	stat_rows_box.add_child(hbox)

	var row = {"hbox": hbox, "stat": stat_opt, "val": val_spin}
	stat_rows.append(row)
	rem.pressed.connect(func(): stat_rows.erase(row); hbox.queue_free())


# ─────────────────────────────────────────────────────────────
# BROWSER
# ─────────────────────────────────────────────────────────────
func _refresh_browser() -> void:
	resource_tree.clear()
	var root_item = resource_tree.create_item()
	_scan_into_tree("res://resources/Items", root_item)
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
		if dir.current_is_dir() if false else DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(full)):
			if not entry.begins_with("."):
				var folder = resource_tree.create_item(parent)
				folder.set_text(0, "📁 " + entry)
				folder.set_selectable(0, false)
				_scan_into_tree(full, folder)
		elif entry.get_extension() in ["tres", "res"]:
			var res = load(full)
			if res is ItemData:
				var item = resource_tree.create_item(parent)
				var display = res.name if not res.name.is_empty() else entry.get_basename()
				var rarity_prefix = ""
				match int(res.rarity):
					1: rarity_prefix = "◈ "
					2: rarity_prefix = "◉ "
					3: rarity_prefix = "★ "
					4: rarity_prefix = "✦ "
				item.set_text(0, rarity_prefix + display)
				item.set_metadata(0, full)


func _on_load_selected() -> void:
	var sel = resource_tree.get_selected()
	if not sel or sel.get_metadata(0) == null:
		_set_status("Select a resource first.", true)
		return
	var res = load(sel.get_metadata(0) as String)
	if not res is ItemData:
		_set_status("Could not load resource.", true)
		return
	_load_from_resource(res as ItemData)
	tabs.current_tab = 1
	_set_status("Loaded: %s" % (sel.get_metadata(0) as String).get_file())


func _load_from_resource(res: ItemData) -> void:
	name_edit.text = res.name
	level_spin.value = res.item_level
	desc_edit.text = res.description
	for i in range(rarity_opt.item_count):
		if rarity_opt.get_item_id(i) == int(res.rarity):
			rarity_opt.select(i); break

	if res is WeaponData:
		type_btns[T_WEAPON].button_pressed = true
		_on_type_pressed(T_WEAPON)
		var w = res as WeaponData
		for i in range(weapon_type_opt.item_count):
			if weapon_type_opt.get_item_id(i) == int(w.weapon_type):
				weapon_type_opt.select(i); break
		attack_speed_spin.value = w.weapon_attack_speed
		_update_speed_hint()
		_load_stat_bonuses(w)
	elif res is ArmorData:
		type_btns[T_ARMOR].button_pressed = true
		_on_type_pressed(T_ARMOR)
		var a = res as ArmorData
		for i in range(armor_type_opt.item_count):
			if armor_type_opt.get_item_id(i) == int(a.armor_type):
				armor_type_opt.select(i); break
		_load_stat_bonuses(a)
	elif res is ConsumableData:
		type_btns[T_CONSUMABLE].button_pressed = true
		_on_type_pressed(T_CONSUMABLE)
	else:
		type_btns[T_BASIC].button_pressed = true
		_on_type_pressed(T_BASIC)


func _load_stat_bonuses(equip: EquipmentData) -> void:
	for row in stat_rows:
		row.hbox.queue_free()
	stat_rows.clear()
	for stat_type in equip.bonus_stats:
		var sd: StatData = equip.bonus_stats[stat_type]
		if sd.flat_bonus_value > 0:
			_add_stat_row(int(stat_type), sd.flat_bonus_value)


# ─────────────────────────────────────────────────────────────
# FILE OPERATIONS
# ─────────────────────────────────────────────────────────────
func _on_new_pressed() -> void:
	name_edit.text = ""
	desc_edit.text = ""
	rarity_opt.select(0)
	level_spin.value = 1
	for row in stat_rows: row.hbox.queue_free()
	stat_rows.clear()
	type_btns[T_BASIC].button_pressed = true
	_on_type_pressed(T_BASIC)
	tabs.current_tab = 1
	_set_status("Ready for new item.")


func _on_save_pressed() -> void:
	_on_save_as_pressed()


func _on_save_as_pressed() -> void:
	var n = name_edit.text.strip_edges().replace(" ", "_")
	if n.is_empty():
		_set_status("Name cannot be empty.", true); return
	var path = "res://resources/Items/"
	match current_type:
		T_WEAPON:     path += "Weapons/%s.tres" % n
		T_ARMOR:      path += "Armor/%s.tres" % n
		T_CONSUMABLE: path += "Consumables/%s.tres" % n
		_:            path += "%s.tres" % n
	file_dialog.current_path = path
	file_dialog.popup_centered(Vector2i(620, 420))


func _on_file_selected(path: String) -> void:
	var n = name_edit.text.strip_edges()
	if n.is_empty():
		_set_status("Name cannot be empty.", true); return
	var res = _build_resource()
	if not res: return
	var err = ResourceSaver.save(res, path)
	if err == OK:
		_set_status("Saved: " + path.get_file())
		_refresh_browser()
	else:
		_set_status("Save failed (err %d)" % err, true)


func _build_resource() -> Resource:
	var res: ItemData
	match current_type:
		T_WEAPON:
			var w = WeaponData.new()
			w.weapon_type = weapon_type_opt.get_selected_id()
			w.weapon_attack_speed = int(attack_speed_spin.value)
			w.equipment_type = Constants.EquipmentType.WEAPON
			w.item_type = Constants.ItemType.EQUIPMENT
			_apply_stats(w); res = w
		T_ARMOR:
			var a = ArmorData.new()
			a.armor_type = armor_type_opt.get_selected_id()
			a.equipment_type = Constants.EquipmentType.ARMOR
			a.item_type = Constants.ItemType.EQUIPMENT
			_apply_stats(a); res = a
		T_CONSUMABLE:
			var c = ConsumableData.new()
			c.item_type = Constants.ItemType.CONSUMABLE
			var ename = effect_type_opt.get_item_text(effect_type_opt.selected)
			var epath = EFFECT_SCRIPTS.get(ename, "")
			if not epath.is_empty() and ResourceLoader.exists(epath):
				c.effect_script = load(epath)
			res = c
		_:
			res = ItemData.new()
			res.item_type = Constants.ItemType.ANY
	res.name        = name_edit.text.strip_edges()
	res.rarity      = rarity_opt.get_selected_id()
	res.item_level  = int(level_spin.value)
	res.description = desc_edit.text
	return res


func _apply_stats(equip: EquipmentData) -> void:
	equip.bonus_stats.clear()
	for row in stat_rows:
		var st: Constants.StatType = (row.stat as OptionButton).get_selected_id()
		var v: int = int((row.val as SpinBox).value)
		if not equip.bonus_stats.has(st):
			var sd = StatData.new(); sd.stat_type = st
			equip.bonus_stats[st] = sd
		(equip.bonus_stats[st] as StatData).flat_bonus_value += v


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


func _btn(text: String, accent: bool, callable: Callable) -> Button:
	var b = Button.new()
	b.text = text
	b.pressed.connect(callable)
	if accent:
		var s = StyleBoxFlat.new()
		s.bg_color = C_BLUE.darkened(0.52)
		s.border_color = C_BLUE
		s.set_border_width_all(1)
		s.corner_radius_top_left    = 3; s.corner_radius_top_right    = 3
		s.corner_radius_bottom_left = 3; s.corner_radius_bottom_right = 3
		s.set_content_margin_all(4)
		b.add_theme_stylebox_override("normal", s)
		b.add_theme_color_override("font_color", C_BLUE)
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
