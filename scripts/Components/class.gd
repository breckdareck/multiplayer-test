class_name ClassComponent
extends Node

signal class_changed(new_class: String)

@export var current_class: Constants.ClassType

var _stats_component: StatsComponent

func _ready() -> void:
	_stats_component = get_parent().get_node_or_null("Stats")

func get_class_name() -> String:
	return ResourceManager.get_class_name(current_class)
	
func get_base_stats() -> Dictionary:
	return ResourceManager.get_base_stats(current_class)

func get_class_bonuses() -> Dictionary:
	return ResourceManager.get_class_bonuses(current_class)

func get_available_skills() -> Array[String]:
	return ResourceManager.get_class_skills(current_class)

func change_class(new_class: Constants.ClassType) -> void:
	if new_class != current_class:
		var old_class_name: String = get_class_name()
		print("ClassComponent: Changing class from %s to %s" % [old_class_name, ResourceManager.get_class_name(new_class)])
		current_class = new_class
		class_changed.emit(get_class_name())

@rpc("authority", "call_local", "reliable")
func change_class_rpc(new_class: int) -> void:
	print("ClassComponent: Change Class RPC called")
	change_class(new_class as Constants.ClassType)
