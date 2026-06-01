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

@export_group("Skill Tree Layout")
## Which of the discipline's two paths this ability occupies in the skill-tree
## window. 0 = Path A (left column), 1 = Path B (right column). -1 = not placed
## in the tree (orphaned / utility abilities are hidden from the tree view).
@export var tree_path: int = -1
## Row within the path, 0 at the top (a path's depth-0 node is its root). Drives
## both the visual layout AND the climb-gate: a node at depth D requires the
## same-discipline, same-path node at depth D-1 to be learned (level >= 1).
@export var tree_depth: int = 0

## PR 6 — per-ability upgrade tree. Each upgrade is its own .tres
## (AbilityUpgradeData) referenced here. Empty array = no upgrades available
## for this ability (the pre-PR-6 baseline behavior).
@export var upgrades: Array[AbilityUpgradeData] = []

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
## $[target_count], $[hit_count], $[buff_duration], $[stat_bonus], and named
## $[value:KEY] custom values) for the given level. The text may still contain
## hand-authored BBCode ([color=...]) from the description — callers that show
## the result must render it with a BBCode-enabled control (see the hotbar /
## skill-tree slot custom tooltips), otherwise the tags display raw.
##
## Note ($[damage_percent] gating): the placeholder is also evaluated for
## PASSIVE abilities now. Passives may use `scaling_data.damage_percent_formula`
## as a generic level-scaled "value" formula for description display (e.g.
## Bloodthirst's heal %); the field is otherwise unused for passives since
## they don't deal damage on cast.
func _format_plain_description(level_data: AbilityLevelData) -> String:
	if description.is_empty():
		return ""
	var output := description
	if level_data:
		if ability_type == Constants.AbilityType.ACTIVE:
			output = output.replace("$[damage_percent]", "%s%%" % _smart_format_number(level_data.damage_percent))
		elif scaling_data and scaling_data.damage_percent_formula:
			# Passive: read the formula directly (level_data.damage_percent
			# is only populated for active abilities).
			var v: float = scaling_data.damage_percent_formula.calculate(level_data.level)
			output = output.replace("$[damage_percent]", "%s%%" % _smart_format_number(v))
		if scaling_data:
			if scaling_data.max_targets_formula:
				output = output.replace("$[target_count]", "%d" % scaling_data.max_targets_formula.calculate(level_data.level))
			if scaling_data.max_hits_formula:
				output = output.replace("$[hit_count]", "%d" % scaling_data.max_hits_formula.calculate(level_data.level))
		if applies_buff and buff_duration_formula:
			output = output.replace("$[buff_duration]", "%.0fs" % buff_duration_formula.calculate(level_data.level))

		# Named custom values ($[value:KEY]) — for abilities whose effect numbers
		# live in their AL script rather than a fixed scaling field (Bulwark's
		# Defense, Sentinel's damage + refund, Banner's Defense + HP regen).
		# The AL reads the same formula via get_custom_value(), so the displayed
		# number always equals the gameplay number.
		if scaling_data:
			for key in scaling_data.custom_value_formulas:
				var f: AbilityScalingFormula = scaling_data.custom_value_formulas[key]
				if f:
					output = output.replace("$[value:%s]" % key, _smart_format_number(f.calculate(level_data.level)))

	if level_data and not level_data.stat_bonuses.is_empty():
		var stat_key = level_data.stat_bonuses.keys()[0]
		var stat_data: StatData = level_data.stat_bonuses[stat_key]
		var stat_value: float = float(stat_data.total_value) if stat_data.total_value > 0 else stat_data.percent_bonus_value
		output = output.replace("$[stat_bonus]", _smart_format_number(stat_value))

	return output


## Single source of truth for a named, level-scaled custom value (see
## scaling_data.custom_value_formulas). Both the description formatter and the
## ability's AL_*.gd script call this, so the tooltip number and the gameplay
## number are always identical. Returns `default` if the key has no formula.
func get_custom_value(key: String, level: int, default: float = 0.0) -> float:
	if not scaling_data:
		return default
	var f: AbilityScalingFormula = scaling_data.custom_value_formulas.get(key)
	if f == null:
		return default
	return f.calculate(level)


## Single source of truth for conditional-damage passives (Execution, Tailwind,
## Composure, Opportunist, Toxicology, Killing Spree, Overload). The bonus is
## authored in display percent on `damage_percent_formula` so $[damage_percent]
## shows the live value; the AL_*.gd reads the FRACTION here so the tooltip and
## gameplay can't drift. Returns `fallback` if the formula is missing.
func get_damage_percent_fraction(level: int, fallback: float = 0.0) -> float:
	if scaling_data and scaling_data.damage_percent_formula:
		return scaling_data.damage_percent_formula.calculate(level) / 100.0
	return fallback


## Formats a numeric value for description display. Whole numbers show as
## integers ("4"), fractional values show with one decimal place ("0.5",
## "3.2"). Used by both the plain-text formatter here and the BBCode
## formatter in ability_window.gd — keep them in sync if the rule changes.
static func _smart_format_number(value: float) -> String:
	# Snap to one decimal first so float fuzz from per-level division
	# (e.g. 100 + 9 * (150.0/9) = 250.0000003) renders as a clean "250"
	# rather than "250.0".
	var v := snappedf(value, 0.1)
	if v == floor(v):
		return "%d" % int(v)
	return "%.1f" % v
