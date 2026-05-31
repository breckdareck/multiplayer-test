extends Node

## Aggression (passive, replaces the old primary-stat% auto-take) — CONDITIONAL
## damage: +bonus to enemies ABOVE HP_THRESHOLD of their max HP. An opener/burst
## passive — strong on fresh targets, fades as you whittle them down. Class-neutral
## (stacks from both equipped weapon slots). Queried per hit by combat._execute_hit
## via AbilityComponent.get_conditional_damage_modifier. Returns the bonus FRACTION
## (combat sums all conditional passives and applies 1 + total).

const HP_THRESHOLD: float = 0.90
const BONUS_AT_MAX: float = 0.30   # +30% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 5
func conditional_damage_mult(_owner: Node, target: Node, level: int) -> float:
	if not is_instance_valid(target):
		return 0.0
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc):
		return 0.0
	var mh: int = int(hc.max_health) if "max_health" in hc else 0
	var ch: int = int(hc.current_health) if "current_health" in hc else 0
	if mh <= 0 or float(ch) / float(mh) < HP_THRESHOLD:
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
