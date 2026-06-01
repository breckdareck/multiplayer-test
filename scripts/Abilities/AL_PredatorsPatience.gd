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
func conditional_damage_mult(owner_node: Node, _target: Node, level: int) -> float:
	if owner_node == null or not is_instance_valid(owner_node):
		return 0.0

	# Only fires on a from-stealth hit (the ambush). Otherwise this passive
	# is dormant — the normal combat hit doesn't benefit.
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

	# Time since the last ambush = Patience stacks. First-ever ambush (no
	# meta yet) gets MAX_STACKS — encourages opening with stealth.
	var now: int = Time.get_ticks_msec()
	var last: int = int(owner_node.get_meta(LAST_AMBUSH_META, -1))
	var stacks: float
	if last < 0:
		stacks = MAX_STACKS
	else:
		stacks = clampf(float(now - last) / 1000.0, 0.0, MAX_STACKS)
	if stacks <= 0.0:
		return 0.0
	return PATIENCE_PER_STACK * stacks * (float(level) / float(MAX_LEVEL))
