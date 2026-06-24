extends Node

const MapScope := preload("res://scripts/Gameplay/map_scope.gd")

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

const MARK_DURATION: float = 15.0
const MARK_META: String = "death_mark_remaining"
## Per-enemy metas carrying the upgrade-scaled values, stamped at mark time so the
## static crit/spread helpers (and combat.gd) read them without an ability_id.
const CRIT_BONUS_META: String = "death_mark_crit_bonus"
const SPREAD_META: String = "death_mark_spread"
const SPREAD_RADIUS: float = 200.0

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

	# Upgrade reads (Lingering Mark +duration, Killing Mark +crit potency,
	# Spreading Mark = on-death spread, Double Mark = +N marks on cast,
	# Bleeding Mark = bleed DOT on the marked target). Stamped into per-enemy
	# metas so the static helpers + combat.gd kill path read them id-free.
	var duration: float = MARK_DURATION
	var crit_bonus: float = CRIT_CHANCE_BONUS
	var spread: int = 0
	var extra_targets: int = 0
	var bleed_pct: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_duration")
		crit_bonus += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_potency")
		spread = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_spread"))
		extra_targets = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_targets"))
		bleed_pct = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_bleed_dot")

	# Bleeding Mark (T3) scales its bleed off the ability's max hit (stat-scaled,
	# like the other DoTs — project_dot_scaling_divergence). Death Mark authors no
	# damage formula, so dot_scaling_base falls back to max_range. Computed once.
	var dot_base: int = 0
	if bleed_pct > 0.0:
		var combat = owner_node.get("combat_component")
		if combat != null and combat.has_method("dot_scaling_base"):
			dot_base = combat.dot_scaling_base(_ability)

	# Mark the primary target, then (Double Mark) the nearest extra enemies.
	_apply_mark(owner_node, target, duration, crit_bonus, spread, bleed_pct, dot_base)
	if extra_targets > 0:
		for other in _nearby_enemies(target, SPREAD_RADIUS, extra_targets):
			_apply_mark(owner_node, other, duration, crit_bonus, spread, bleed_pct, dot_base)


## Stamp the Death Mark (+ its T3 riders) onto one enemy. Reading an absolute
## server-clock deadline is simpler than a per-mark Timer and survives the enemy
## being engaged by other players. Bleeding Mark adds a light bleed (% of
## WEAPONATTACK/sec) for the mark's lifetime.
func _apply_mark(owner_node: Node, target: Node, duration: float, crit_bonus: float, spread: int, bleed_pct: float, dot_base: int = 0) -> void:
	if not is_instance_valid(target):
		return
	var expire_at_ms: int = Time.get_ticks_msec() + int(duration * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)
	# Juice: marks never tick, so a marked enemy was invisible — name it.
	EventJuice.proc(target, "MARKED", EventJuice.COLOR_AMBUSH, "res://assets/sounds/generated/mark_ping.wav", "dark_impact")
	target.set_meta(CRIT_BONUS_META, crit_bonus)
	if spread > 0:
		target.set_meta(SPREAD_META, spread)
	if bleed_pct > 0.0 and dot_base > 0:
		var per_tick: int = maxi(1, roundi(dot_base * bleed_pct))
		# Runtime load() (not the BleedDot global) — combat.gd hard-preloads
		# AL_DeathMark, so a compile-time class ref here would form a cycle.
		load("res://scripts/Gameplay/bleed_dot.gd").apply(target, owner_node, per_tick, 1, duration, "death_mark_bleed", "bleed")


## Up to `count` nearest valid living enemies within `radius` of `origin`
## (excluding `origin`). Mirrors the proximity model the other mark spreads use.
func _nearby_enemies(origin: Node, radius: float, count: int) -> Array:
	var out: Array = []
	if not is_instance_valid(origin):
		return out
	var origin_pos: Vector2 = origin.global_position
	var origin_map: Node = MapScope.map_of(origin)
	var candidates: Array = []
	for e in origin.get_tree().get_nodes_in_group("Enemies"):
		if e == origin or not (e is EnemyBase) or not is_instance_valid(e):
			continue
		if not MapScope.contains(origin_map, e):
			continue  # different map — skip (global group)
		var hc = e.get("health_component")
		if hc != null and is_instance_valid(hc) and hc.is_dead:
			continue
		var d: float = origin_pos.distance_to(e.global_position)
		if d <= radius:
			candidates.append({"e": e, "d": d})
	candidates.sort_custom(func(a, b): return a.d < b.d)
	for i in range(mini(count, candidates.size())):
		out.append(candidates[i].e)
	return out


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
		if is_instance_valid(target) and target.has_meta(CRIT_BONUS_META):
			return float(target.get_meta(CRIT_BONUS_META))
		return CRIT_CHANCE_BONUS
	return 0.0


## Spreading Mark (T3): when a marked target dies, transfer the mark (with its
## stamped crit bonus) to the nearest living enemy. Called from combat.gd's kill
## block when the dying enemy carries SPREAD_META. Each spread decrements the
## count so the chain is bounded.
static func spread_on_death(died_enemy: Node) -> void:
	if not is_instance_valid(died_enemy) or not died_enemy.has_meta(SPREAD_META):
		return
	var remaining: int = int(died_enemy.get_meta(SPREAD_META))
	if remaining <= 0:
		return
	var crit_bonus: float = float(died_enemy.get_meta(CRIT_BONUS_META)) if died_enemy.has_meta(CRIT_BONUS_META) else CRIT_CHANCE_BONUS
	var origin: Vector2 = died_enemy.global_position
	var origin_map: Node = MapScope.map_of(died_enemy)
	var best: Node = null
	var best_d: float = SPREAD_RADIUS
	for e in died_enemy.get_tree().get_nodes_in_group("Enemies"):
		if e == died_enemy or not (e is EnemyBase) or not is_instance_valid(e):
			continue
		if not MapScope.contains(origin_map, e):
			continue  # different map — skip (global group)
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
		best.set_meta(CRIT_BONUS_META, crit_bonus)
		if remaining - 1 > 0:
			best.set_meta(SPREAD_META, remaining - 1)
