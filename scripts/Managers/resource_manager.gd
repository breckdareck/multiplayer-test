# ResourceManager.gd - Autoload script
extends Node

# Dictionary to store class data by class type enum value
var class_data: Dictionary[Constants.ClassType, ClassData] = {}
var item_data: Dictionary[String, ItemData] = {}
var item_by_name: Dictionary[String, ItemData] = {} # New lookup dictionary

func _ready() -> void:
	_load_class_data()
	_load_item_data()
	

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


func get_class_skills(class_type: Constants.ClassType) -> Array[String]:
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
