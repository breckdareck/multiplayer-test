extends Node

## Vanguard's Resolve (sword passive) — CONDITIONAL damage REDUCTION:
## while the wielder has 1+ combo points, incoming damage is reduced. The
## reduction scales with combo stacks: -8% at 1 combo, -12% at 2 combo,
## -16% at 3 combo (linear scaling × passive level). Rewards building combo
## even before you can spend it — the gauge becomes a defensive lever.
##
## This is sword's first gauge-engaging passive. Pairs naturally with the
## existing combo builders (Steel Flurry / Vault Strike / Charge!) so a
## sword build that hits its first combo gets immediate sustain benefit.
##
## Implementation: defines an `incoming_damage_mult(owner, source, level)`
## hook that combat.gd reads on damage-taken to scale the incoming amount.
## Returns a NEGATIVE fraction (e.g. -0.16) which combat applies as
## (1.0 + that_fraction). Class-neutral (stacks from both equipped weapon
## slots).

const REDUCTION_PER_COMBO: float = 0.08   # -8% per combo stack at max level
const MAX_LEVEL: int = 5
const MAX_COMBO: float = 3.0


## Returns a NEGATIVE fraction representing the percentage damage reduction
## from this passive (e.g. -0.16 = -16% incoming damage). combat.gd's
## damage-taken path applies this as (1.0 + total_reduction) on the final
## damage before HP deduction.
##
## Reads the current sword combo stacks; if no SwordComboComponent (a
## non-sword build with this passive equipped from a sword off-hand),
## returns 0.0.
func conditional_damage_taken_mult(owner_node: Node, _source: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var combo_comp = owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp) or not combo_comp.has_method("get_combo_count"):
		return 0.0
	var combo: float = clampf(float(combo_comp.get_combo_count()), 0.0, MAX_COMBO)
	if combo <= 0.0:
		return 0.0
	# Linear scaling with combo AND with passive level.
	return -REDUCTION_PER_COMBO * combo * (float(level) / float(MAX_LEVEL))
