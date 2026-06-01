extends Node

## Mana Surge (staff active) — MARK + PAYOFF (MP-refund). Tags one enemy with
## a Mana Resonance for 8 seconds. The next damaging staff spell cast against
## the marked target deals +DAMAGE_BONUS_PCT AND refunds REFUND_PCT of its
## MP cost on cast. The mark is consumed by the bonus spell.
##
## Adds the missing mark+payoff shape to staff with an MP-economy twist
## (other weapons' marks are crit / combo / damage-themed; staff's is
## resource-themed). Pairs naturally with the big-cost spells:
##   - Mana Surge + Spellweave: a Spellweave's amplified version refunds
##     half the channel cost
##   - Mana Surge + Stormcall: a Stormcall channel pays itself back enough
##     to keep going through low-mana stretches
## So Mana Surge isn't just damage — it's how a staff build sustains
## high-MP rotations.

const MARK_DURATION: float = 8.0
const MARK_META: String = "mana_resonance_remaining"

const DAMAGE_BONUS_PCT: float = 0.50  ## +50% damage to the spell that consumes
const REFUND_PCT: float = 0.50        ## refunds 50% of the consuming spell's MP


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Apply (or refresh) the mark with an absolute expiry timestamp on the
	# server clock. Lazy expiry on read.
	var expire_at_ms: int = Time.get_ticks_msec() + int(MARK_DURATION * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)


## Public helper for CombatComponent: returns true iff the target carries an
## unexpired Mana Resonance mark. Lazy expiry on read.
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


## Public helper for CombatComponent: returns the bonus damage fraction (0.50
## while marked, 0.0 otherwise). Additive to the spell's normal damage.
static func get_damage_bonus(target: Node) -> float:
	if is_marked(target):
		return DAMAGE_BONUS_PCT
	return 0.0


## Public helper for the ability system / mana component: called after a
## staff spell consumes the mark. Refunds half the caster's spell MP cost
## via the canonical ManaComponent.restore API, and clears the mark.
## Idempotent on an unmarked target (no refund, no clear).
static func consume_and_refund(caster: Node, target: Node, spell_mp_cost: float) -> void:
	if not is_marked(target):
		return
	target.remove_meta(MARK_META)
	if caster == null or not is_instance_valid(caster):
		return
	var mana_comp = caster.get("mana_component")
	if mana_comp == null or not is_instance_valid(mana_comp):
		return
	var refund: int = int(spell_mp_cost * REFUND_PCT)
	# ManaComponent's current_mana setter clamps to [0, max_mana] and emits
	# the changed signal; regain_mana wraps the same behavior with
	# attribution. Prefer regain_mana when present, fall back to direct set.
	if mana_comp.has_method("regain_mana"):
		mana_comp.regain_mana(refund, caster)
	elif "current_mana" in mana_comp:
		mana_comp.current_mana += refund
