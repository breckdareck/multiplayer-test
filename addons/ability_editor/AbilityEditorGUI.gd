@tool
class_name AbilityEditorGUI
extends Control

# ========================================
# MAIN ABILITY EDITOR - ALL IN ONE FILE
# ========================================

# --- ONREADY VARS ---
# File Browser
@onready var refresh_button = $Panel/MainHSplit/AbilityBrowser/RefreshButton
@onready var ability_tree = $Panel/MainHSplit/AbilityBrowser/AbilityTree

# General Settings
@onready var ability_id_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_ID/AbilityIDEdit
@onready var ability_name_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Name/AbilityNameEdit
@onready var description_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Desc/DescriptionEdit
@onready var icon_path_picker = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Icon/IconPathPicker
@onready var max_level_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_MaxLevel/MaxLevelSpinBox
@onready var ability_type_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Type/AbilityTypeOption
@onready var required_class_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Class/RequiredClassOption
@onready var required_weapon_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Weapon/RequiredWeaponOption

# Scaling Mode Toggle
@onready var use_formulas_checkbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ScalingMode/MarginContainer/Form/UseFormulasCheckbox
@onready var formula_help_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ScalingMode/MarginContainer/Form/HelpButton

# Active Behavior Panel
@onready var active_behavior_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior
@onready var active_behavior_inspector = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/ActiveBehaviorInspector

# Formula Editor Panel
@onready var formula_editor_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor
@onready var formula_tree = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HSplit/FormulaTree
@onready var formula_inspector = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HSplit/FormulaInspector
@onready var add_formula_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HeaderButtons/AddFormulaButton
@onready var formula_preset_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HeaderButtons/PresetOption

# Manual Level Editor Panel
@onready var manual_level_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings
@onready var level_list = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/LevelList
@onready var add_level_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/AddLevelButton
@onready var remove_level_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/RemoveLevelButton
@onready var level_details_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetailsPanel
@onready var level_detail_inspector = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetailsPanel/LevelDetailInspector

# Buttons & Dialogs
@onready var new_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/NewButton
@onready var save_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveButton
@onready var save_as_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveAsButton
@onready var preview_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/PreviewButton
@onready var file_dialog = $FileDialog

# --- MEMBER VARS ---
var current_ability: AbilityData
var current_scaling_data: AbilityScalingData
var is_updating_ui: bool = false
var selected_formula_key: String = ""
var current_editing_formula: AbilityScalingFormula = null

# Formula presets
var formula_presets = {
	"Linear +1/level": {"type": AbilityScalingFormula.ScalingType.FLAT, "base": 0, "per_level": 1.0},
	"Linear +5/level": {"type": AbilityScalingFormula.ScalingType.FLAT, "base": 0, "per_level": 5.0},
	"100 + 10/level": {"type": AbilityScalingFormula.ScalingType.FLAT, "base": 100, "per_level": 10.0},
	"Exponential 10%": {"type": AbilityScalingFormula.ScalingType.MULTIPLICATIVE, "base": 100, "mult": 1.1},
	"Exponential 20%": {"type": AbilityScalingFormula.ScalingType.MULTIPLICATIVE, "base": 100, "mult": 1.2},
}

# ========================================
# GODOT LIFECYCLE
# ========================================
func _ready() -> void:
	_populate_option_buttons()
	_populate_formula_presets()
	_connect_signals()
	_scan_for_abilities()
	_on_new_button_pressed()


# ========================================
# INITIALIZATION
# ========================================
func _populate_option_buttons() -> void:
	_populate_option_button(ability_type_option, Constants.AbilityType)
	_populate_option_button(required_class_option, Constants.ClassType)
	_populate_option_button(required_weapon_option, Constants.WeaponType)
	# No longer need to populate TargetType, inspector will do it


func _populate_option_button(button: OptionButton, enum_dict: Dictionary) -> void:
	button.clear()
	for key in enum_dict:
		button.add_item(key, enum_dict[key])


func _populate_formula_presets() -> void:
	formula_preset_option.clear()
	formula_preset_option.add_item("-- Select Preset --", -1)
	var idx = 0
	for preset_name in formula_presets:
		formula_preset_option.add_item(preset_name, idx)
		idx += 1


func _connect_signals() -> void:
	# File operations
	new_button.pressed.connect(_on_new_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	save_as_button.pressed.connect(_on_save_as_button_pressed)
	preview_button.pressed.connect(_on_preview_button_pressed)
	file_dialog.file_selected.connect(_on_file_selected)
	
	# Browser
	refresh_button.pressed.connect(_scan_for_abilities)
	ability_tree.item_selected.connect(_on_ability_tree_item_selected)
	
	# General info
	ability_name_edit.text_changed.connect(_on_general_info_changed)
	description_edit.text_changed.connect(_on_general_info_changed)
	icon_path_picker.resource_changed.connect(_on_general_info_changed)
	max_level_spinbox.value_changed.connect(_on_general_info_changed)
	ability_type_option.item_selected.connect(_on_ability_type_changed)
	required_class_option.item_selected.connect(_on_general_info_changed)
	required_weapon_option.item_selected.connect(_on_general_info_changed)
	
	# Scaling mode
	use_formulas_checkbox.toggled.connect(_on_scaling_mode_toggled)
	formula_help_button.pressed.connect(_show_formula_help)
	
	# Active behavior - No longer needed, inspector handles it
	
	# Formula editor
	add_formula_button.pressed.connect(_on_add_formula_pressed)
	formula_preset_option.item_selected.connect(_on_preset_selected)
	formula_tree.item_selected.connect(_on_formula_tree_selected)
	
	# Manual level editor
	add_level_button.pressed.connect(_on_add_level_pressed)
	remove_level_button.pressed.connect(_on_remove_level_pressed)
	level_list.item_selected.connect(_on_level_selected)
	
	# Manual level details - No longer needed, inspector handles it


# ========================================
# FILE BROWSER
# ========================================
func _scan_for_abilities() -> void:
	ability_tree.clear()
	var root = ability_tree.create_item()
	var ability_script = load("res://scripts/Resources/AbilitySystem/AbilityData.gd")
	
	if not ability_script:
		push_error("Could not find AbilityData.gd script")
		return
	
	var path = "res://resources/Abilities"
	_recursive_scan(path, root, ability_script)


func _recursive_scan(path: String, parent_item: TreeItem, script_to_match: Script) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	
	dir.list_dir_begin()
	var file_name = dir.get_next()
	
	while file_name != "":
		if dir.current_is_dir() and file_name != "." and file_name != "..":
			_recursive_scan(path.path_join(file_name), parent_item, script_to_match)
		elif not dir.current_is_dir() and file_name.get_extension() == "tres":
			var file_path = path.path_join(file_name)
			var res = load(file_path)
			
			if res and res.get_script() == script_to_match:
				var item = ability_tree.create_item(parent_item)
				item.set_text(0, res.ability_name if not res.ability_name.is_empty() else file_name)
				item.set_metadata(0, file_path)
		
		file_name = dir.get_next()


# ========================================
# FILE OPERATIONS
# ========================================
func _on_new_button_pressed() -> void:
	ability_tree.deselect_all()
	current_ability = AbilityData.new()
	current_ability.max_level = 10
	current_ability.use_scaling_formulas = true
	
	# Create and embed scaling data
	current_ability.scaling_data = AbilityScalingData.new()
	current_ability.scaling_data.resource_local_to_scene = true # Embed resource
	current_scaling_data = current_ability.scaling_data
	
	# Create and embed active behavior data
	current_ability.active_behavior = ActiveBehaviorData.new()
	current_ability.active_behavior.resource_local_to_scene = true # Embed resource
	
	_update_ui()


func _on_save_button_pressed() -> void:
	if current_ability.resource_path.is_empty():
		_on_save_as_button_pressed()
	else:
		_save_ability(current_ability.resource_path)


func _on_save_as_button_pressed() -> void:
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Ability Resource")
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_ability(path)
	elif file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		_load_ability(path)


func _save_ability(path: String) -> void:
	# No longer need to save scaling data separately
	ResourceSaver.save(current_ability, path)
	print("✅ Ability saved to: ", path)
	_scan_for_abilities()


func _load_ability(path: String) -> void:
	current_ability = load(path)
	if current_ability and current_ability.scaling_data:
		current_scaling_data = current_ability.scaling_data
	
	# Ensure embedded resources exist if loading older files
	if not current_ability.active_behavior:
		current_ability.active_behavior = ActiveBehaviorData.new()
		current_ability.active_behavior.resource_local_to_scene = true
	if not current_ability.scaling_data:
		current_ability.scaling_data = AbilityScalingData.new()
		current_ability.scaling_data.resource_local_to_scene = true
		current_scaling_data = current_ability.scaling_data

	_update_ui()


func _on_ability_tree_item_selected() -> void:
	var selected = ability_tree.get_selected()
	if selected:
		var path = selected.get_metadata(0)
		if path and not path.is_empty():
			_load_ability(path)


# ========================================
# UI UPDATE - MAIN
# ========================================
func _update_ui() -> void:
	if not current_ability:
		return
	
	is_updating_ui = true
	
	# General info
	ability_id_edit.text = current_ability.ability_id
	ability_name_edit.text = current_ability.ability_name
	description_edit.text = current_ability.description
	icon_path_picker.set_edited_resource(current_ability.ability_icon)
	max_level_spinbox.value = current_ability.max_level
	ability_type_option.selected = current_ability.ability_type
	
	if not current_ability.required_class.is_empty():
		required_class_option.selected = current_ability.required_class[0]
	if not current_ability.required_weapon_types.is_empty():
		required_weapon_option.selected = current_ability.required_weapon_types[0]
	
	# Scaling mode
	use_formulas_checkbox.button_pressed = current_ability.use_scaling_formulas
	_on_scaling_mode_toggled(current_ability.use_scaling_formulas)
	
	# Active behavior
	_update_active_behavior_ui()
	
	is_updating_ui = false


func _update_active_behavior_ui() -> void:
	if current_ability.ability_type == Constants.AbilityType.ACTIVE:
		active_behavior_panel.show()
		# The inspector now handles all field population
		active_behavior_inspector.edit(current_ability.active_behavior)
	else:
		active_behavior_panel.hide()
		active_behavior_inspector.edit(null)


# ========================================
# GENERAL INFO HANDLERS
# ========================================
func _on_general_info_changed(value = null) -> void:
	if is_updating_ui or not current_ability:
		return
	
	current_ability.ability_name = ability_name_edit.text
	current_ability.description = description_edit.text
	current_ability.max_level = int(max_level_spinbox.value)
	
	current_ability.ability_icon = icon_path_picker.get_edited_resource()
	
	current_ability.ability_type = ability_type_option.get_selected_id()
	
	current_ability.required_class.clear()
	current_ability.required_class.append(required_class_option.get_selected_id())
	current_ability.required_weapon_types.clear()
	current_ability.required_weapon_types.append(required_weapon_option.get_selected_id())


func _on_ability_type_changed(index: int) -> void:
	_on_general_info_changed()
	_update_active_behavior_ui()
	
	if current_ability.use_scaling_formulas:
		_update_formula_tree()


# ========================================
# ACTIVE BEHAVIOR HANDLERS
# ========================================

# This function is no longer needed.
# The EditorInspector automatically updates the resource properties.
# func _on_active_behavior_changed(value = null) -> void:


# ========================================
# SCALING MODE TOGGLE
# ========================================
func _on_scaling_mode_toggled(use_formulas: bool) -> void:
	if not current_ability:
		return
	
	current_ability.use_scaling_formulas = use_formulas
	
	if use_formulas:
		formula_editor_panel.show()
		manual_level_panel.hide()
		
		if not current_ability.scaling_data:
			current_ability.scaling_data = AbilityScalingData.new()
			current_ability.scaling_data.resource_local_to_scene = true
			current_scaling_data = current_ability.scaling_data
		
		_update_formula_tree()
	else:
		formula_editor_panel.hide()
		manual_level_panel.show()
		_update_manual_level_list()
	
	# Clear inspectors
	formula_inspector.edit(null)
	level_detail_inspector.edit(null)


# ========================================
# FORMULA EDITOR - TREE VIEW
# ========================================
func _update_formula_tree() -> void:
	formula_tree.clear()
	formula_inspector.edit(null) # Clear inspector
	if not current_ability or not current_scaling_data:
		return
	
	var root = formula_tree.create_item()
	
	# Basic Stats Category
	var basic_stats = formula_tree.create_item(root)
	basic_stats.set_text(0, "📊 Basic Stats")
	basic_stats.set_selectable(0, false)
	
	_add_formula_item(basic_stats, "Mana Cost", "mana_cost_formula", current_scaling_data.mana_cost_formula)
	_add_formula_item(basic_stats, "Cooldown", "cooldown_formula", current_scaling_data.cooldown_formula)
	_add_formula_item(basic_stats, "Damage %", "damage_percent_formula", current_scaling_data.damage_percent_formula)
	_add_formula_item(basic_stats, "Max Targets", "max_targets_formula", current_scaling_data.max_targets_formula)
	_add_formula_item(basic_stats, "Max Hits", "max_hits_formula", current_scaling_data.max_hits_formula)
	_add_formula_item(basic_stats, "Cast Time", "cast_time_formula", current_scaling_data.cast_time_formula)
	
	# Stat Bonuses (Passives only)
	if current_ability.ability_type == Constants.AbilityType.PASSIVE:
		var stat_bonuses = formula_tree.create_item(root)
		stat_bonuses.set_text(0, "💪 Stat Bonuses")
		stat_bonuses.set_selectable(0, false)
		
		for stat_formula in current_scaling_data.stat_bonus_formulas:
			if stat_formula:
				var stat_name = Constants.StatType.keys()[stat_formula.stat_type]
				_add_stat_bonus_item(stat_bonuses, stat_name, stat_formula)
	
	# Ability Modifiers
	if current_scaling_data.ability_damage_modifier_formulas.size() > 0:
		var modifiers = formula_tree.create_item(root)
		modifiers.set_text(0, "⚔️ Ability Modifiers")
		modifiers.set_selectable(0, false)
		
		for ability_id in current_scaling_data.ability_damage_modifier_formulas:
			_add_formula_item(modifiers, "Dmg Mod", "damage_mod_" + ability_id, 
							current_scaling_data.ability_damage_modifier_formulas[ability_id])
	
	# Proc Effects
	if current_scaling_data.proc_chance_formula or current_scaling_data.proc_damage_formula:
		var procs = formula_tree.create_item(root)
		procs.set_text(0, "⚡ Proc Effects")
		procs.set_selectable(0, false)
		
		_add_formula_item(procs, "Proc Chance", "proc_chance_formula", current_scaling_data.proc_chance_formula)
		_add_formula_item(procs, "Proc Damage", "proc_damage_formula", current_scaling_data.proc_damage_formula)


func _add_formula_item(parent: TreeItem, label: String, key: String, formula: AbilityScalingFormula) -> void:
	var item = formula_tree.create_item(parent)
	item.set_text(0, label)
	item.set_metadata(0, key)
	
	if formula:
		var preview = _get_formula_preview(formula)
		item.set_text(1, preview)
		item.set_custom_color(1, Color.LIGHT_GREEN)
	else:
		item.set_text(1, "Not Set")
		item.set_custom_color(1, Color.DIM_GRAY)


func _add_stat_bonus_item(parent: TreeItem, stat_name: String, stat_formula: StatBonusFormula) -> void:
	var item = formula_tree.create_item(parent)
	item.set_text(0, stat_name)
	# We can just pass the resource itself in the metadata
	item.set_metadata(0, {"type": "stat_bonus", "resource": stat_formula})
	
	var preview_parts = []
	if stat_formula.flat_bonus_formula:
		preview_parts.append("Flat: " + _get_formula_preview(stat_formula.flat_bonus_formula))
	if stat_formula.percent_bonus_formula:
		preview_parts.append("%: " + _get_formula_preview(stat_formula.percent_bonus_formula))
	
	item.set_text(1, " | ".join(preview_parts) if preview_parts.size() > 0 else "Not Set")


func _get_formula_preview(formula: AbilityScalingFormula) -> String:
	match formula.scaling_type:
		AbilityScalingFormula.ScalingType.FLAT:
			return "%.1f + (Lv × %.1f)" % [formula.base_value, formula.per_level]
		AbilityScalingFormula.ScalingType.MULTIPLICATIVE:
			return "%.1f × %.2f^Lv" % [formula.base_value, formula.multiplier]
		AbilityScalingFormula.ScalingType.STEPPED:
			return "Breakpoints: %d" % formula.step_values.size()
		AbilityScalingFormula.ScalingType.CUSTOM:
			return "Custom"
	return "?"


# ========================================
# FORMULA EDITOR - DETAIL EDITING
# ========================================
func _on_formula_tree_selected() -> void:
	var selected = formula_tree.get_selected()
	if not selected:
		formula_inspector.edit(null)
		current_editing_formula = null
		return
	
	var metadata = selected.get_metadata(0)
	
	if metadata is String:
		# It's a key for a basic formula
		selected_formula_key = metadata
		var formula = _get_formula_by_key(metadata)
		if not formula:
			formula = AbilityScalingFormula.new()
			formula.resource_local_to_scene = true # Embed it
			_assign_formula_to_key(metadata, formula)
		
		current_editing_formula = formula
		formula_inspector.edit(formula) # Tell inspector to edit this resource
		
	elif metadata is Dictionary and metadata.has("type") and metadata.type == "stat_bonus":
		# It's a StatBonusFormula resource
		selected_formula_key = ""
		current_editing_formula = null # We are editing the container, not a single formula
		formula_inspector.edit(metadata.resource)


func _get_formula_by_key(key: String) -> AbilityScalingFormula:
	match key:
		"mana_cost_formula": return current_scaling_data.mana_cost_formula
		"cooldown_formula": return current_scaling_data.cooldown_formula
		"damage_percent_formula": return current_scaling_data.damage_percent_formula
		"max_targets_formula": return current_scaling_data.max_targets_formula
		"max_hits_formula": return current_scaling_data.max_hits_formula
		"cast_time_formula": return current_scaling_data.cast_time_formula
		"proc_chance_formula": return current_scaling_data.proc_chance_formula
		"proc_damage_formula": return current_scaling_data.proc_damage_formula
	
	# Check if it's a damage modifier
	if key.begins_with("damage_mod_"):
		var ability_id = key.replace("damage_mod_", "")
		return current_scaling_data.ability_damage_modifier_formulas.get(ability_id, null)
	
	return null


func _assign_formula_to_key(key: String, formula: AbilityScalingFormula) -> void:
	match key:
		"mana_cost_formula": current_scaling_data.mana_cost_formula = formula
		"cooldown_formula": current_scaling_data.cooldown_formula = formula
		"damage_percent_formula": current_scaling_data.damage_percent_formula = formula
		"max_targets_formula": current_scaling_data.max_targets_formula = formula
		"max_hits_formula": current_scaling_data.max_hits_formula = formula
		"cast_time_formula": current_scaling_data.cast_time_formula = formula
		"proc_chance_formula": current_scaling_data.proc_chance_formula = formula
		"proc_damage_formula": current_scaling_data.proc_damage_formula = formula

#
# ALL MANUAL UI BUILDING FUNCTIONS ARE NOW REMOVED
# _build_formula_detail_ui()
# _add_flat_fields()
# _add_multiplicative_fields()
# _add_stepped_fields()
# _add_custom_fields()
# _add_formula_preview()
# _show_stat_bonus_editor()
#


# ========================================
# FORMULA EDITOR - ADD & PRESETS
# ========================================
func _on_add_formula_pressed() -> void:
	var popup = PopupMenu.new()
	popup.add_item("Stat Bonus (Passive)", 0)
	popup.add_item("Ability Damage Modifier", 1)
	popup.id_pressed.connect(func(id):
		match id:
			0: _add_stat_bonus()
			1: _add_ability_modifier()
		popup.queue_free()
	)
	add_child(popup)
	popup.position = add_formula_button.global_position + Vector2(0, add_formula_button.size.y)
	popup.popup()


func _add_stat_bonus() -> void:
	var new_stat_formula = StatBonusFormula.new()
	new_stat_formula.resource_local_to_scene = true
	new_stat_formula.stat_type = Constants.StatType.STRENGTH  # Default
	current_scaling_data.stat_bonus_formulas.append(new_stat_formula)
	_update_formula_tree()


func _add_ability_modifier() -> void:
	# For now, use a simple input for ability ID
	print("Add ability modifier - need ability ID input dialog")
	# TODO: Show input dialog to get ability ID


func _on_preset_selected(index: int) -> void:
	if index < 0 or not current_editing_formula:
		return
	
	var preset_name = formula_preset_option.get_item_text(index)
	if not formula_presets.has(preset_name):
		return
	
	var preset = formula_presets[preset_name]
	
	# Apply preset values
	current_editing_formula.scaling_type = preset.type
	current_editing_formula.base_value = preset.get("base", 0)
	
	match preset.type:
		AbilityScalingFormula.ScalingType.FLAT:
			current_editing_formula.per_level = preset.get("per_level", 1.0)
		AbilityScalingFormula.ScalingType.MULTIPLICATIVE:
			current_editing_formula.multiplier = preset.get("mult", 1.1)
	
	# Refresh the inspector to show the new values
	formula_inspector.edit(null)
	formula_inspector.edit(current_editing_formula)
	
	_update_formula_tree()
	formula_preset_option.select(0) # Reset preset dropdown


# ========================================
# MANUAL LEVEL EDITOR
# ========================================
func _update_manual_level_list() -> void:
	level_list.clear()
	if not current_ability:
		return
	
	for i in range(current_ability.level_data.size()):
		var level_data: AbilityLevelData = current_ability.level_data[i]
		level_list.add_item("Level %d" % level_data.level)


func _on_add_level_pressed() -> void:
	if not current_ability:
		return
	
	var next_level = current_ability.level_data.size() + 1
	var new_level_data = AbilityLevelData.new(next_level)
	new_level_data.resource_local_to_scene = true # Embed it
	current_ability.level_data.append(new_level_data)
	_update_manual_level_list()
	level_list.select(current_ability.level_data.size() - 1)
	_update_manual_level_details()


func _on_remove_level_pressed() -> void:
	if not current_ability:
		return
	
	var selected = level_list.get_selected_items()
	if selected.is_empty():
		return
	
	current_ability.level_data.remove_at(selected[0])
	
	# Renumber remaining levels
	for i in range(current_ability.level_data.size()):
		current_ability.level_data[i].level = i + 1
	
	_update_manual_level_list()
	level_list.deselect_all()
	_update_manual_level_details()


func _on_level_selected(index: int) -> void:
	_update_manual_level_details()


func _update_manual_level_details() -> void:
	var selected = level_list.get_selected_items()
	if selected.is_empty():
		level_details_panel.hide()
		level_detail_inspector.edit(null)
		return
	
	level_details_panel.show()
	var level_data: AbilityLevelData = current_ability.level_data[selected[0]]
	
	# Tell the inspector to edit this level data
	level_detail_inspector.edit(level_data)

	is_updating_ui = false


# This function is no longer needed.
# The EditorInspector automatically updates the resource properties.
# func _on_level_detail_changed(value = null) -> void:


# ========================================
# PREVIEW WINDOW
# ========================================
func _on_preview_button_pressed() -> void:
	if not current_ability:
		return
	
	var preview_text = "═══════════════════════════════════════\n"
	preview_text += "    ABILITY PREVIEW\n"
	preview_text += "═══════════════════════════════════════\n\n"
	preview_text += "Name: %s\n" % current_ability.ability_name
	preview_text += "Type: %s\n" % ("Active" if current_ability.ability_type == Constants.AbilityType.ACTIVE else "Passive")
	preview_text += "Max Level: %d\n" % current_ability.max_level
	preview_text += "Scaling: %s\n\n" % ("Formula-Based" if current_ability.use_scaling_formulas else "Manual")
	
	var max_preview = min(current_ability.max_level, 15)
	
	for level in range(1, max_preview + 1):
		var level_data = current_ability.get_level_stats(level)
		if level_data:
			preview_text += "─────────────────────────────────────\n"
			preview_text += "Level %d:\n" % level
			preview_text += "  Mana: %d | Cooldown: %.1fs | Cast: %.1fs\n" % [
				level_data.mana_cost,
				level_data.cooldown_time,
				level_data.cast_time
			]
			preview_text += "  Damage: %d%% | Targets: %d | Hits: %d\n" % [
				level_data.damage_percent,
				level_data.max_targets,
				level_data.max_hits
			]
			
			# Show stat bonuses for passives
			if current_ability.ability_type == Constants.AbilityType.PASSIVE and level_data.stat_bonuses.size() > 0:
				preview_text += "  Stat Bonuses:\n"
				for stat_type in level_data.stat_bonuses:
					var stat = level_data.stat_bonuses[stat_type]
					if stat.flat_bonus_value > 0 or stat.percent_bonus_value > 0:
						preview_text += "    %s: " % Constants.StatType.keys()[stat_type]
						if stat.flat_bonus_value > 0:
							preview_text += "+%d flat " % stat.flat_bonus_value
						if stat.percent_bonus_value > 0:
							preview_text += "+%.1f%% " % stat.percent_bonus_value
						preview_text += "\n"
			
			# Show proc info
			if level_data.on_hit_proc:
				preview_text += "  On Hit Proc: %.1f%% chance, %d%% damage\n" % [
					level_data.on_hit_proc.proc_chance * 100,
					level_data.on_hit_proc.damage_percent
				]
	
	if current_ability.max_level > 15:
		preview_text += "\n... (showing first 15 of %d levels)\n" % current_ability.max_level
	
	preview_text += "\n═══════════════════════════════════════\n"
	
	print(preview_text)
	
	# TODO: Show in a proper AcceptDialog window instead of console


# ========================================
# HELP DIALOG
# ========================================
func _show_formula_help() -> void:
	var help_text = """
	═══ FORMULA SYSTEM GUIDE ═══
	
	LINEAR (FLAT):
	  Formula: base + (level × per_level)
	  Example: 10 + (level × 5)
	  Result: 10, 15, 20, 25, 30...
	
	EXPONENTIAL (MULTIPLICATIVE):
	  Formula: base × (multiplier ^ level)
	  Example: 100 × (1.1 ^ level)
	  Result: 100, 110, 121, 133, 146...
	
	BREAKPOINTS (STEPPED):
	  Changes at specific levels
	  Example: {1: 100, 5: 150, 10: 200}
	  Levels 1-4: 100
	  Levels 5-9: 150
	  Levels 10+: 200
	
	CUSTOM:
	  Write your own GDScript formula
	  Variables: level, base_value
	  Example: base_value + (level * 10) + (level * level * 0.5)
	
	═══════════════════════════════
	"""
	
	print(help_text)
	# TODO: Show in AcceptDialog window
