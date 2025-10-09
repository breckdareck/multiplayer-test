# AbilityEditorGUI.gd
@tool
class_name AbilityEditorGUI
extends Control

# --- ONREADY VARS ---
# File Browser
@onready var refresh_button = $Panel/MainHSplit/AbilityBrowser/RefreshButton
@onready var ability_tree = $Panel/MainHSplit/AbilityBrowser/AbilityTree

# General Ability Info
@onready var ability_name_edit = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_Name/AbilityNameEdit
@onready var description_edit = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_Desc/DescriptionEdit
@onready var max_level_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_MaxLevel/MaxLevelSpinBox
@onready var ability_type_option = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_Type/AbilityTypeOption
@onready var required_class_option = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_Class/RequiredClassOption
@onready var required_weapon_option = $Panel/MainHSplit/EditorPanel/HSplitContainer/GeneralSettings/MarginContainer/Form/HBox_Weapon/RequiredWeaponOption

# Level Info
@onready var level_list = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/VBoxContainer/LevelList
@onready var level_details_panel = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails
@onready var level_label = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/LevelLabel
@onready var mana_cost_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/ManaCost/ManaCostSpinBox
@onready var cooldown_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/Cooldown/CooldownSpinBox
@onready var damage_percent_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/DamagePercent/DamagePercentSpinBox
@onready var fixed_damage_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/FixedDamage/FixedDamageSpinBox
@onready var max_targets_spinbox = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/MaxTargets/MaxTargetsSpinBox

# Buttons & Dialogs
@onready var new_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/NewButton
@onready var load_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/LoadButton
@onready var save_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveButton
@onready var save_as_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveAsButton
@onready var add_level_button = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/AddLevelButton
@onready var remove_level_button = $Panel/MainHSplit/EditorPanel/HSplitContainer/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/RemoveLevelButton
@onready var file_dialog = $FileDialog

# --- MEMBER VARS ---
var current_ability: AbilityData
var is_updating_ui: bool = false

# --- GODOT METHODS ---
func _ready() -> void:
	# Populate dropdowns
	_populate_option_button(ability_type_option, Constants.AbilityType)
	_populate_option_button(required_class_option, Constants.ClassType)
	_populate_option_button(required_weapon_option, Constants.WeaponType)

	# Connect signals
	_connect_signals()

	# Scan project for abilities
	_scan_for_abilities()

	# Start with a new, empty ability
	_on_new_button_pressed()


# --- CONNECTIONS ---
func _connect_signals() -> void:
	# File browser
	refresh_button.pressed.connect(_scan_for_abilities)
	ability_tree.item_selected.connect(_on_ability_tree_item_selected)
	
	# File buttons
	new_button.pressed.connect(_on_new_button_pressed)
	load_button.pressed.connect(_on_load_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	save_as_button.pressed.connect(_on_save_as_button_pressed)
	file_dialog.file_selected.connect(_on_file_selected)

	# General info fields
	ability_name_edit.text_changed.connect(_on_general_info_changed)
	description_edit.text_changed.connect(_on_general_info_changed)
	max_level_spinbox.value_changed.connect(_on_general_info_changed)
	ability_type_option.item_selected.connect(_on_general_info_changed)
	required_class_option.item_selected.connect(_on_general_info_changed)
	required_weapon_option.item_selected.connect(_on_general_info_changed)

	# Level buttons and list
	add_level_button.pressed.connect(_on_add_level_pressed)
	remove_level_button.pressed.connect(_on_remove_level_pressed)
	level_list.item_selected.connect(_on_level_selected)
	
	# Level detail fields
	mana_cost_spinbox.value_changed.connect(_on_level_detail_changed)
	cooldown_spinbox.value_changed.connect(_on_level_detail_changed)
	damage_percent_spinbox.value_changed.connect(_on_level_detail_changed)
	fixed_damage_spinbox.value_changed.connect(_on_level_detail_changed)
	max_targets_spinbox.value_changed.connect(_on_level_detail_changed)

# --- CUSTOM METHODS ---
func _scan_for_abilities() -> void:
	ability_tree.clear()
	var root = ability_tree.create_item()
	var ability_script = load("res://scripts/Resources/AbilitySystem/AbilityData.gd") # Path to your AbilityData script
	if not ability_script:
		print_rich("[color=red]Error:[/color] Could not find AbilityData.gd script.")
		return

	var filesystem = EditorInterface.get_resource_filesystem()
	_recursive_scan(filesystem.get_filesystem_path("res://resources/Abilities").get_path(), root, ability_script)


func _recursive_scan(path: String, parent_item: TreeItem, script_to_match: Script) -> void:
	var dir = DirAccess.open(path)
	print(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		print(file_name)
		while file_name != "":
			if dir.current_is_dir() and file_name != "." and file_name != "..":
				# Scan subdirectories
				_recursive_scan(path.path_join(file_name), parent_item, script_to_match)
			elif not dir.current_is_dir() and file_name.get_extension() == "tres":
				# FIX: The check for resource_type is removed as it's deprecated.
				# We now load the resource directly to check its script.
				var file_path = path.path_join(file_name)
				var res = load(file_path)
				
				# Check if the loaded resource has the correct script attached
				if res and res.get_script() == script_to_match:
					var item = ability_tree.create_item(parent_item)
					item.set_text(0, res.ability_name if not res.ability_name.is_empty() else file_path.get_file())
					item.set_metadata(0, file_path)

			file_name = dir.get_next()

func _load_ability_from_path(path: String) -> void:
	var loaded_resource = load(path)
	if loaded_resource is AbilityData:
		current_ability = loaded_resource
		_update_ui()
	else:
		print_rich("[color=red]Error:[/color] Selected file is not an AbilityData resource.")

# --- UI POPULATION & UPDATING ---
func _populate_option_button(button: OptionButton, enum_dict: Dictionary) -> void:
	button.clear()
	for key in enum_dict:
		button.add_item(key, enum_dict[key])

func _update_ui() -> void:
	if current_ability == null: return
	is_updating_ui = true

	# Update general info
	ability_name_edit.text = current_ability.ability_name
	description_edit.text = current_ability.description
	max_level_spinbox.value = current_ability.max_level
	ability_type_option.selected = current_ability.ability_type
	if !current_ability.required_class.is_empty():
		required_class_option.selected = current_ability.required_class[0]
	if !current_ability.required_weapon_types.is_empty():
		required_weapon_option.selected = current_ability.required_weapon_types[0]

	# Update level list and details
	_update_level_list()
	_update_level_details()
	
	is_updating_ui = false

func _update_level_list() -> void:
	level_list.clear()
	if current_ability == null: return
	
	for i in range(current_ability.level_data.size()):
		var level_data: AbilityLevelData = current_ability.level_data[i]
		level_list.add_item("Level %d" % level_data.level)

func _update_level_details() -> void:
	var selected_indices = level_list.get_selected_items()
	if selected_indices.is_empty():
		level_details_panel.hide()
		return
	
	level_details_panel.show()
	var selected_idx = selected_indices[0]
	var level_data: AbilityLevelData = current_ability.level_data[selected_idx]

	is_updating_ui = true
	level_label.text = "Editing Level: %d" % level_data.level
	mana_cost_spinbox.value = level_data.mana_cost
	cooldown_spinbox.value = level_data.cooldown_time
	damage_percent_spinbox.value = level_data.damage_percent
	fixed_damage_spinbox.value = level_data.fixed_damage
	max_targets_spinbox.value = level_data.max_targets
	is_updating_ui = false

# --- SIGNAL HANDLERS ---
func _on_ability_tree_item_selected() -> void:
	var selected_item = ability_tree.get_selected()
	if selected_item:
		var path = selected_item.get_metadata(0)
		if !path.is_empty():
			_load_ability_from_path(path)

func _on_new_button_pressed() -> void:
	ability_tree.deselect_all()
	current_ability = AbilityData.new()
	current_ability.max_level = 1
	_update_ui()

func _on_load_button_pressed() -> void:
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Ability Resource")
	file_dialog.popup_centered()

func _on_save_button_pressed() -> void:
	if current_ability.resource_path.is_empty():
		_on_save_as_button_pressed()
	else:
		ResourceSaver.save(current_ability, current_ability.resource_path)
		print("Ability saved to: ", current_ability.resource_path)
		_scan_for_abilities() # Refresh list to show new name

func _on_save_as_button_pressed() -> void:
	file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", "Ability Resource")
	file_dialog.popup_centered()

func _on_file_selected(path: String) -> void:
	if file_dialog.file_mode == EditorFileDialog.FILE_MODE_OPEN_FILE:
		_load_ability_from_path(path)
	elif file_dialog.file_mode == EditorFileDialog.FILE_MODE_SAVE_FILE:
		ResourceSaver.save(current_ability, path)
		print("Ability saved to: ", path)
		_scan_for_abilities() # Refresh list to show new file

func _on_general_info_changed(value = null) -> void:
	if is_updating_ui or current_ability == null: return
	current_ability.ability_name = ability_name_edit.text
	current_ability.description = description_edit.text
	current_ability.max_level = int(max_level_spinbox.value)
	current_ability.ability_type = ability_type_option.get_selected_id()
	current_ability.required_class.clear()
	current_ability.required_class.append(required_class_option.get_selected_id())
	current_ability.required_weapon_types.clear()
	current_ability.required_weapon_types.append(required_weapon_option.get_selected_id())

func _on_level_detail_changed(value = null) -> void:
	if is_updating_ui or current_ability == null: return
	var selected_indices = level_list.get_selected_items()
	if selected_indices.is_empty(): return
	var selected_idx = selected_indices[0]
	var level_data: AbilityLevelData = current_ability.level_data[selected_idx]
	level_data.mana_cost = int(mana_cost_spinbox.value)
	level_data.cooldown_time = float(cooldown_spinbox.value)
	level_data.damage_percent = int(damage_percent_spinbox.value)
	level_data.fixed_damage = int(fixed_damage_spinbox.value)
	level_data.max_targets = int(max_targets_spinbox.value)

func _on_add_level_pressed() -> void:
	if current_ability == null: return
	var next_level_num = current_ability.level_data.size() + 1
	var new_level_data = AbilityLevelData.new(next_level_num)
	current_ability.level_data.append(new_level_data)
	_update_level_list()
	level_list.select(current_ability.level_data.size() - 1)
	_update_level_details()

func _on_remove_level_pressed() -> void:
	if current_ability == null: return
	var selected_indices = level_list.get_selected_items()
	if selected_indices.is_empty(): return
	current_ability.level_data.remove_at(selected_indices[0])
	for i in range(current_ability.level_data.size()):
		current_ability.level_data[i].level = i + 1
	_update_level_list()
	level_list.deselect_all()
	_update_level_details()

func _on_level_selected(index: int) -> void:
	_update_level_details()
