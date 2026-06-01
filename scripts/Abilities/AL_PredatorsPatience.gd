extends Node

## Predator's Patience (dagger passive) — CONDITIONAL ambush bonus.
## Each second the wielder spends OUT OF STEALTH since their last ambush
## builds 1 stack of Patience (max 10). The NEXT ambush hit (the one that
## breaks stealth) gains +PATIENCE_PER_STACK% damage per stack — up to
## +30% at 10 stacks × max passive level.
##
## Directly fixes the kite-stealth-spam failure mode: the optimal pattern
## becomes "fight out of stealth → build Patience → re-stealth → ambush
## with extra damage" rather than "stealth → ambush → wait → repeat." The
## passive rewards combat between stealths, not avoiding combat.
##
## Implementation: tracks Patience via a meta on the dagger user holding the
## server-clock millisecond of the last ambush. On each ambush, computes
## stacks as `(now - last_ambush_ms) / 1000`, capped at MAX_STACKS, and
## returns the bonus. ShadowmeldComponent emits `shadowmeld_changed`; a
## listener on enter-stealth resets the timer to "now" so re-entering
## stealth without an ambush doesn't credit Patience to that re-entry.
##
## For v1 we use a SIMPLER variant: just measure time since LAST ambush
## using a meta updated by combat.gd's ambush-mult path. Time since the
## last ambush ≈ time-out-of-stealth in most rotations (since the only
## way to leave the cooldown is to break stealth via attack).

const PATIENCE_PER_STACK: float = 0.03   # +3% per stack at max level
const MAX_STACKS: float = 10.0           # cap at 10 stacks = +30%
const MAX_LEVEL: int = 5

const LAST_AMBUSH_META: String = "predators_patience_last_ambush_ms"


## Called by combat.gd when an ambush hit (Shadowmeld ×2 hit) lands.
## Stamps the current time so the next ambush's stack count starts from
## now. Idempotent / safe on non-dagger builds.
static func record_ambush(owner_node: Node) -> void:
	if owner_node == null or not is_instance_valid(owner_node):
		return
	owner_node.set_meta(LAST_AMBUSH_META, Time.get_ticks_msec())


## Conditional damage bonus on the ambush hit — only returns a positive
## value when the wielder is currently stealthed (i.e. the hit that's
## about to land IS the ambush). Mirrors AL_Opportunist's stealth check
## but with a time-since-last-ambush ramp on top.
##
## See AL_Aggression for the conditional_damage_mult contract.
## 5-arg form: the dispatcher passes this passive's OWN ability_id so it can read
## its own upgrades (potency / cap / carryover). cast_ability is unused here.
func conditional_damage_mult(owner_node: Node, _target: Node, level: int, _cast_ability: AbilityData = null, passive_id: String = "") -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0

	# Per-stack bonus at max level — read from the shared .tres formula
	# ("per_stack", display % at max_level) so it matches the $[value:per_stack]
	# tooltip; the * (level / MAX_LEVEL) below applies the per-level ramp.
	var per_stack: float = PATIENCE_PER_STACK
	var self_data: AbilityData = ResourceManager.get_ability_data(passive_id) if passive_id != "" else null
	if self_data:
		per_stack = self_data.get_custom_value("per_stack", MAX_LEVEL, PATIENCE_PER_STACK * 100.0) / 100.0
	var max_stacks: float = MAX_STACKS
	var carryover_s: float = 0.0
	var ac = owner_node.get("ability_component")
	if ac and passive_id != "" and ac.has_method("get_ability_upgrade_magnitude"):
		per_stack += ac.get_ability_upgrade_magnitude(passive_id, "bonus_passive_potency")
		max_stacks += ac.get_ability_upgrade_magnitude(passive_id, "bonus_passive_cap")
		carryover_s = ac.get_ability_upgrade_magnitude(passive_id, "bonus_carryover")

	# Fires on a from-stealth hit (the ambush). Eternal Patience (T3) extends a
	# grace window after the ambush during which non-stealth hits still benefit.
	var stealthed: bool = false
	var sm = owner_node.get("shadowmeld_component")
	if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
		stealthed = sm.is_stealthed()
	if not stealthed:
		var bc = owner_node.get("buff_component")
		if bc != null and is_instance_valid(bc) and bc.has_method("has_buff"):
			stealthed = bc.has_buff("Vanish")
	if not stealthed:
		# Carryover window: still active for `carryover_s` after the last ambush.
		if carryover_s <= 0.0:
			return 0.0
		var last_amb: int = int(owner_node.get_meta(LAST_AMBUSH_META, -1))
		if last_amb < 0 or (Time.get_ticks_msec() - last_amb) > int(carryover_s * 1000.0):
			return 0.0

	# Time since the last ambush = Patience stacks. First-ever ambush (no
	# meta yet) gets MAX_STACKS — encourages opening with stealth.
	var now: int = Time.get_ticks_msec()
	var last: int = int(owner_node.get_meta(LAST_AMBUSH_META, -1))
	var stacks: float
	if last < 0:
		stacks = max_stacks
	else:
		stacks = clampf(float(now - last) / 1000.0, 0.0, max_stacks)
	if stacks <= 0.0:
		return 0.0
	return per_stack * stacks * (float(level) / float(MAX_LEVEL))


## Current Patience stack count (time since last ambush, capped at the effective
## cap including bonus_passive_cap). Shared by the crit/lifesteal helpers.
static func _current_stacks(owner_node: Node) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var cap: float = MAX_STACKS
	var ac = owner_node.get("ability_component")
	if ac and ac.has_method("get_total_upgrade_magnitude"):
		cap += ac.get_total_upgrade_magnitude("bonus_passive_cap")
	var last: int = int(owner_node.get_meta(LAST_AMBUSH_META, -1))
	if last < 0:
		return cap
	return clampf(float(Time.get_ticks_msec() - last) / 1000.0, 0.0, cap)


## Killer Patience (T3): +crit chance (percentage points) per Patience stack.
## bonus_crit_per_stack is unique to this ability, so get_total is unambiguous.
## Returns 0.0 if the upgrade isn't owned. Called from combat.gd's crit roll.
static func get_crit_bonus(owner_node: Node) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var ac = owner_node.get("ability_component")
	if ac == null or not ac.has_method("get_total_upgrade_magnitude"):
		return 0.0
	var per_stack: float = ac.get_total_upgrade_magnitude("bonus_crit_per_stack")
	if per_stack <= 0.0:
		return 0.0
	# magnitude 0.01 = +1% per stack; crit_chance is in percentage points.
	return per_stack * _current_stacks(owner_node) * 100.0


## Lifesteal Patience (T3): heal fraction of damage dealt when an ambush lands at
## FULL Patience. Returns 0.0 unless owned + at max stacks. Called post-hit.
static func get_lifesteal_at_max(owner_node: Node) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0
	var ac = owner_node.get("ability_component")
	if ac == null or not ac.has_method("get_total_upgrade_magnitude"):
		return 0.0
	var ls: float = ac.get_total_upgrade_magnitude("bonus_lifesteal_at_max")
	if ls <= 0.0:
		return 0.0
	var cap: float = MAX_STACKS + ac.get_total_upgrade_magnitude("bonus_passive_cap")
	if _current_stacks(owner_node) >= cap:
		return ls
	return 0.0
