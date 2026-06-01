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
## Stamped per-enemy at mark time so the static damage/spread helpers read the
## upgrade-scaled values without an ability_id.
const DMG_BONUS_META: String = "sentinels_mark_dmg"
const REFUND_META: String = "sentinels_mark_refund"
const SPREAD_META: String = "sentinels_mark_spread"
const SPREAD_RADIUS: float = 200.0

## Damage bonus + refund chance scale with the ability's level, then upgrades add
## on top. on_hit stamps the level-scaled values into per-enemy metas so the static
## damage/refund helpers read them id-free. The MIN/MAX consts are fallback only —
## the live values come from the .tres custom_value_formulas ("mark_damage" 20→30,
## "refund_chance" 15→25), the same formulas the $[value:...] description
## placeholders read, so the tooltip and the applied bonus can never drift.
const DAMAGE_BONUS_MIN: float = 0.20   ## +20% damage at level 1
const DAMAGE_BONUS_MAX: float = 0.30   ## +30% damage at max level
const REFUND_CHANCE_MIN: float = 0.15  ## 15% refund at level 1
const REFUND_CHANCE_MAX: float = 0.25  ## 25% refund at max level
## Back-compat fallbacks for the static helpers when no meta is stamped.
const DAMAGE_BONUS_PCT: float = 0.30
const REFUND_CHANCE: float = 0.25


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Level-scaled base values read from the shared .tres formulas (display % → /100),
	# then upgrades add on top.
	var lvl: int = 1
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_level"):
		lvl = ability_comp.get_ability_level(_ability.ability_id)
	var duration: float = MARK_DURATION
	var dmg_bonus: float = DAMAGE_BONUS_MAX
	var refund: float = REFUND_CHANCE_MAX
	if _ability != null:
		dmg_bonus = _ability.get_custom_value("mark_damage", lvl, DAMAGE_BONUS_MAX * 100.0) / 100.0
		refund = _ability.get_custom_value("refund_chance", lvl, REFUND_CHANCE_MAX * 100.0) / 100.0
	var spread: int = 0
	# Upgrade reads (Extended Mark +duration, Sharper/Punishing Mark +damage,
	# Generous Mark +refund, Echoing Mark = on-death spread).
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_duration")
		dmg_bonus += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_damage")
		refund += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_refund_chance")
		spread = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_spread"))

	# Apply (or refresh) the mark with an absolute server-clock expiry.
	var expire_at_ms: int = Time.get_ticks_msec() + int(duration * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)
	target.set_meta(DMG_BONUS_META, dmg_bonus)
	target.set_meta(REFUND_META, refund)
	if spread > 0:
		target.set_meta(SPREAD_META, spread)


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
		if is_instance_valid(target) and target.has_meta(DMG_BONUS_META):
			return float(target.get_meta(DMG_BONUS_META))
		return DAMAGE_BONUS_PCT
	return 0.0


## Echoing Mark (T3): when the marked target dies, transfer the mark (with its
## stamped damage bonus) to the nearest living enemy. Called from combat.gd's
## kill block; no-op unless the dying enemy carries SPREAD_META.
static func spread_on_death(died_enemy: Node) -> void:
	if not is_instance_valid(died_enemy) or not died_enemy.has_meta(SPREAD_META):
		return
	var remaining: int = int(died_enemy.get_meta(SPREAD_META))
	if remaining <= 0:
		return
	var dmg_bonus: float = float(died_enemy.get_meta(DMG_BONUS_META)) if died_enemy.has_meta(DMG_BONUS_META) else DAMAGE_BONUS_PCT
	var origin: Vector2 = died_enemy.global_position
	var best: Node = null
	var best_d: float = SPREAD_RADIUS
	for e in died_enemy.get_tree().get_nodes_in_group("Enemies"):
		if e == died_enemy or not (e is EnemyBase) or not is_instance_valid(e):
			continue
		if e.has_meta(MARK_META):
			continue
		var hc = e.get("health_component")
		if hc != null and is_instance_valid(hc) and hc.is_dead:
			continue
		var d: float = origin.distance_to(e.global_position)
		if d <= best_d:
			best = e
			best_d = d
	if best != null:
		best.set_meta(MARK_META, Time.get_ticks_msec() + int(MARK_DURATION * 1000.0))
		best.set_meta(DMG_BONUS_META, dmg_bonus)
		if remaining - 1 > 0:
			best.set_meta(SPREAD_META, remaining - 1)


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
	# The level-scaled refund chance (+ Generous Mark T3) was stamped on the
	# target at mark time; fall back to the base constant if absent.
	var chance: float = REFUND_CHANCE
	if is_instance_valid(target) and target.has_meta(REFUND_META):
		chance = float(target.get_meta(REFUND_META))
	if randf() > chance:
		return
	var combo_comp = attacker.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp) or not combo_comp.has_method("add_combo_point"):
		return
	combo_comp.add_combo_point()
