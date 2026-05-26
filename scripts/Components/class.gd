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
	##print("ClassComponent: Loaded %d abilities for %s." % [class_abilities.size(), get_class_name()])


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


## Returns the ability auto-granted at level 1 to a new character of this
## class (the class's "starter skill" — Slash for Swordsman, Magic Bolt for
## Mage, etc.). Returns null if the class has no starter configured.
func get_starter_ability() -> AbilityData:
	var data: ClassData = ResourceManager.get_class_data(current_class)
	if data == null:
		return null
	return data.starter_ability

func change_class(new_class: Constants.ClassType) -> void:
	if new_class != current_class:
		##print("ClassComponent: Changing class from %s to %s" % [get_class_name(), ResourceManager.get_class_name(new_class)])
		current_class = new_class
		_load_class_abilities()
		class_changed.emit(get_class_name())
		# NEW: Notify PartyManager of the class change
		if multiplayer and multiplayer.is_server():
			PartyManager.notify_player_data_changed(get_owner().player_id)

@rpc("authority", "call_local", "reliable")
func change_class_rpc(new_class: int) -> void:
	##print("ClassComponent: Change Class RPC called")
	change_class(new_class as Constants.ClassType)
