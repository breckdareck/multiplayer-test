extends Node

## Tailwind (bow passive) — CONDITIONAL damage: +bonus scaled by the attacker's
## current Momentum stacks. Ride the rhythm — pays off the bow's ramp: at full
## Momentum (MAX_STACKS) and max passive level it grants BONUS_AT_MAX. Returns 0
## when no Momentum component (non-bow). Class-neutral (stacks from both equipped
## weapon slots). See AL_Aggression for the contract (returns the bonus FRACTION;
## combat applies 1 + total).

const BONUS_AT_MAX: float = 0.30   # +30% at full Momentum (10 stacks) + level 10
const MAX_LEVEL: int = 5
const MAX_STACKS: float = 10.0     # mirrors BowMomentumComponent.MAX_STACKS


func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("get_stacks"):
		return 0.0
	var stacks: float = float(bm.get_stacks())
	return BONUS_AT_MAX * (stacks / MAX_STACKS) * (float(level) / float(MAX_LEVEL))
