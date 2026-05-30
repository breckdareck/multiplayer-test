extends Node

## Opportunist (dagger passive) — CONDITIONAL damage: +bonus while the ATTACKER is
## in stealth (the Shadowmeld toggle OR the Vanish buff). Strike from the dark —
## rewards opening from stealth. The stealth check mirrors AL_Eviscerate. Class-
## neutral (stacks from both equipped weapon slots). See AL_Aggression for the
## contract (returns the bonus FRACTION; combat applies 1 + total).

const BONUS_AT_MAX: float = 0.35   # +35% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 10


func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0

	# Must be in stealth — Shadowmeld toggle or the Vanish ability's buff
	# (same check AL_Eviscerate uses for its from-stealth execute).
	var stealthed: bool = false
	var sm = owner_node.get("shadowmeld_component")
	if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
		stealthed = sm.is_stealthed()
	if not stealthed:
		var bc = owner_node.get("buff_component")
		if bc != null and is_instance_valid(bc) and bc.has_method("has_buff"):
			stealthed = bc.has_buff("Vanish")
	if not stealthed:
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
