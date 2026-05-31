extends Node

## Toxicology (dagger passive) — CONDITIONAL damage: +bonus against POISONED
## targets. Twist the toxin — pairs with Envenom (which tags its victims with the
## "envenom_poison" meta). Class-neutral (stacks from both equipped weapon slots).
## See AL_Aggression for the contract (returns the bonus FRACTION; combat applies
## 1 + total).

const POISON_META: String = "envenom_poison"
const BONUS_AT_MAX: float = 0.30   # +30% at passive level 10 (scales linearly)
const MAX_LEVEL: int = 5
func conditional_damage_mult(_owner: Node, target: Node, level: int) -> float:
	if not is_instance_valid(target):
		return 0.0
	if not target.has_meta(POISON_META):
		return 0.0
	return BONUS_AT_MAX * (float(level) / float(MAX_LEVEL))
