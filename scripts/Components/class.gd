class_name ClassComponent
extends Node

signal class_changed(new_class: String)

@export var current_class: Constants.ClassType = Constants.ClassType.SWORDSMAN

var _stats_component: StatsComponent

func _ready() -> void:
	_stats_component = get_parent().get_node_or_null("Stats")
	if not multiplayer.is_server():
		return
		
	# class_changed.emit(get_class_name())

func get_class_name() -> String:
	return ResourceManager.get_class_name(current_class)

func get_class_data() -> ClassData:
	return ResourceManager.get_class_data(current_class)
	
func get_base_stats() -> Dictionary:
	return ResourceManager.get_base_stats(current_class)
	
func get_growth_rates() -> Dictionary:
	return ResourceManager.get_growth_rates(current_class)

func get_class_bonuses() -> Dictionary:
	return ResourceManager.get_class_bonuses(current_class)

func get_available_skills() -> Array[String]:
	return ResourceManager.get_class_skills(current_class)

func get_class_summary() -> Dictionary:
	var data = get_class_data()
	return {
		"class_name": get_class_name(),
		"class_type": current_class,
		"bonuses": get_class_bonuses(),
		"skills": get_available_skills(),
		"description": data.description if data else "",
		"base_stats": ResourceManager.get_base_stats(current_class),
		"growth_rates": ResourceManager.get_growth_rates(current_class)
	}
	return {
		"class_name": get_class_name(),
		"class_type": current_class,
		"bonuses": get_class_bonuses(),
		"skills": get_available_skills()
	}

func change_class(new_class: Constants.ClassType) -> void:
	if new_class != current_class:
		var old_class_name = get_class_name()
		print("ClassComponent: Changing class from %s to %s" % [old_class_name, ResourceManager.get_class_name(new_class)])
		current_class = new_class
		class_changed.emit(get_class_name())

func change_class_by_name(_class_name: String) -> void:
	var class_type = ResourceManager.get_class_type_from_string(_class_name)
	change_class(class_type)

@rpc("authority", "call_local", "reliable")
func change_class_rpc(new_class: int) -> void:
	change_class(new_class)
	
	
# Convenience methods for checking class
func is_swordsman() -> bool:
	return current_class == Constants.ClassType.SWORDSMAN

func is_archer() -> bool:
	return current_class == Constants.ClassType.ARCHER

func is_mage() -> bool:
	return current_class == Constants.ClassType.MAGE

func has_skill(skill_name: String) -> bool:
	var data = get_class_data()
	return data.has_skill(skill_name) if data else false
