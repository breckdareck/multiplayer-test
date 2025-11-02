class_name ClassComponent
extends Node

signal class_changed(new_class: String)

@export var current_class: Constants.ClassType

var class_abilities: Array[AbilityData] = []

func _ready() -> void:
	_load_class_abilities()


func _load_class_abilities() -> void:
	var abilities: Array[AbilityData] = get_available_abilities()
	class_abilities.clear()
	for ability in abilities:
		class_abilities.append(ability)
	print("ClassComponent: Loaded %d abilities for %s." % [class_abilities.size(), get_class_name()])


func get_class_abilities() -> Array[AbilityData]:
	return class_abilities

func get_class_name() -> String:
	return ResourceManager.get_class_name(current_class)
	
func get_base_stats() -> Dictionary:
	return ResourceManager.get_base_stats(current_class)

func get_class_bonuses() -> Dictionary:
	return ResourceManager.get_class_bonuses(current_class)

func get_available_abilities() -> Array[AbilityData]:
	return ResourceManager.get_class_skills(current_class)

func change_class(new_class: Constants.ClassType) -> void:
	if new_class != current_class:
		var old_class_name: String = get_class_name()
		print("ClassComponent: Changing class from %s to %s" % [old_class_name, ResourceManager.get_class_name(new_class)])
		current_class = new_class
		_load_class_abilities()
		class_changed.emit(get_class_name())
		# NEW: Notify PartyManager of the class change
		if multiplayer and multiplayer.is_server():
			PartyManager.notify_player_data_changed(get_owner().player_id)

@rpc("authority", "call_local", "reliable")
func change_class_rpc(new_class: int) -> void:
	print("ClassComponent: Change Class RPC called")
	change_class(new_class as Constants.ClassType)
