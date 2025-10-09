# ResourceManager.gd - Autoload script
extends Node

# Dictionary to store class data by class type enum value
var class_data: Dictionary[Constants.ClassType, ClassData] = {}
var item_data: Dictionary[String, ItemData] = {}
var item_by_name: Dictionary[String, ItemData] = {} # New lookup dictionary

var ability_data: Dictionary[String, AbilityData] = {}
var ability_by_name: Dictionary[String, AbilityData] = {}

func _ready() -> void:
	_load_class_data()
	_load_item_data()
	_load_ability_data()
	

#region Item Data Functions

func _load_item_data() -> void:
	var item_folder: String = "res://resources/Items/"

	for resource in ResourceLoader.list_directory(item_folder):
		var data: ItemData = ResourceLoader.load(item_folder+resource)
		item_data[data.item_id] = data
		item_by_name[data.name] = data # Add name-based lookup
		print("Loaded item: %s with ID: %s" % [data.name, data.item_id])
		

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
	
	for resource in ResourceLoader.list_directory(class_folder):
		var data: ClassData = ResourceLoader.load(class_folder+resource)
		class_data[data.class_type] = data
		print("Loaded class: %s " % data._class_name)


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
	_load_abilities_recursive(ability_folder)


func _load_abilities_recursive(path: String) -> void:
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			var full_path = path + file_name
			
			if dir.current_is_dir() and file_name != "." and file_name != "..":
				# It's a subdirectory, recursively load from it
				_load_abilities_recursive(full_path + "/")
			elif file_name.ends_with(".tres") or file_name.ends_with(".res"):
				# It's a resource file, try to load it
				var data = ResourceLoader.load(full_path)
				if data is AbilityData:
					ability_data[data.ability_id] = data
					ability_by_name[data.ability_name] = data
					print("Loaded ability: %s with ID: %s" % [data.ability_name, data.ability_id])
			
			file_name = dir.get_next()
			
		dir.list_dir_end()


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
