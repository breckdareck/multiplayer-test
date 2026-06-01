extends Node

## Wind Rider (bow passive) — CONDITIONAL fire-rate buff: reduces basic-
## attack delay scaling with current Bow Momentum stacks. Each stack reduces
## the basic-attack cooldown by 2.5% (max -25% at 10 stacks × max passive
## level). Different axis from Tailwind:
##   - Tailwind: +damage AT FULL Momentum (payoff at cap)
##   - Wind Rider: +fire-rate THROUGHOUT the build (smooth ramp)
## So a Momentum-heavy bow build gets BOTH a damage boost at cap and a
## smoother fire-rate ramp during the build — they don't overlap.
##
## Implementation: defines an `attack_cooldown_mult(owner, level)` hook
## that combat.gd reads when computing basic-attack cooldown. Returns a
## NEGATIVE fraction (e.g. -0.25) which combat applies as
## (1.0 + that_fraction) to scale the cooldown DOWN. Class-neutral
## (stacks from both equipped weapon slots).

const REDUCTION_PER_STACK: float = 0.025   # -2.5% per Momentum stack at max level
const MAX_LEVEL: int = 5
const MAX_STACKS: float = 10.0


## Returns a NEGATIVE fraction representing the basic-attack cooldown
## reduction this passive grants (e.g. -0.25 = -25% delay). combat.gd's
## basic-attack-cooldown path applies as (1.0 + total_reduction) on the
## cooldown value before scheduling the next attack.
##
## Reads the current Bow Momentum stacks; returns 0.0 on a non-bow build.
func attack_cooldown_mult(owner_node: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("get_stacks"):
		return 0.0
	var stacks: float = clampf(float(bm.get_stacks()), 0.0, MAX_STACKS)
	if stacks <= 0.0:
		return 0.0
	return -REDUCTION_PER_STACK * stacks * (float(level) / float(MAX_LEVEL))
