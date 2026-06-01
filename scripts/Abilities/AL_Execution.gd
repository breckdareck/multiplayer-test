extends Node

## Execution (passive, replaces the old primary-stat% auto-take) — CONDITIONAL
## damage: +bonus to enemies BELOW HP_THRESHOLD of their max HP. A finisher passive
## — useless on a fresh enemy, big on a wounded one. Higher magnitude than the
## opener passives since its window is small. Class-neutral. See AL_Aggression for
## the contract (returns the bonus FRACTION; combat applies 1 + total).

const HP_THRESHOLD: float = 0.30
## Fallback ramp only — the live value comes from the .tres damage_percent_formula
## (authored as +9%/level → +45% at L5). See AL_Aggression for the contract.
const BONUS_AT_MAX: float = 0.45
const MAX_LEVEL: int = 5
func conditional_damage_mult(_owner: Node, target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if not is_instance_valid(target):
		return 0.0
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc):
		return 0.0
	var mh: int = int(hc.max_health) if "max_health" in hc else 0
	var ch: int = int(hc.current_health) if "current_health" in hc else 0
	if mh <= 0 or float(ch) / float(mh) > HP_THRESHOLD:
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
