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
@export var damage_stat: Constants.StatType = Constants.StatType.WEAPONATTACK
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

@export_group("Scaling Configuration")
@export var scaling_data: AbilityScalingData

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


## Retrieves the AbilityLevelData resource for the specified level by
## generating it from `scaling_data`'s formulas.
func get_level_stats(level: int) -> AbilityLevelData:
	if level < 1 or level > max_level:
		return null

	if not scaling_data:
		push_error("Ability '%s' has no scaling_data!" % ability_name)
		return null

	return scaling_data.generate_level_data(level)


## Builds a plain-text tooltip describing this ability.
## If `current_level <= 0` the level line says "Unlearned" and placeholders are
## substituted using level 1 values so the player can preview the ability.
func get_tooltip_text(current_level: int = 0) -> String:
	var display_level: int = current_level if current_level > 0 else 1
	var stats: AbilityLevelData = get_level_stats(display_level)

	var lines: Array[String] = []
	lines.append(ability_name)

	var type_str: String = "Passive" if ability_type == Constants.AbilityType.PASSIVE else "Active"
	if current_level > 0:
		lines.append("%s — Level %d / %d" % [type_str, current_level, max_level])
	else:
		lines.append("%s — Unlearned" % type_str)

	if stats and ability_type == Constants.AbilityType.ACTIVE:
		if stats.mana_cost > 0:
			lines.append("Mana Cost: %d" % stats.mana_cost)
		if stats.cooldown_time > 0:
			lines.append("Cooldown: %.1fs" % stats.cooldown_time)

	var desc := _format_plain_description(stats)
	if not desc.is_empty():
		lines.append("")
		lines.append(desc)

	return "\n".join(lines)


## Substitutes the description template's placeholders ($[damage_percent],
## $[target_count], $[hit_count], $[buff_duration], $[stat_bonus]) for the given
## level. Returns plain text — no BBCode.
func _format_plain_description(level_data: AbilityLevelData) -> String:
	if description.is_empty():
		return ""
	var output := description
	if ability_type == Constants.AbilityType.ACTIVE and level_data:
		output = output.replace("$[damage_percent]", "%d%%" % level_data.damage_percent)
		if scaling_data:
			if scaling_data.max_targets_formula:
				output = output.replace("$[target_count]", "%d" % scaling_data.max_targets_formula.calculate(level_data.level))
			if scaling_data.max_hits_formula:
				output = output.replace("$[hit_count]", "%d" % scaling_data.max_hits_formula.calculate(level_data.level))
		if applies_buff and buff_duration_formula:
			output = output.replace("$[buff_duration]", "%.0fs" % buff_duration_formula.calculate(level_data.level))

	if level_data and not level_data.stat_bonuses.is_empty():
		var stat_key = level_data.stat_bonuses.keys()[0]
		var stat_data: StatData = level_data.stat_bonuses[stat_key]
		var stat_value: float = float(stat_data.total_value) if stat_data.total_value > 0 else stat_data.percent_bonus_value
		output = output.replace("$[stat_bonus]", "%d" % stat_value)

	return output
