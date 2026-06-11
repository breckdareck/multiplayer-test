extends Node

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## Hemomancy (staff passive) — CONDITIONAL damage: +bonus against BLEEDING
## targets. Spilled blood feeds the spell — reads the bleed STATUS TAG
## (ADR 0013), so ANY bleed source qualifies: a sword partner's Hemorrhage,
## a bow's Barbed Shot, a dagger's Bleeding Mark, a party member's. Staff
## applies no bleed itself — this is a deliberate cross-discipline consumer
## (the tag-consumer economy). Class-neutral (stacks from both equipped
## weapon slots). See AL_Aggression for the contract (returns the bonus
## FRACTION; combat applies 1 + total).

const BONUS_AT_MAX: float = 0.30   # +30% at passive level 5 (scales linearly)
const MAX_LEVEL: int = 5
func conditional_damage_mult(_owner: Node, target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if not is_instance_valid(target):
		return 0.0
	if not EnemyStatus.has_tag(target, EnemyStatus.TAG_BLEED):
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
