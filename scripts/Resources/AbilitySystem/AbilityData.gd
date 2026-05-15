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
@export var max_level: int
@export var ability_type: Constants.AbilityType
@export var required_class: Array[Constants.ClassType]
@export var required_weapon_types: Array[Constants.WeaponType]
@export var prerequisite_abilities: Dictionary[AbilityData, int] = {}

@export var active_behavior: ActiveBehaviorData

@export_group("Buff Configuration")
@export var applies_buff: BuffData = null
@export var buff_duration_formula: AbilityScalingFormula = null

@export_group("Target Debuff")
## Debuff applied to each enemy hit by this ability
@export var applies_target_debuff: BuffData = null
@export var debuff_duration_formula: AbilityScalingFormula = null

## NEW: Use either scaling data OR manual level data
@export_group("Scaling Configuration")
@export var use_scaling_formulas: bool = true
@export var scaling_data: AbilityScalingData

## OLD: Manual level data (only used if use_scaling_formulas = false)
@export var level_data: Array[AbilityLevelData]

## Cache for generated level data to avoid recalculating
var _level_data_cache: Dictionary = {}


func _init():
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
## If using scaling formulas, generates it on-the-fly and caches it.
func get_level_stats(level: int) -> AbilityLevelData:
	if level < 1 or level > max_level:
		return null
	
	# Use manual level data if not using formulas
	if not use_scaling_formulas:
		var index = level - 1
		if index >= 0 and index < level_data.size():
			return level_data[index]
		return null
	
	# Use scaling formulas
	if not scaling_data:
		push_error("Ability '%s' is set to use scaling formulas but has no scaling_data!" % ability_name)
		return null
	
	# Check cache first
	if _level_data_cache.has(level):
		return _level_data_cache[level]
	
	# Generate and cache
	var generated_data = scaling_data.generate_level_data(level)
	_level_data_cache[level] = generated_data
	return generated_data
