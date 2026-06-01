extends Node

## Mark of the Hunt (bow active) — MARK + PAYOFF (auto-crit-next-spender).
## Tags one enemy with a Hunter's Mark for 8 seconds. While the mark is
## active, the NEXT momentum-spender cast against the marked target is an
## AUTO-CRIT (100% crit chance for the roll). The mark is consumed by the
## crit, so to chain crits you re-apply.
##
## Pairs naturally with both bow spenders:
##   - Snipe vs marked: big single-target auto-crit burst
##   - Sundering Arrow vs marked: pierce-line opener with guaranteed crit
##     on the marked target (other pierced enemies roll normally)
##
## Implementation: the mark is a per-enemy meta (`hunters_mark_remaining`)
## holding an absolute server-clock expiry. CombatComponent's crit-roll
## path reads `is_marked(target)` and forces the crit on a momentum-spender
## hit, then clears the mark. Lazy expiry on read — no per-mark Timer.

const MARK_DURATION: float = 8.0
const MARK_META: String = "hunters_mark_remaining"


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Apply (or refresh) the mark with an absolute expiry timestamp on the
	# server clock. Lazy expiry on read avoids any per-mark Timer plumbing.
	var expire_at_ms: int = Time.get_ticks_msec() + int(MARK_DURATION * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)


## Public helper for CombatComponent: returns true iff the target carries an
## unexpired Hunter's Mark. Expires lazily on read.
static func is_marked(target: Node) -> bool:
	if not is_instance_valid(target):
		return false
	if not target.has_meta(MARK_META):
		return false
	var expire_at: int = int(target.get_meta(MARK_META))
	if Time.get_ticks_msec() >= expire_at:
		target.remove_meta(MARK_META)
		return false
	return true


## Public helper for CombatComponent: consume the mark (call after the
## auto-crit hit lands). Idempotent — safe to call on an unmarked target.
static func consume_mark(target: Node) -> void:
	if is_instance_valid(target) and target.has_meta(MARK_META):
		target.remove_meta(MARK_META)
