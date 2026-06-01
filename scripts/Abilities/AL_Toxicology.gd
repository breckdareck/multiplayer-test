extends Node

## Toxicology (dagger passive) — CONDITIONAL damage: +bonus against POISONED
## targets. Twist the toxin — pairs with Envenom (which tags its victims with the
## "envenom_poison" meta). Class-neutral (stacks from both equipped weapon slots).
## See AL_Aggression for the contract (returns the bonus FRACTION; combat applies
## 1 + total).

const POISON_META: String = "envenom_poison"
const BONUS_AT_MAX: float = 0.30   # +30% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 5
func conditional_damage_mult(_owner: Node, target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if not is_instance_valid(target):
		return 0.0
	if not target.has_meta(POISON_META):
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
