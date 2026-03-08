@tool
extends Control

# ============================================================
# ITEM CREATOR PANEL
# Creates ItemData, WeaponData, ArmorData, ConsumableData .tres
# ============================================================

const ITEM_TYPE_BASIC = 0
const ITEM_TYPE_WEAPON = 1
const ITEM_TYPE_ARMOR = 2
const ITEM_TYPE_CONSUMABLE = 3

# ── Widget refs ──────────────────────────────────────────────
var type_option: OptionButton
var name_edit: LineEdit
var rarity_option: OptionButton
var item_level_spin: SpinBox
var description_edit: TextEdit

# Weapon section
var weapon_section: VBoxContainer
var weapon_type_option: OptionButton
var attack_speed_spin: SpinBox
var attack_speed_label: Label

# Armor section
var armor_section: VBoxContainer
var armor_type_option: OptionButton

# Consumable section
var consumable_section: VBoxContainer
var effect_type_option: OptionButton

# Stat bonus section
var stat_section: VBoxContainer
var stat_rows_container: VBoxContainer

# Save
var save_button: Button
var status_label: Label
var file_dialog: FileDialog

# State
var stat_rows: Array = []  # Array of Dictionarys: {type_opt, value_spin, remove_btn, hbox}

const EFFECT_SCRIPTS = {
	"RestoreHealth": "res://scripts/Resources/ItemSystem/Effects/Effect_RestoreHealth.gd",
	"GrantExperience": "res://scripts/Resources/ItemSystem/Effects/Effect_GrantExperience.gd",
	"TownPotion": "res://scripts/Resources/ItemSystem/Effects/Effect_TownPotion.gd",
}

# ============================================================
# BUILD UI
# ============================================================
func _ready() -> void:
	name = "Item Creator"
	_build_ui()


func _build_ui() -> void:
	# Root scroll
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
	title.text = "ITEM CREATOR"
	title.add_theme_font_size_override("font_size", 14)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	root.add_child(HSeparator.new())

	# Type selector
	var type_hbox = HBoxContainer.new()
	var type_lbl = Label.new()
	type_lbl.text = "Type:"
	type_lbl.custom_minimum_size.x = 90
	type_option = OptionButton.new()
	type_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_option.add_item("Basic Item", ITEM_TYPE_BASIC)
	type_option.add_item("Weapon", ITEM_TYPE_WEAPON)
	type_option.add_item("Armor", ITEM_TYPE_ARMOR)
	type_option.add_item("Consumable", ITEM_TYPE_CONSUMABLE)
	type_option.item_selected.connect(_on_type_changed)
	type_hbox.add_child(type_lbl)
	type_hbox.add_child(type_option)
	root.add_child(type_hbox)

	root.add_child(HSeparator.new())

	# ── Basic Info ───────────────────────────────────────────
	root.add_child(_section_label("Basic Info"))

	name_edit = _add_field(root, "Name:", "")
	rarity_option = _add_enum_field(root, "Rarity:", Constants.ItemRarity)
	item_level_spin = _add_spinbox_field(root, "Item Level:", 1, 100, 1)

	var desc_lbl = Label.new()
	desc_lbl.text = "Description:"
	root.add_child(desc_lbl)
	description_edit = TextEdit.new()
	description_edit.custom_minimum_size = Vector2(0, 60)
	description_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	root.add_child(description_edit)

	# ── Weapon section ───────────────────────────────────────
	weapon_section = VBoxContainer.new()
	weapon_section.add_theme_constant_override("separation", 4)
	root.add_child(weapon_section)
	weapon_section.add_child(HSeparator.new())
	weapon_section.add_child(_section_label("Weapon Settings"))
	weapon_type_option = _add_enum_field(weapon_section, "Weapon Type:", Constants.WeaponType)
	attack_speed_spin = _add_spinbox_field(weapon_section, "Attack Speed:", 1, 10, 4)
	attack_speed_label = Label.new()
	attack_speed_label.text = "  (1=Slower  4=Normal  10=Faster)"
	attack_speed_label.add_theme_color_override("font_color", Color.GRAY)
	weapon_section.add_child(attack_speed_label)
	attack_speed_spin.value_changed.connect(func(_v): _update_speed_label())

	# ── Armor section ────────────────────────────────────────
	armor_section = VBoxContainer.new()
	armor_section.add_theme_constant_override("separation", 4)
	root.add_child(armor_section)
	armor_section.add_child(HSeparator.new())
	armor_section.add_child(_section_label("Armor Settings"))
	armor_type_option = _add_enum_field(armor_section, "Armor Slot:", Constants.ArmorType)

	# ── Consumable section ───────────────────────────────────
	consumable_section = VBoxContainer.new()
	consumable_section.add_theme_constant_override("separation", 4)
	root.add_child(consumable_section)
	consumable_section.add_child(HSeparator.new())
	consumable_section.add_child(_section_label("Consumable Settings"))
	effect_type_option = _add_effect_field(consumable_section)

	# ── Stat bonus section ───────────────────────────────────
	stat_section = VBoxContainer.new()
	stat_section.add_theme_constant_override("separation", 4)
	root.add_child(stat_section)
	stat_section.add_child(HSeparator.new())
	stat_section.add_child(_section_label("Stat Bonuses"))

	stat_rows_container = VBoxContainer.new()
	stat_rows_container.add_theme_constant_override("separation", 3)
	stat_section.add_child(stat_rows_container)

	var add_stat_btn = Button.new()
	add_stat_btn.text = "+ Add Stat Bonus"
	add_stat_btn.pressed.connect(_add_stat_row)
	stat_section.add_child(add_stat_btn)

	# ── Save ─────────────────────────────────────────────────
	root.add_child(HSeparator.new())
	save_button = Button.new()
	save_button.text = "Save Resource"
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

	# Init visibility
	_on_type_changed(ITEM_TYPE_BASIC)


# ============================================================
# UI HELPERS
# ============================================================
func _section_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color.LIGHT_BLUE)
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


func _add_enum_field(parent: Control, label: String, enum_dict: Dictionary) -> OptionButton:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 90
	var opt = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in enum_dict:
		opt.add_item(key, enum_dict[key])
	hbox.add_child(lbl)
	hbox.add_child(opt)
	parent.add_child(hbox)
	return opt


func _add_effect_field(parent: Control) -> OptionButton:
	var hbox = HBoxContainer.new()
	var lbl = Label.new()
	lbl.text = "Effect Type:"
	lbl.custom_minimum_size.x = 90
	var opt = OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for effect_name in EFFECT_SCRIPTS:
		opt.add_item(effect_name)
	hbox.add_child(lbl)
	hbox.add_child(opt)
	parent.add_child(hbox)
	return opt


# ============================================================
# TYPE VISIBILITY
# ============================================================
func _on_type_changed(index: int) -> void:
	var t = type_option.get_selected_id()
	weapon_section.visible = (t == ITEM_TYPE_WEAPON)
	armor_section.visible = (t == ITEM_TYPE_ARMOR)
	consumable_section.visible = (t == ITEM_TYPE_CONSUMABLE)
	stat_section.visible = (t == ITEM_TYPE_WEAPON or t == ITEM_TYPE_ARMOR)


func _update_speed_label() -> void:
	var speed_val = int(attack_speed_spin.value)
	var label_text: String
	match speed_val:
		1: label_text = "Slower"
		2, 3: label_text = "Slow"
		4: label_text = "Normal"
		5, 6: label_text = "Fast"
		_: label_text = "Faster"
	attack_speed_label.text = "  Speed: %s" % label_text


# ============================================================
# STAT ROW BUILDER
# ============================================================
func _add_stat_row() -> void:
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 4)

	var stat_opt = OptionButton.new()
	stat_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for key in Constants.StatType:
		stat_opt.add_item(key, Constants.StatType[key])

	var value_spin = SpinBox.new()
	value_spin.min_value = 1
	value_spin.max_value = 999
	value_spin.value = 5
	value_spin.custom_minimum_size.x = 60

	var remove_btn = Button.new()
	remove_btn.text = "X"
	remove_btn.custom_minimum_size.x = 28

	hbox.add_child(stat_opt)
	hbox.add_child(value_spin)
	hbox.add_child(remove_btn)
	stat_rows_container.add_child(hbox)

	var row = {"hbox": hbox, "stat_opt": stat_opt, "value_spin": value_spin}
	stat_rows.append(row)
	remove_btn.pressed.connect(_remove_stat_row.bind(row))


func _remove_stat_row(row: Dictionary) -> void:
	stat_rows.erase(row)
	row.hbox.queue_free()


# ============================================================
# SAVE
# ============================================================
func _on_save_pressed() -> void:
	var item_name = name_edit.text.strip_edges()
	if item_name.is_empty():
		status_label.text = "Error: Name cannot be empty."
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var t = type_option.get_selected_id()
	var suggested_path: String
	match t:
		ITEM_TYPE_WEAPON:
			suggested_path = "res://resources/Items/Weapons/%s.tres" % item_name.replace(" ", "_")
		ITEM_TYPE_ARMOR:
			suggested_path = "res://resources/Items/Armor/%s.tres" % item_name.replace(" ", "_")
		ITEM_TYPE_CONSUMABLE:
			suggested_path = "res://resources/Items/Consumables/%s.tres" % item_name.replace(" ", "_")
		_:
			suggested_path = "res://resources/Items/%s.tres" % item_name.replace(" ", "_")

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


func _build_resource() -> Resource:
	var t = type_option.get_selected_id()
	var resource: ItemData

	match t:
		ITEM_TYPE_WEAPON:
			var weapon = WeaponData.new()
			weapon.weapon_type = weapon_type_option.get_selected_id()
			weapon.weapon_attack_speed = int(attack_speed_spin.value)
			weapon.equipment_type = Constants.EquipmentType.WEAPON
			weapon.item_type = Constants.ItemType.EQUIPMENT
			_apply_stat_bonuses(weapon)
			resource = weapon

		ITEM_TYPE_ARMOR:
			var armor = ArmorData.new()
			armor.armor_type = armor_type_option.get_selected_id()
			armor.equipment_type = Constants.EquipmentType.ARMOR
			armor.item_type = Constants.ItemType.EQUIPMENT
			_apply_stat_bonuses(armor)
			resource = armor

		ITEM_TYPE_CONSUMABLE:
			var consumable = ConsumableData.new()
			consumable.item_type = Constants.ItemType.CONSUMABLE
			var effect_name = effect_type_option.get_item_text(effect_type_option.selected)
			var effect_path = EFFECT_SCRIPTS.get(effect_name, "")
			if not effect_path.is_empty() and ResourceLoader.exists(effect_path):
				consumable.effect_script = load(effect_path)
			resource = consumable

		_:
			resource = ItemData.new()
			resource.item_type = Constants.ItemType.ANY

	# Apply common fields
	resource.name = name_edit.text.strip_edges()
	resource.rarity = rarity_option.get_selected_id()
	resource.item_level = int(item_level_spin.value)
	resource.description = description_edit.text

	return resource


func _apply_stat_bonuses(equipment: EquipmentData) -> void:
	equipment.bonus_stats.clear()
	for row in stat_rows:
		var stat_type: Constants.StatType = row.stat_opt.get_selected_id()
		var value: int = int(row.value_spin.value)
		if not equipment.bonus_stats.has(stat_type):
			var sd = StatData.new()
			sd.stat_type = stat_type
			equipment.bonus_stats[stat_type] = sd
		(equipment.bonus_stats[stat_type] as StatData).flat_bonus_value += value
