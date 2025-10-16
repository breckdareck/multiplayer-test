@tool
class_name AbilityEditorGUI
extends Control

# --- ONREADY VARS ---
# File Browser
@onready var refresh_button = $Panel/MainHSplit/AbilityBrowser/RefreshButton
@onready var ability_tree = $Panel/MainHSplit/AbilityBrowser/AbilityTree

# General Ability Info
@onready var ability_id_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_ID/AbilityIDEdit
@onready var ability_name_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Name/AbilityNameEdit
@onready var description_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Desc/DescriptionEdit
@onready var icon_path_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Icon/IconPathEdit
@onready var max_level_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_MaxLevel/MaxLevelSpinBox
@onready var ability_type_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Type/AbilityTypeOption
@onready var required_class_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Class/RequiredClassOption
@onready var required_weapon_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Weapon/RequiredWeaponOption

# Active Behavior
@onready var active_behavior_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior
@onready var target_type_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_TargetType/TargetTypeOption
@onready var animation_name_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_Animation/AnimationNameEdit
@onready var sfx_path_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_SFX/SFXPathEdit
@onready var hitbox_shape_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_HitboxShape/HitboxShapeEdit
@onready var hitbox_pos_x = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_HitboxPos/HitboxPosX
@onready var hitbox_pos_y = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_HitboxPos/HitboxPosY
@onready var logic_script_edit = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/Form/HBox_LogicScript/LogicScriptEdit

# Level Info
@onready var level_list = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/LevelList
@onready var level_details_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails
@onready var level_label = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/LevelLabel

# Basic Level Stats
@onready var mana_cost_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/ManaCost/ManaCostSpinBox
@onready var cooldown_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/Cooldown/CooldownSpinBox
@onready var cast_time_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/CastTime/CastTimeSpinBox
@onready var damage_percent_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/DamagePercent/DamagePercentSpinBox
@onready var max_targets_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/MaxTargets/MaxTargetsSpinBox
@onready var max_hits_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/BasicStats/MaxHits/MaxHitsSpinBox

# Advanced Level Stats
@onready var status_chance_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/AdvancedStats/StatusChance/StatusChanceSpinBox
@onready var status_duration_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/AdvancedStats/StatusDuration/StatusDurationSpinBox
@onready var range_mult_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/AdvancedStats/RangeMult/RangeMultSpinBox
@onready var knockback_spinbox = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/LevelDetails/MarginContainer/Form/AdvancedStats/Knockback/KnockbackSpinBox

# Buttons & Dialogs
@onready var new_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/NewButton
@onready var load_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/LoadButton
@onready var save_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveButton
@onready var save_as_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveAsButton
@onready var add_level_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/AddLevelButton
@onready var remove_level_button = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/LevelSettings/HSplitContainer/VBoxContainer/HBoxContainer/RemoveLevelButton
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
	_populate_option_button(target_type_option, Constants.TargetType)

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
	ability_id_edit.text_changed.connect(_on_general_info_changed)
	ability_name_edit.text_changed.connect(_on_general_info_changed)
	description_edit.text_changed.connect(_on_general_info_changed)
	icon_path_edit.text_changed.connect(_on_general_info_changed)
	max_level_spinbox.value_changed.connect(_on_general_info_changed)
	ability_type_option.item_selected.connect(_on_ability_type_changed)
	required_class_option.item_selected.connect(_on_general_info_changed)
	required_weapon_option.item_selected.connect(_on_general_info_changed)

	# Active behavior fields
	target_type_option.item_selected.connect(_on_active_behavior_changed)
	animation_name_edit.text_changed.connect(_on_active_behavior_changed)
	sfx_path_edit.text_changed.connect(_on_active_behavior_changed)
	hitbox_shape_edit.text_changed.connect(_on_active_behavior_changed)
	hitbox_pos_x.value_changed.connect(_on_active_behavior_changed)
	hitbox_pos_y.value_changed.connect(_on_active_behavior_changed)
	logic_script_edit.text_changed.connect(_on_active_behavior_changed)

	# Level buttons and list
	add_level_button.pressed.connect(_on_add_level_pressed)
	remove_level_button.pressed.connect(_on_remove_level_pressed)
	level_list.item_selected.connect(_on_level_selected)
	
	# Level detail fields - Basic
	mana_cost_spinbox.value_changed.connect(_on_level_detail_changed)
	cooldown_spinbox.value_changed.connect(_on_level_detail_changed)
	cast_time_spinbox.value_changed.connect(_on_level_detail_changed)
	damage_percent_spinbox.value_changed.connect(_on_level_detail_changed)
	max_targets_spinbox.value_changed.connect(_on_level_detail_changed)
	max_hits_spinbox.value_changed.connect(_on_level_detail_changed)
	
	# Level detail fields - Advanced
	status_chance_spinbox.value_changed.connect(_on_level_detail_changed)
	status_duration_spinbox.value_changed.connect(_on_level_detail_changed)
	range_mult_spinbox.value_changed.connect(_on_level_detail_changed)
	knockback_spinbox.value_changed.connect(_on_level_detail_changed)

# --- CUSTOM METHODS ---
func _scan_for_abilities() -> void:
	ability_tree.clear()
	var root = ability_tree.create_item()
	var ability_script = load("res://scripts/Resources/AbilitySystem/AbilityData.gd")
	if not ability_script:
		print_rich("[color=red]Error:[/color] Could not find AbilityData.gd script.")
		return

	var path = "res://resources/Abilities"
	_recursive_scan(path, root, ability_script)

func _recursive_scan(path: String, parent_item: TreeItem, script_to_match: Script) -> void:
	var dir = DirAccess.open(path)
	if dir:
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
	ability_id_edit.text = current_ability.ability_id
	ability_name_edit.text = current_ability.ability_name
	description_edit.text = current_ability.description
	icon_path_edit.text = current_ability.ability_icon.resource_path if current_ability.ability_icon else ""
	max_level_spinbox.value = current_ability.max_level
	ability_type_option.selected = current_ability.ability_type
	
	if !current_ability.required_class.is_empty():
		required_class_option.selected = current_ability.required_class[0]
	if !current_ability.required_weapon_types.is_empty():
		required_weapon_option.selected = current_ability.required_weapon_types[0]

	# Update active behavior visibility and fields
	_update_active_behavior_ui()

	# Update level list and details
	_update_level_list()
	_update_level_details()
	
	is_updating_ui = false

func _update_active_behavior_ui() -> void:
	if current_ability.ability_type == Constants.AbilityType.ACTIVE:
		active_behavior_panel.show()
		
		# Ensure active_behavior exists
		if current_ability.active_behavior == null:
			current_ability.active_behavior = ActiveBehaviorData.new()
		
		# Populate fields
		target_type_option.selected = current_ability.active_behavior.target_type
		animation_name_edit.text = current_ability.active_behavior.animation_name
		sfx_path_edit.text = current_ability.active_behavior.sfx_path
		hitbox_shape_edit.text = current_ability.active_behavior.hit_box_shape_data.resource_path if current_ability.active_behavior.hit_box_shape_data else ""
		hitbox_pos_x.value = current_ability.active_behavior.hit_box_position_data.x
		hitbox_pos_y.value = current_ability.active_behavior.hit_box_position_data.y
		logic_script_edit.text = current_ability.active_behavior.logic_script.resource_path if current_ability.active_behavior.logic_script else ""
	else:
		active_behavior_panel.hide()

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
	
	# Basic stats
	mana_cost_spinbox.value = level_data.mana_cost
	cooldown_spinbox.value = level_data.cooldown_time
	cast_time_spinbox.value = level_data.cast_time
	damage_percent_spinbox.value = level_data.damage_percent
	max_targets_spinbox.value = level_data.max_targets
	max_hits_spinbox.value = level_data.max_hits
	
	# Advanced stats
	status_chance_spinbox.value = level_data.status_effect_chance
	status_duration_spinbox.value = level_data.status_effect_duration
	range_mult_spinbox.value = level_data.range_multiplier
	knockback_spinbox.value = level_data.knockback_force
	
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
		_scan_for_abilities()

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
		_scan_for_abilities()

func _on_general_info_changed(value = null) -> void:
	if is_updating_ui or current_ability == null: return
	
	current_ability.ability_id = ability_id_edit.text
	current_ability.ability_name = ability_name_edit.text
	current_ability.description = description_edit.text
	
	# Handle icon loading
	if not icon_path_edit.text.is_empty():
		var icon = load(icon_path_edit.text)
		if icon is Texture2D:
			current_ability.ability_icon = icon
	
	current_ability.max_level = int(max_level_spinbox.value)
	current_ability.ability_type = ability_type_option.get_selected_id()
	
	current_ability.required_class.clear()
	current_ability.required_class.append(required_class_option.get_selected_id())
	current_ability.required_weapon_types.clear()
	current_ability.required_weapon_types.append(required_weapon_option.get_selected_id())

func _on_ability_type_changed(index: int) -> void:
	_on_general_info_changed()
	_update_active_behavior_ui()

func _on_active_behavior_changed(value = null) -> void:
	if is_updating_ui or current_ability == null: return
	if current_ability.ability_type != Constants.AbilityType.ACTIVE: return
	
	if current_ability.active_behavior == null:
		current_ability.active_behavior = ActiveBehaviorData.new()
	
	current_ability.active_behavior.target_type = target_type_option.get_selected_id()
	current_ability.active_behavior.animation_name = animation_name_edit.text
	current_ability.active_behavior.sfx_path = sfx_path_edit.text
	
	# Handle hitbox shape loading
	if not hitbox_shape_edit.text.is_empty():
		var shape = load(hitbox_shape_edit.text)
		if shape is Shape2D:
			current_ability.active_behavior.hit_box_shape_data = shape
	
	current_ability.active_behavior.hit_box_position_data = Vector2(hitbox_pos_x.value, hitbox_pos_y.value)
	
	# Handle logic script loading
	if not logic_script_edit.text.is_empty():
		var script = load(logic_script_edit.text)
		if script is Script:
			current_ability.active_behavior.logic_script = script

func _on_level_detail_changed(value = null) -> void:
	if is_updating_ui or current_ability == null: return
	var selected_indices = level_list.get_selected_items()
	if selected_indices.is_empty(): return
	
	var selected_idx = selected_indices[0]
	var level_data: AbilityLevelData = current_ability.level_data[selected_idx]
	
	# Basic stats
	level_data.mana_cost = int(mana_cost_spinbox.value)
	level_data.cooldown_time = float(cooldown_spinbox.value)
	level_data.cast_time = float(cast_time_spinbox.value)
	level_data.damage_percent = int(damage_percent_spinbox.value)
	level_data.max_targets = int(max_targets_spinbox.value)
	level_data.max_hits = int(max_hits_spinbox.value)
	
	# Advanced stats
	level_data.status_effect_chance = float(status_chance_spinbox.value)
	level_data.status_effect_duration = float(status_duration_spinbox.value)
	level_data.range_multiplier = float(range_mult_spinbox.value)
	level_data.knockback_force = float(knockback_spinbox.value)

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
