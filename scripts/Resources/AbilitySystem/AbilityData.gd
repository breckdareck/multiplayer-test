@tool
class_name AbilityData
extends Resource

@export var ability_id: String:
	set(value):
		if value.is_empty():
			ability_id = generate_uuid()
		else:
			ability_id = value
@export var ability_name: String = ""
@export_multiline var description: String = ""
@export var ability_icon: Texture2D
## Max Level the ability can level up to
@export var max_level: int
## Is this a Passive or Active Ability
@export var ability_type: Constants.AbilityType
## Only allow these classes to use ability
@export var required_class: Array[Constants.ClassType]
## Only allow these weapons to use ability
@export var required_weapon_types: Array[Constants.WeaponType]
## AbilityData to Level Required
@export var prerequisite_abilities: Dictionary[AbilityData, int] = {}

@export var active_behavior: ActiveBehaviorData
@export var level_data: Array[AbilityLevelData]


func _init():
	# Only generate a UUID if one doesn't already exist.
	if ability_id.is_empty():
		ability_id = generate_uuid()


func generate_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32)),
	]

## Retrieves the AbilityLevelData resource for the specified level.
## Returns null if the level is out of bounds.
func get_level_stats(level: int) -> AbilityLevelData:
	# Levels are 1-based, array indices are 0-based.
	var index = level - 1
	
	if index >= 0 and index < level_data.size():
		return level_data[index]
	
	# Fallback for invalid levels
	return null
