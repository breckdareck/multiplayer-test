extends Node

## Death Mark (dagger active) — MARK + PAYOFF (crit theme). Tags one enemy
## with a Death Mark for 8 seconds. While the mark is active, every dagger
## hit against the marked target gains a flat +CRIT_CHANCE_BONUS to its
## roll. The mark itself does no damage on cast — it's pure setup.
##
## Distinct from Envenom / Toxicology (the poison mark+payoff chain):
##   - Envenom builds Poison stacks → Toxicology PASSIVELY buffs vs Poisoned
##   - Death Mark applies Mark → boosts crit RATE actively against marked
## So a Dagger build that runs both gets stacking value: Envenom stacks for
## the +30% Toxicology damage, AND Death Mark for the +crit-chance — a
## marked-and-poisoned target is the assassin's ideal kill.
##
## The mark is stored as a per-enemy meta (`death_mark_remaining`) holding
## the absolute server-clock expiry time. CombatComponent.has_crit_bonus()
## reads this on every dagger hit and adds the bonus to the crit roll.

const MARK_DURATION: float = 8.0
const MARK_META: String = "death_mark_remaining"

## Crit-chance bonus while target is marked. Adds to the player's base
## CRITCHANCE on the roll (additive). +25% is meaningful but not auto-crit.
const CRIT_CHANCE_BONUS: float = 25.0


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Apply (or refresh) the mark with an absolute expiry timestamp on the
	# server clock. Reading the absolute deadline is simpler than a separate
	# Timer per mark and survives the enemy being engaged by other players.
	var expire_at_ms: int = Time.get_ticks_msec() + int(MARK_DURATION * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)


## Public helper for CombatComponent: returns true iff the target currently
## carries an unexpired Death Mark. Hot-path so we expire lazily on read
## (no per-mark Timer to schedule, cancel, or clean up).
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


## Public helper for CombatComponent: returns the crit-chance bonus the mark
## grants if the target is marked, or 0.0 otherwise. CombatComponent adds
## this to the base CRITCHANCE before rolling crits on a dagger hit.
static func get_crit_bonus(target: Node) -> float:
	if is_marked(target):
		return CRIT_CHANCE_BONUS
	return 0.0
