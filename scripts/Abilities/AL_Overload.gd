extends Node

## Overload (staff passive) — CONDITIONAL damage: +bonus while the ATTACKER is
## ABOVE MANA_THRESHOLD of their max mana. Channel your reserves — strong while
## you're topped up on mana, falls off as you spend it. Class-neutral (stacks
## from both equipped weapon slots). See AL_Aggression for the contract (returns
## the bonus FRACTION; combat applies 1 + total).

const MANA_THRESHOLD: float = 0.50
const BONUS_AT_MAX: float = 0.25   # +25% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 5
func conditional_damage_mult(owner_node: Node, _target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var mc = owner_node.get("mana_component")
	if mc == null or not is_instance_valid(mc):
		return 0.0
	var mm: float = float(mc.max_mana) if "max_mana" in mc else 0.0
	var cm: float = float(mc.current_mana) if "current_mana" in mc else 0.0
	if mm <= 0.0 or cm / mm <= MANA_THRESHOLD:
		return 0.0
	return _level_bonus(passive_id, level)


## Per-level bonus FRACTION read from this passive's damage_percent_formula
## (single source of truth with the $[damage_percent] tooltip). Falls back to
## the constant ramp only if the ability/formula can't be resolved.
func _level_bonus(passive_id: String, level: int) -> float:
	var data: AbilityData = ResourceManager.get_ability_data(passive_id) if passive_id != "" else null
	if data:
		return data.get_damage_percent_fraction(level, BONUS_AT_MAX * float(level) / float(MAX_LEVEL))
	return BONUS_AT_MAX * float(level) / float(MAX_LEVEL)
