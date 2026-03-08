@tool
extends Control

# ============================================================
# BUFF / DEBUFF CREATOR PANEL
# Creates BuffData .tres files with a stat modifier builder
# ============================================================

# ── Widget refs ──────────────────────────────────────────────
var name_edit: LineEdit
var is_debuff_check: CheckBox
var duration_spin: SpinBox
var stack_mode_option: OptionButton
var max_stacks_spin: SpinBox
var description_edit: TextEdit
var modifier_rows_container: VBoxContainer
var save_button: Button
var status_label: Label
var file_dialog: FileDialog

# State
var modifier_rows: Array = []  # Array of Dictionarys per row


# ============================================================
# BUILD UI
# ============================================================
func _ready() -> void:
	name = "Buff Creator"
	_build_ui()


func _build_ui() -> void:
	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var root = VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 6)
	scroll.add_child(root)

	# Title
	var title = Label.new()
	title.text = "BUFF / DEBUFF CREATOR"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(HSeparator.new())

	# ── Basic Fields ─────────────────────────────────────────
	root.add_child(_section_label("Basic Info"))
	name_edit = _add_field(root, "Name:")

	# Is Debuff checkbox
	var debuff_hbox = HBoxContainer.new()
	var debuff_lbl = Label.new()
	debuff_lbl.text = "Is Debuff:"
	debuff_lbl.custom_minimum_size.x = 90
	is_debuff_check = CheckBox.new()
	is_debuff_check.text = "Yes (harmful)"
	is_debuff_check.toggled.connect(_on_debuff_toggled)
	debuff_hbox.add_child(debuff_lbl)
	debuff_hbox.add_child(is_debuff_check)
	root.add_child(debuff_hbox)

	# Duration
	duration_spin = _add_spinbox(root, "Duration:", 0.0, 3600.0, 10.0, 0.5)
	var dur_hint = Label.new()
	dur_hint.text = "  (0 = permanent until removed)"
	dur_hint.add_theme_color_override("font_color", Color.GRAY)
	root.add_child(dur_hint)

	# Stack behavior
	var stack_hbox = HBoxContainer.new()
	var stack_lbl = Label.new()
	stack_lbl.text = "Stack Mode:"
	stack_lbl.custom_minimum_size.x = 90
	stack_mode_option = OptionButton.new()
	stack_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stack_mode_option.add_item("REFRESH — reset duration on reapply", BuffData.StackBehavior.REFRESH)
	stack_mode_option.add_item("STACK — add a stack each time", BuffData.StackBehavior.STACK)
	stack_mode_option.add_item("IGNORE — keep existing, discard new", BuffData.StackBehavior.IGNORE)
	stack_mode_option.item_selected.connect(_on_stack_mode_changed)
	stack_hbox.add_child(stack_lbl)
	stack_hbox.add_child(stack_mode_option)
	root.add_child(stack_hbox)

	max_stacks_spin = _add_spinbox(root, "Max Stacks:", 1, 99, 1, 1)
	max_stacks_spin.get_parent().visible = false  # hidden until STACK mode selected

	# Description
	var desc_lbl = Label.new()
	desc_lbl.text = "Description:"
	root.add_child(desc_lbl)
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size = Vector2(0, 60)
	description_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(description_edit)

	# ── Stat Modifiers ───────────────────────────────────────
	root.add_child(HSeparator.new())
	root.add_child(_section_label("Stat Modifiers"))

	# Column headers
	var header = HBoxContainer.new()
	var _h1 = _header_lbl("Stat", 110)
	var _h2 = _header_lbl("Value", 70)
	var _h3 = _header_lbl("Type", 80)
	header.add_child(_h1)
	header.add_child(_h2)
	header.add_child(_h3)
	root.add_child(header)

	modifier_rows_container = VBoxContainer.new()
	modifier_rows_container.add_theme_constant_override("separation", 3)
	root.add_child(modifier_rows_container)

	var add_mod_btn = Button.new()
	add_mod_btn.text = "+ Add Stat Modifier"
	add_mod_btn.pressed.connect(_add_modifier_row)
	root.add_child(add_mod_btn)

	# ── Save ─────────────────────────────────────────────────
	root.add_child(HSeparator.new())
	save_button = Button.new()
	save_button.text = "Save Buff / Debuff"
	save_button.pressed.connect(_on_save_pressed)
	root.add_child(save_button)

	status_label = Label.new()
	status_label.text = ""
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	root.add_child(status_label)

	# File dialog
	file_dialog = FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.add_filter("*.tres", "Godot Resource")
	file_dialog.file_selected.connect(_on_file_selected)
	add_child(file_dialog)


# ============================================================
# UI HELPERS
# ============================================================
func _section_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	return lbl


func _header_lbl(text: String, min_width: int) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = min_width
	lbl.add_theme_color_override("font_color", Color.GRAY)
	return lbl


func _add_field(parent: Control, label: String) -> LineEdit:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 90
	var edit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	hbox.add_child(edit)
	parent.add_child(hbox)
	return edit


func _add_spinbox(parent: Control, label: String, min_val: float, max_val: float, default_val: float, step: float = 1.0) -> SpinBox:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 90
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.step = step
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	hbox.add_child(spin)
	parent.add_child(hbox)
	return spin


# ============================================================
# SIGNAL HANDLERS
# ============================================================
func _on_debuff_toggled(_pressed: bool) -> void:
	# Visual feedback — tint the title area red/green
	pass


func _on_stack_mode_changed(index: int) -> void:
	# Show max_stacks only when STACK mode is selected
	var is_stack = (stack_mode_option.get_selected_id() == BuffData.StackBehavior.STACK)
	max_stacks_spin.get_parent().visible = is_stack


# ============================================================
# MODIFIER ROW BUILDER
# ============================================================
func _add_modifier_row() -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	var stat_opt = OptionButton.new()
	stat_opt.custom_minimum_size.x = 110
	stat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.StatType:
		stat_opt.add_item(key, Constants.StatType[key])

	var value_spin = SpinBox.new()
	value_spin.min_value = 1
	value_spin.max_value = 9999
	value_spin.value = 5
	value_spin.custom_minimum_size.x = 70

	var type_opt = OptionButton.new()
	type_opt.custom_minimum_size.x = 80
	type_opt.add_item("Flat")
	type_opt.add_item("Percent %")

	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size.x = 28

	hbox.add_child(stat_opt)
	hbox.add_child(value_spin)
	hbox.add_child(type_opt)
	hbox.add_child(remove_btn)
	modifier_rows_container.add_child(hbox)

	var row = {
		"hbox": hbox,
		"stat_opt": stat_opt,
		"value_spin": value_spin,
		"type_opt": type_opt,
	}
	modifier_rows.append(row)
	remove_btn.pressed.connect(_remove_modifier_row.bind(row))


func _remove_modifier_row(row: Dictionary) -> void:
	modifier_rows.erase(row)
	row.hbox.queue_free()


# ============================================================
# SAVE
# ============================================================
func _on_save_pressed() -> void:
	var buff_name = name_edit.text.strip_edges()
	if buff_name.is_empty():
		status_label.text = "Error: Name cannot be empty."
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var safe_name = buff_name.replace(" ", "_")
	var prefix = "DB_" if is_debuff_check.button_pressed else "B_"
	var suggested_path = "res://resources/Buffs/%s%s.tres" % [prefix, safe_name]
	file_dialog.current_path = suggested_path
	file_dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	var resource = _build_resource()
	if not resource:
		return

	var err = ResourceSaver.save(resource, path)
	if err == OK:
		status_label.text = "Saved: %s" % path
		status_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	else:
		status_label.text = "Save failed (error %d)" % err
		status_label.add_theme_color_override("font_color", Color.RED)


func _build_resource() -> BuffData:
	var buff = BuffData.new()
	buff.buff_name = name_edit.text.strip_edges()
	buff.description = description_edit.text
	buff.is_debuff = is_debuff_check.button_pressed
	buff.duration = duration_spin.value
	buff.stack_behavior = stack_mode_option.get_selected_id() as BuffData.StackBehavior
	buff.max_stacks = int(max_stacks_spin.value)

	buff.stat_modifiers = {}
	for row in modifier_rows:
		var stat_type: Constants.StatType = (row.stat_opt as OptionButton).get_selected_id()
		var value: int = int((row.value_spin as SpinBox).value)
		var is_percent: bool = ((row.type_opt as OptionButton).selected == 1)

		if not buff.stat_modifiers.has(stat_type):
			var sd = StatData.new()
			sd.stat_type = stat_type
			buff.stat_modifiers[stat_type] = sd

		var sd: StatData = buff.stat_modifiers[stat_type]
		if is_percent:
			sd.percent_bonus_value += float(value)
		else:
			sd.flat_bonus_value += value

	return buff
