extends Node

## Last Stand (sword passive) — CONDITIONAL damage: +bonus while the ATTACKER is
## BELOW HP_THRESHOLD of their own max HP. The cornered-warrior's resolve — the
## inverse of Composure (which rewards staying topped up). Rewards diving in and
## fighting hurt; dead weight while you're healthy. Class-neutral (stacks from
## both equipped weapon slots). See AL_Aggression for the contract (returns the
## bonus FRACTION; combat applies 1 + total).

const HP_THRESHOLD: float = 0.35
const BONUS_AT_MAX: float = 0.35   # +35% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 10


func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var hc = owner_node.get("health_component")
	if hc == null or not is_instance_valid(hc):
		return 0.0
	var mh: int = int(hc.max_health) if "max_health" in hc else 0
	var ch: int = int(hc.current_health) if "current_health" in hc else 0
	if mh <= 0 or float(ch) / float(mh) >= HP_THRESHOLD:
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
