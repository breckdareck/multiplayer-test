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
const DMG_BONUS_META: String = "mana_resonance_dmg"
const SPREAD_META: String = "mana_resonance_spread"
const SPREAD_RADIUS: float = 200.0

const DAMAGE_BONUS_PCT: float = 0.50  ## +50% damage to the spell that consumes
const REFUND_PCT: float = 0.50        ## refunds 50% of the consuming spell's MP


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Upgrade reads (Lingering +duration, Heavy Surge +damage, Cascading Surge =
	# spread-on-consume). Stamped into per-enemy metas so the static helpers read
	# the upgrade-scaled values id-free.
	var duration: float = MARK_DURATION
	var dmg_bonus: float = DAMAGE_BONUS_PCT
	var spread: int = 0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_duration")
		dmg_bonus += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_bonus")
		spread = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_spread"))

	# Apply (or refresh) the mark with an absolute expiry timestamp on the
	# server clock. Lazy expiry on read.
	var expire_at_ms: int = Time.get_ticks_msec() + int(duration * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)
	target.set_meta(DMG_BONUS_META, dmg_bonus)
	if spread > 0:
		target.set_meta(SPREAD_META, spread)


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
		if is_instance_valid(target) and target.has_meta(DMG_BONUS_META):
			return float(target.get_meta(DMG_BONUS_META))
		return DAMAGE_BONUS_PCT
	return 0.0


## Public helper for the ability system / mana component: called after a
## staff spell consumes the mark. Refunds half the caster's spell MP cost
## via the canonical ManaComponent.restore API, and clears the mark.
## Idempotent on an unmarked target (no refund, no clear).
static func consume_and_refund(caster: Node, target: Node, spell_mp_cost: float) -> void:
	if not is_marked(target):
		return
	# Cascading Surge (T3): on consume, spread the mark to a nearby enemy.
	if is_instance_valid(target) and target.has_meta(SPREAD_META):
		_spread_mark(target)
	target.remove_meta(MARK_META)
	if caster == null or not is_instance_valid(caster):
		return
	var mana_comp = caster.get("mana_component")
	if mana_comp == null or not is_instance_valid(mana_comp):
		return
	# Surging Refund (T2): increases the refund fraction. bonus_refund_pct is
	# unique to this ability, so get_total is unambiguous.
	var refund_pct: float = REFUND_PCT
	var ac = caster.get("ability_component")
	if ac and ac.has_method("get_total_upgrade_magnitude"):
		refund_pct += ac.get_total_upgrade_magnitude("bonus_refund_pct")
	var refund: int = int(spell_mp_cost * refund_pct)
	# ManaComponent's current_mana setter clamps to [0, max_mana] and emits
	# the changed signal; regain_mana wraps the same behavior with
	# attribution. Prefer regain_mana when present, fall back to direct set.
	if mana_comp.has_method("regain_mana"):
		mana_comp.regain_mana(refund, caster)
	elif "current_mana" in mana_comp:
		mana_comp.current_mana += refund


## Cascading Surge (T3): transfer the mark (with its stamped damage bonus) to the
## nearest living, unmarked enemy when the original is consumed.
static func _spread_mark(origin: Node) -> void:
	var remaining: int = int(origin.get_meta(SPREAD_META))
	if remaining <= 0:
		return
	var dmg_bonus: float = float(origin.get_meta(DMG_BONUS_META)) if origin.has_meta(DMG_BONUS_META) else DAMAGE_BONUS_PCT
	var origin_pos: Vector2 = origin.global_position
	var best: Node = null
	var best_d: float = SPREAD_RADIUS
	for e in origin.get_tree().get_nodes_in_group("Enemies"):
		if e == origin or not (e is EnemyBase) or not is_instance_valid(e):
			continue
		if e.has_meta(MARK_META):
			continue
		var hc = e.get("health_component")
		if hc != null and is_instance_valid(hc) and hc.is_dead:
			continue
		var d: float = origin_pos.distance_to(e.global_position)
		if d <= best_d:
			best = e
			best_d = d
	if best != null:
		best.set_meta(MARK_META, Time.get_ticks_msec() + int(MARK_DURATION * 1000.0))
		best.set_meta(DMG_BONUS_META, dmg_bonus)
		if remaining - 1 > 0:
			best.set_meta(SPREAD_META, remaining - 1)
