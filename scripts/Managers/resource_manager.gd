# ResourceManager.gd - Autoload script
extends Node

# Dictionary to store class data by class type enum value
var class_data: Dictionary[Constants.ClassType, ClassData] = {}

var item_data: Dictionary[String, ItemData] = {}
var item_by_name: Dictionary[String, ItemData] = {}

var ability_data: Dictionary[String, AbilityData] = {}
var ability_by_name: Dictionary[String, AbilityData] = {}

var buff_data: Dictionary[String, BuffData] = {}
var buffs_by_name: Dictionary[String, BuffData] = {}

func _ready() -> void:
	_load_class_data()
	_load_item_data()
	_load_ability_data()
	_load_buff_data()
	

#region Item Data Functions

func _load_item_data() -> void:
	var item_folder: String = "res://resources/Items/"

	var process_item = func(resource, path):
		if resource is ItemData:
			item_data[resource.item_id] = resource
			item_by_name[resource.name] = resource
			print("Loaded item: %s from path: %s" % [resource.name, path])
			print("DEBUG: ResourceManager loaded item icon: ", resource.icon)
		else:
			print("Skipped (not ItemData): %s" % path)
			
	# Call the generic loader
	_load_resources_recursively(item_folder, process_item)
		

func get_item_data(item_id: String) -> ItemData:
	# If it's a UUID, look it up directly
	if item_data.has(item_id):
		return item_data[item_id]
	
	# If it's a name, try to find it by name
	if item_by_name.has(item_id):
		return item_by_name[item_id]
	
	# Nothing found
	print("Item not found: %s" % item_id)
	return null
	
	
func get_item_by_name(item_name: String) -> ItemData:
	return item_by_name.get(item_name)
	
#endregion


#region Class Data Functions

func _load_class_data() -> void:
	var class_folder: String = "res://resources/Player/Classes/"
	
	var process_class = func(resource, path):
		if resource is ClassData:
			class_data[resource.class_type] = resource
			print("Loaded class: %s from path: %s" % [resource._class_name, path])
		else:
			print("Skipped (not ClassData): %s" % path)

	_load_resources_recursively(class_folder, process_class)


func get_class_data(class_type: Constants.ClassType) -> ClassData:
	return class_data.get(class_type)


func get_class_name(class_type: Constants.ClassType) -> String:
	var data: ClassData = get_class_data(class_type)
	return data._class_name if data else "unknown"


func get_class_bonuses(class_type: Constants.ClassType) -> Dictionary:
	var data: ClassData = get_class_data(class_type)
	return data.stat_bonuses if data else {}


func get_class_skills(class_type: Constants.ClassType) -> Array[AbilityData]:
	var data: ClassData = get_class_data(class_type)
	return data.skills if data else []


func get_sprite_frames_for_class(class_type: Constants.ClassType) -> Dictionary:
	var data: ClassData = get_class_data(class_type)
	return data.sprite_frames if data else {}


func get_sprite_for_level(class_type: Constants.ClassType, level: int) -> SpriteFrames:
	var data: ClassData = get_class_data(class_type)
	return data.get_sprite_for_level(level) if data else null


func get_base_stats(class_type: Constants.ClassType) -> Dictionary:
	var data: ClassData = get_class_data(class_type)
	return data.base_stats if data else {}


func get_primary_stat(class_type: Constants.ClassType) -> Constants.StatType:
	var data: ClassData = get_class_data(class_type)
	return data.primary_stat
	

func get_secondary_stat(class_type: Constants.ClassType) -> Constants.StatType:
	var data: ClassData = get_class_data(class_type)
	return data.secondary_stat

# Utility function to get ClassType enum from string
func get_class_type_from_string(_class_name: String) -> Constants.ClassType:
	match _class_name.to_lower():
		"swordsman":
			return Constants.ClassType.SWORDSMAN
		"archer":
			return Constants.ClassType.ARCHER
		"mage":
			return Constants.ClassType.MAGE
		_:
			return Constants.ClassType.SWORDSMAN  # Default fallback
#endregion


#region Ability Data Functions

func _load_ability_data() -> void:
	var ability_folder: String = "res://resources/Abilities/"
	
	var process_ability = func(resource, path):
		if resource is AbilityData:
			ability_data[resource.ability_id] = resource 
			ability_by_name[resource.ability_name] = resource 
			print("Loaded ability: %s from path: %s" % [resource.ability_name, path])
		else:
			print("Skipped (not AbilityData): %s" % path)

	_load_resources_recursively(ability_folder, process_ability)


func get_ability_data(ability_identifier: String) -> AbilityData:
	# First check by ID
	if ability_data.has(ability_identifier):
		return ability_data[ability_identifier]
	
	# Then check by name
	if ability_by_name.has(ability_identifier):
		return ability_by_name[ability_identifier]
	
	# Nothing found
	print("Ability not found: %s" % ability_identifier)
	return null

func get_ability_by_name(ability_name: String) -> AbilityData:
	return ability_by_name.get(ability_name)

#endregion


#region Buff Data Functions

func _load_buff_data() -> void:
	var buff_folder: String = "res://resources/Buffs/"
	
	var process_buff = func(resource, path):
		if resource is BuffData:
			buff_data[resource.buff_id] = resource 
			buffs_by_name[resource.buff_name] = resource 
			print("Loaded buff: %s from path: %s" % [resource.buff_name, path])
		else:
			print("Skipped (not BuffData): %s" % path)
			
	_load_resources_recursively(buff_folder, process_buff)
		
func get_buff_data(buff_identifier: String) -> BuffData:
	if buff_data.has(buff_identifier):
		return buff_data[buff_identifier]
		
	if buffs_by_name.has(buff_identifier):
		return buffs_by_name[buff_identifier]
		
	print("Buff not found: %s" % buff_identifier)
	return null
	
func get_buff_by_name(buff_name: String) -> BuffData:
	return buffs_by_name.get(buff_name)

		
#endregion


func _load_resources_recursively(path: String, process_callable: Callable) -> void:
	# Get all items (files and directories) in the current path
	var items = ResourceLoader.list_directory(path)
	
	for item_name in items:
		var full_path = path + item_name
		
		# Check if the item is a directory (it will end with "/")
		if item_name.ends_with("/"):
			# It's a directory! Call this function again for the subdirectory.
			# This is the "recursive" step.
			_load_resources_recursively(full_path, process_callable)
			
		# Check if it's a resource file we want to load
		# This avoids trying to load ".import" files
		elif full_path.ends_with(".tres") or full_path.ends_with(".res"):
			# It's a file! Load it.
			var resource = ResourceLoader.load(full_path)
			
			if resource:
				# Call the provided 'Callable' and pass it the loaded resource
				process_callable.call(resource, full_path)
			else:
				print("Failed to load resource at: %s" % full_path)
