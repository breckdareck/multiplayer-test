@tool
class_name ResourceTypeConfig
extends Resource

## Configuration for a single resource type
class ResourceType:
	var display_name: String
	var script_path: String
	var base_folder: String
	var file_extension: String = "tres"
	var icon_name: String = "" # Optional icon for the type
	var category: String = "" # Category for grouping (e.g., "Items", "Abilities")
	var create_new_func: Callable # Custom function to create new instance
	var needs_special_ui: bool = false # Whether this type needs custom UI panels
	
	func _init(
		p_display_name: String = "",
		p_script_path: String = "",
		p_base_folder: String = "",
		p_category: String = "",
		p_needs_special_ui: bool = false
	):
		display_name = p_display_name
		script_path = p_script_path
		base_folder = p_base_folder
		category = p_category
		needs_special_ui = p_needs_special_ui


## Get all configured resource types
static func get_all_resource_types() -> Array[ResourceType]:
	var types: Array[ResourceType] = []
	
	# Ability System Resources
	var ability_type = ResourceType.new(
		"Abilities",
		"res://scripts/Resources/AbilitySystem/AbilityData.gd",
		"res://resources/Abilities",
		"Ability System",
		true # Needs special UI (formula editor, level editor)
	)
	ability_type.icon_name = "NodeWarning" # Use Godot built-in icon
	types.append(ability_type)
	
	# Item System Resources
	var item_type = ResourceType.new(
		"Items",
		"res://scripts/Resources/ItemSystem/ItemData.gd",
		"res://resources/Items",
		"Item System",
		false
	)
	item_type.icon_name = "PackedScene"
	types.append(item_type)
	
	var weapon_type = ResourceType.new(
		"Weapons",
		"res://scripts/Resources/ItemSystem/WeaponData.gd",
		"res://resources/Items/Weapons",
		"Item System",
		false
	)
	weapon_type.icon_name = "Sword"
	types.append(weapon_type)
	
	var armor_type = ResourceType.new(
		"Armor",
		"res://scripts/Resources/ItemSystem/ArmorData.gd",
		"res://resources/Items/Armor",
		"Item System",
		false
	)
	armor_type.icon_name = "Shield"
	types.append(armor_type)
	
	var consumable_type = ResourceType.new(
		"Consumables",
		"res://scripts/Resources/ItemSystem/ConsumableData.gd",
		"res://resources/Items/Consumables",
		"Item System",
		false
	)
	consumable_type.icon_name = "Heart"
	types.append(consumable_type)
	
	# Buff System Resources
	var buff_type = ResourceType.new(
		"Buffs",
		"res://scripts/Resources/BuffSystem/BuffData.gd",
		"res://resources/Buffs",
		"Buff System",
		false
	)
	buff_type.icon_name = "StatusEffect"
	types.append(buff_type)
	
	# Class System Resources
	var class_type = ResourceType.new(
		"Classes",
		"res://scripts/Resources/ClassSystem/ClassData.gd",
		"res://resources/Classes",
		"Class System",
		false
	)
	class_type.icon_name = "AnimationPlayer"
	types.append(class_type)
	
	# Enemy Data Resources
	var enemy_type = ResourceType.new(
		"Enemies",
		"res://scripts/Resources/EnemyData.gd",
		"res://resources/Enemies",
		"Enemy System",
		false
	)
	enemy_type.icon_name = "CharacterBody2D"
	types.append(enemy_type)
	
	return types


## Get resource types grouped by category
static func get_resource_types_by_category() -> Dictionary:
	var all_types = get_all_resource_types()
	var by_category: Dictionary = {}
	
	for type in all_types:
		if not by_category.has(type.category):
			by_category[type.category] = []
		by_category[type.category].append(type)
	
	return by_category


## Find a resource type by display name
static func get_resource_type_by_name(display_name: String) -> ResourceType:
	var all_types = get_all_resource_types()
	for type in all_types:
		if type.display_name == display_name:
			return type
	return null


## Create a new instance of a resource type
static func create_new_resource(type: ResourceType) -> Resource:
	if not type:
		return null
	
	var script = load(type.script_path)
	if not script:
		push_error("Failed to load script: " + type.script_path)
		return null
	
	var resource = script.new()
	
	# Special initialization for specific types
	if type.display_name == "Abilities":
		# Initialize ability with default values
		resource.max_level = 10
		resource.use_scaling_formulas = true
		resource.scaling_data = load("res://scripts/Resources/AbilitySystem/AbilityScalingData.gd").new()
		resource.scaling_data.resource_local_to_scene = true
		resource.active_behavior = load("res://scripts/Resources/AbilitySystem/ActiveBehaviorData.gd").new()
		resource.active_behavior.resource_local_to_scene = true
	
	return resource
