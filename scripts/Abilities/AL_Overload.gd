extends Node

## Overload (staff passive) — CONDITIONAL damage: +bonus while the ATTACKER is
## ABOVE MANA_THRESHOLD of their max mana. Channel your reserves — strong while
## you're topped up on mana, falls off as you spend it. Class-neutral (stacks
## from both equipped weapon slots). See AL_Aggression for the contract (returns
## the bonus FRACTION; combat applies 1 + total).

const MANA_THRESHOLD: float = 0.50
const BONUS_AT_MAX: float = 0.25   # +25% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 10


func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var mc = owner_node.get("mana_component")
	if mc == null or not is_instance_valid(mc):
		return 0.0
	var mm: float = float(mc.max_mana) if "max_mana" in mc else 0.0
	var cm: float = float(mc.current_mana) if "current_mana" in mc else 0.0
	if mm <= 0.0 or cm / mm <= MANA_THRESHOLD:
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
