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
const CARRY_UNTIL_META: String = "vrs_carry_until_ms"
const CARRY_AMT_META: String = "vrs_carry_amt"


## 4-arg form: the dispatcher passes this passive's OWN ability_id so it can read
## its upgrades (Stalwart/Iron Resolve potency, Tenacious cap, Eternal carryover,
## Combat Resolve defense-at-full).
func conditional_damage_taken_mult(owner_node: Node, _source: Node, level: int, passive_id: String = "") -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0

	var per_combo: float = REDUCTION_PER_COMBO
	var max_combo: float = MAX_COMBO
	var carryover_s: float = 0.0
	var defense_at_full: float = 0.0
	var ac = owner_node.get("ability_component")
	if ac and passive_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
		per_combo += ac.get_ability_upgrade_magnitude(passive_id, "bonus_passive_potency")
		max_combo += ac.get_ability_upgrade_magnitude(passive_id, "bonus_resolve_cap")
		carryover_s = ac.get_ability_upgrade_magnitude(passive_id, "bonus_resolve_carryover")
		defense_at_full = ac.get_ability_upgrade_magnitude(passive_id, "bonus_defense_at_full")

	var combo: float = 0.0
	var combo_comp = owner_node.get("sword_combo_component")
	if combo_comp != null and is_instance_valid(combo_comp) and combo_comp.has_method("get_combo_count"):
		combo = clampf(float(combo_comp.get_combo_count()), 0.0, max_combo)

	if combo <= 0.0:
		# Eternal Resolve (T3): keep the last reduction for a grace window after
		# combo drops to 0.
		if carryover_s > 0.0 and owner_node.has_meta(CARRY_UNTIL_META):
			if Time.get_ticks_msec() < int(owner_node.get_meta(CARRY_UNTIL_META)):
				return -float(owner_node.get_meta(CARRY_AMT_META))
			owner_node.remove_meta(CARRY_UNTIL_META)
		return 0.0

	# Linear scaling with combo AND with passive level.
	var reduction: float = per_combo * combo * (float(level) / float(MAX_LEVEL))
	# Combat Resolve (T3): extra reduction at full combo, derived from the granted
	# defense via the game's own defense curve (def/(def+500)).
	if defense_at_full > 0.0 and combo >= max_combo:
		reduction += clampf(defense_at_full / (defense_at_full + 500.0), 0.0, 0.5)

	# Stamp for the carryover window (no-op if Eternal Resolve isn't owned).
	if carryover_s > 0.0:
		owner_node.set_meta(CARRY_UNTIL_META, Time.get_ticks_msec() + int(carryover_s * 1000.0))
		owner_node.set_meta(CARRY_AMT_META, reduction)
	return -reduction
