extends Node

## Sentinel's Mark (sword active) — MARK + PAYOFF (combo-refund). Tags one
## enemy with a Sentinel's Mark for 8 seconds. While the mark is active,
## every sword hit on the marked target deals +DAMAGE_BONUS_PCT and has a
## REFUND_CHANCE chance to refund 1 combo point.
##
## Adds the missing mark+payoff shape to sword AND weaves it into the
## combo mesh — instead of standing alone like Hemorrhage's bleed (which
## ticks but has no consumer), the mark loops back into Steel Flurry /
## Vault Strike / Crescent Cleave / Sundering Blow / Earthsplitter via
## the small combo refund. A marked target lets you sustain combo longer
## without dropping below the spender threshold.
##
## Lazy expiry on read; CombatComponent calls `is_marked` on every sword
## hit. The damage bonus and refund roll are applied per landed hit
## (combat.gd's per-hit pipeline), so on_hit fires for each pierced /
## flurried enemy that's marked.

const MARK_DURATION: float = 8.0
const MARK_META: String = "sentinels_mark_remaining"

const DAMAGE_BONUS_PCT: float = 0.30   ## +30% damage to sword hits on marked
const REFUND_CHANCE: float = 0.25      ## 25% chance per hit to refund 1 combo


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Apply (or refresh) the mark with an absolute server-clock expiry.
	var expire_at_ms: int = Time.get_ticks_msec() + int(MARK_DURATION * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)


## Public helper for CombatComponent: returns true iff the target carries
## an unexpired Sentinel's Mark. Lazy expiry on read.
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


## Public helper for CombatComponent: returns the additive damage multiplier
## while the target is marked (0.30 = +30%). Returns 0.0 otherwise.
static func get_damage_bonus(target: Node) -> float:
	if is_marked(target):
		return DAMAGE_BONUS_PCT
	return 0.0


## Public helper for CombatComponent: called after a sword hit on a marked
## target lands. Rolls REFUND_CHANCE; if it hits, adds 1 combo to the
## attacker via the canonical SwordComboComponent.add_combo path. Idempotent
## on an unmarked target (no roll fires).
##
## Uses an injectable RNG so combat.gd can pass its own RandomNumberGenerator
## if it wants determinism in tests; falls back to a fresh randf() otherwise.
static func roll_refund(attacker: Node, target: Node) -> void:
	if not is_marked(target):
		return
	if attacker == null or not is_instance_valid(attacker):
		return
	if randf() > REFUND_CHANCE:
		return
	var combo_comp = attacker.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp) or not combo_comp.has_method("add_combo"):
		return
	combo_comp.add_combo(1)
