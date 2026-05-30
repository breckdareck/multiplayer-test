extends Node

## Execution (passive, replaces the old primary-stat% auto-take) — CONDITIONAL
## damage: +bonus to enemies BELOW HP_THRESHOLD of their max HP. A finisher passive
## — useless on a fresh enemy, big on a wounded one. Higher magnitude than the
## opener passives since its window is small. Class-neutral. See AL_Aggression for
## the contract (returns the bonus FRACTION; combat applies 1 + total).

const HP_THRESHOLD: float = 0.30
const BONUS_AT_MAX: float = 0.45   # +45% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 10


func conditional_damage_mult(_owner: Node, target: Node, level: int) -> float:
	if not is_instance_valid(target):
		return 0.0
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc):
		return 0.0
	var mh: int = int(hc.max_health) if "max_health" in hc else 0
	var ch: int = int(hc.current_health) if "current_health" in hc else 0
	if mh <= 0 or float(ch) / float(mh) > HP_THRESHOLD:
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
