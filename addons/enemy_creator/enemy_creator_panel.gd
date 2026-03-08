@tool
extends Control

# ============================================================
# ENEMY CREATOR PANEL
# Creates EnemyData .tres files with a drop table builder
# ============================================================

# ── Widget refs ──────────────────────────────────────────────
var name_edit: LineEdit
var level_spin: SpinBox
var speed_spin: SpinBox
var drop_rows_container: VBoxContainer
var save_button: Button
var status_label: Label
var file_dialog: FileDialog

# State
var drop_rows: Array = []  # Array of Dictionarys per drop row


# ============================================================
# BUILD UI
# ============================================================
func _ready() -> void:
	name = "Enemy Creator"
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
	title.text = "ENEMY CREATOR"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(HSeparator.new())

	# ── Basic Info ───────────────────────────────────────────
	root.add_child(_section_label("Basic Info"))
	name_edit = _add_field(root, "Name:", "e.g. Slime")
	level_spin = _add_spinbox_field(root, "Level:", 1, 999, 1)
	speed_spin = _add_float_spinbox_field(root, "Move Speed:", 10.0, 500.0, 60.0)

	# ── Drop Table ───────────────────────────────────────────
	root.add_child(HSeparator.new())
	root.add_child(_section_label("Drop Table"))

	# Column headers
	var header_hbox = HBoxContainer.new()
	var _h1 = _header_label("Item Name", 120)
	var _h2 = _header_label("Chance %", 70)
	var _h3 = _header_label("Min", 40)
	var _h4 = _header_label("Max", 40)
	header_hbox.add_child(_h1)
	header_hbox.add_child(_h2)
	header_hbox.add_child(_h3)
	header_hbox.add_child(_h4)
	root.add_child(header_hbox)

	drop_rows_container = VBoxContainer.new()
	drop_rows_container.add_theme_constant_override("separation", 3)
	root.add_child(drop_rows_container)

	var add_drop_btn = Button.new()
	add_drop_btn.text = "+ Add Drop Entry"
	add_drop_btn.pressed.connect(_add_drop_row)
	root.add_child(add_drop_btn)

	# ── Setup hint ───────────────────────────────────────────
	root.add_child(HSeparator.new())
	root.add_child(_section_label("After Saving"))
	var hint = Label.new()
	hint.text = (
		"Set the following in the Godot inspector\n" +
		"on the saved resource:\n\n" +
		"  - sprite_frames (SpriteFrames)\n" +
		"  - character_collision_shape\n" +
		"  - body_hitbox_shape\n" +
		"  - attack_hitbox_shape\n\n" +
		"Then create a scene inheriting\n" +
		"scenes/NPC/enemy_template.tscn\n" +
		"and assign this EnemyData resource."
	)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", Color.LIGHT_GRAY)
	root.add_child(hint)

	# ── Save ─────────────────────────────────────────────────
	root.add_child(HSeparator.new())
	save_button = Button.new()
	save_button.text = "Save Enemy Data"
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

	# Start with one default drop row
	_add_drop_row()


# ============================================================
# UI HELPERS
# ============================================================
func _section_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.LIGHT_BLUE)
	return lbl


func _header_label(text: String, min_width: int) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.custom_minimum_size.x = min_width
	lbl.add_theme_color_override("font_color", Color.GRAY)
	return lbl


func _add_field(parent: Control, label: String, placeholder: String) -> LineEdit:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 90
	var edit = LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.placeholder_text = placeholder
	hbox.add_child(lbl)
	hbox.add_child(edit)
	parent.add_child(hbox)
	return edit


func _add_spinbox_field(parent: Control, label: String, min_val: float, max_val: float, default_val: float) -> SpinBox:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 90
	var spin = SpinBox.new()
	spin.min_value = min_val
	spin.max_value = max_val
	spin.value = default_val
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(lbl)
	hbox.add_child(spin)
	parent.add_child(hbox)
	return spin


func _add_float_spinbox_field(parent: Control, label: String, min_val: float, max_val: float, default_val: float) -> SpinBox:
	var spin = _add_spinbox_field(parent, label, min_val, max_val, default_val)
	spin.step = 0.5
	return spin


# ============================================================
# DROP ROW BUILDER
# ============================================================
func _add_drop_row() -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	var item_name_edit = LineEdit.new()
	item_name_edit.placeholder_text = "Item name..."
	item_name_edit.custom_minimum_size.x = 120
	item_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var chance_spin = SpinBox.new()
	chance_spin.min_value = 1
	chance_spin.max_value = 100
	chance_spin.value = 90
	chance_spin.suffix = "%"
	chance_spin.custom_minimum_size.x = 70

	var min_spin = SpinBox.new()
	min_spin.min_value = 1
	min_spin.max_value = 9999
	min_spin.value = 1
	min_spin.custom_minimum_size.x = 50

	var max_spin = SpinBox.new()
	max_spin.min_value = 1
	max_spin.max_value = 9999
	max_spin.value = 1
	max_spin.custom_minimum_size.x = 50

	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size.x = 28

	hbox.add_child(item_name_edit)
	hbox.add_child(chance_spin)
	hbox.add_child(min_spin)
	hbox.add_child(max_spin)
	hbox.add_child(remove_btn)
	drop_rows_container.add_child(hbox)

	var row = {
		"hbox": hbox,
		"item_name": item_name_edit,
		"chance": chance_spin,
		"min": min_spin,
		"max": max_spin,
	}
	drop_rows.append(row)
	remove_btn.pressed.connect(_remove_drop_row.bind(row))


func _remove_drop_row(row: Dictionary) -> void:
	drop_rows.erase(row)
	row.hbox.queue_free()


# ============================================================
# SAVE
# ============================================================
func _on_save_pressed() -> void:
	var enemy_name = name_edit.text.strip_edges()
	if enemy_name.is_empty():
		status_label.text = "Error: Name cannot be empty."
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var safe_name = enemy_name.replace(" ", "_")
	var suggested_path = "res://resources/Enemies/%s/ED_%s.tres" % [safe_name, safe_name]
	file_dialog.current_path = suggested_path
	file_dialog.popup_centered(Vector2i(600, 400))


func _on_file_selected(path: String) -> void:
	# Ensure the directory exists
	var dir_path = path.get_base_dir()
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(dir_path)):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))

	var resource = _build_resource()
	if not resource:
		return

	var err = ResourceSaver.save(resource, path)
	if err == OK:
		status_label.text = "Saved: %s\n\nRemember to set sprite_frames and collision shapes in the inspector!" % path
		status_label.add_theme_color_override("font_color", Color.GREEN_YELLOW)
	else:
		status_label.text = "Save failed (error %d)" % err
		status_label.add_theme_color_override("font_color", Color.RED)


func _build_resource() -> EnemyData:
	var enemy = EnemyData.new()
	enemy.monster_name = name_edit.text.strip_edges()
	enemy.monster_level = int(level_spin.value)
	enemy.movement_speed = speed_spin.value

	enemy.item_drops = []
	for row in drop_rows:
		var item_name_str = (row.item_name as LineEdit).text.strip_edges()
		if item_name_str.is_empty():
			continue

		var drop = ItemDropResource.new()
		drop.item_name = item_name_str
		drop.drop_chance = (row.chance as SpinBox).value / 100.0
		drop.min_amount = int((row.min as SpinBox).value)
		drop.max_amount = int((row.max as SpinBox).value)
		drop.resource_local_to_scene = true
		enemy.item_drops.append(drop)

	return enemy
