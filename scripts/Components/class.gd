class_name ClassComponent
extends Node

signal class_changed(new_class: String)

@export var current_class: Constants.ClassType:
	set(value):
		current_class = _ADVANCED_TO_BASE.get(value, value)

var class_abilities: Array[AbilityData] = []

## PR 7 — Job Advancement removed: classes don't exist, only weapons. Any legacy
## advanced class (CRUSADER/RANGER/ARCHMAGE/ASSASSIN) normalizes back to its
## tier-1 weapon discipline so existing advanced characters revert to weapon-pure
## on load. No backend migration needed; the setter catches every assignment.
const _ADVANCED_TO_BASE: Dictionary = {
	Constants.ClassType.CRUSADER: Constants.ClassType.SWORD,
	Constants.ClassType.RANGER: Constants.ClassType.BOW,
	Constants.ClassType.ARCHMAGE: Constants.ClassType.STAFF,
	Constants.ClassType.ASSASSIN: Constants.ClassType.DAGGER,
}

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
