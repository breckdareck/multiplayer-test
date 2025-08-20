# ResourceManager.gd - Autoload script
extends Node

# Dictionary to store class data by class type enum value
var class_data: Dictionary[int, ClassData] = {}

func _ready() -> void:
	_load_class_data()
	print_loaded_classes()  # Debug info

func _load_class_data() -> void:
	var class_folder = "res://resources/Player/Classes/"
	
	for resource in ResourceLoader.list_directory(class_folder):
		var data: ClassData = ResourceLoader.load(class_folder+resource)
		class_data.set(data.class_type, data)


# Additional utility function to debug loaded classes
func print_loaded_classes() -> void:
	print("ResourceManager: Loaded " + str(class_data.size()) + " class(es):")
	for class_type in class_data.keys():
		var data = class_data[class_type]
		print("  - " + data._class_name + " (Type: " + str(class_type) + ")")

# Public API functions
func get_class_data(class_type: Constants.ClassType) -> ClassData:
	return class_data.get(class_type)

func get_class_name(class_type: Constants.ClassType) -> String:
	var data = get_class_data(class_type)
	return data._class_name if data else "unknown"

func get_class_bonuses(class_type: Constants.ClassType) -> Dictionary:
	var data = get_class_data(class_type)
	return data.stat_bonuses if data else {}

func get_class_skills(class_type: Constants.ClassType) -> Array[String]:
	var data = get_class_data(class_type)
	return data.skills if data else []

func get_sprite_frames_for_class(class_type: Constants.ClassType) -> Dictionary:
	var data = get_class_data(class_type)
	return data.sprite_frames if data else {}

func get_sprite_for_level(class_type: Constants.ClassType, level: int) -> SpriteFrames:
	var data = get_class_data(class_type)
	return data.get_sprite_for_level(level) if data else null

func get_all_class_types() -> Array:
	return class_data.keys()

func get_base_stats(class_type: Constants.ClassType) -> Dictionary:
	var data = get_class_data(class_type)
	return data.base_stats if data else {}

func get_growth_rates(class_type: Constants.ClassType) -> Dictionary:
	var data = get_class_data(class_type)
	return data.growth_rates if data else {}

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
