extends Node

const MapScope := preload("res://scripts/Gameplay/map_scope.gd")

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

const MARK_DURATION: float = 15.0
const MARK_META: String = "hunters_mark_remaining"
## Sundering Mark (T3): the marked target carries this flag so combat.gd, when it
## consumes the mark for an auto-crit, spreads the hunt to nearby enemies.
const SUNDER_META: String = "hunters_mark_sundering"
const BLEEDING_MARK_META: String = "hunters_mark_bleed"
## Radius for multi-target (Double Mark) and sundering spread.
const SPREAD_RADIUS: float = 160.0
## Bleeding Mark per-tick = magnitude (% of WEAPONATTACK) — read per cast.


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	# Upgrade reads: Lasting Mark (+duration), Double Mark (+N targets), Sundering
	# Mark (pierce-on-consume), Bleeding Mark (DOT on the marked target).
	var duration: float = MARK_DURATION
	var extra_targets: int = 0
	var sundering: bool = false
	var bleed_pct: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_duration")
		extra_targets = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_mark_targets"))
		sundering = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_pierce_on_crit") > 0.0
		bleed_pct = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_bleed_dot")

	# Bleeding Mark (T3) scales its bleed off the ability's max hit (stat-scaled,
	# like the other DoTs — project_dot_scaling_divergence). Computed once here.
	var dot_base: int = 0
	if bleed_pct > 0.0:
		var combat = owner_node.get("combat_component")
		if combat != null and combat.has_method("dot_scaling_base"):
			dot_base = combat.dot_scaling_base(_ability)

	_apply_mark(owner_node, target, duration, sundering, bleed_pct, dot_base)

	# Double Mark: also mark the nearest `extra_targets` other enemies.
	if extra_targets > 0:
		for other in _nearby_enemies(target, SPREAD_RADIUS, extra_targets):
			_apply_mark(owner_node, other, duration, sundering, bleed_pct, dot_base)


## Apply (or refresh) the mark + its T3 riders to one enemy.
func _apply_mark(owner_node: Node, target: Node, duration: float, sundering: bool, bleed_pct: float, dot_base: int = 0) -> void:
	if not is_instance_valid(target):
		return
	# Lazy expiry on read avoids any per-mark Timer plumbing.
	var expire_at_ms: int = Time.get_ticks_msec() + int(duration * 1000.0)
	target.set_meta(MARK_META, expire_at_ms)
	# Juice: the mark never ticks, so a marked enemy was invisible — name it.
	# Green (momentum theme) distinguishes the bow mark from the sword/dagger marks.
	EventJuice.proc(target, "MARKED", EventJuice.COLOR_MOMENTUM, "res://assets/sounds/generated/mark_ping.wav", "phys_impact")
	if sundering:
		target.set_meta(SUNDER_META, true)
	# Bleeding Mark: a light bleed for the mark's lifetime, scaled off the ability's
	# max hit (stat/mastery/level/gear) rather than raw WEAPONATTACK.
	if bleed_pct > 0.0 and dot_base > 0 and not target.has_meta(BLEEDING_MARK_META):
		var per_tick: int = maxi(1, roundi(dot_base * bleed_pct))
		target.set_meta(BLEEDING_MARK_META, true)
		BleedDot.apply(target, owner_node, per_tick, 1, duration, "moh_bleeding_mark")


## Up to `count` nearest valid living enemies within `radius` of `origin`
## (excluding `origin`). Distance-filtered; matches the simple proximity model
## the other v1 spread effects use.
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


## Public helper for CombatComponent: true if the marked target carries the
## Sundering Mark (T3) flag, so the auto-crit consume should pierce outward.
static func is_sundering(target: Node) -> bool:
	return is_instance_valid(target) and target.has_meta(SUNDER_META)


## Sundering Mark (T3): on the auto-crit consume, the hunt "pierces" to the two
## nearest enemies — applies a fresh (non-sundering, so it can't chain forever)
## Hunter's Mark to each. Clears the consumed target's sunder flag.
static func sunder_spread(_owner_node: Node, origin: Node) -> void:
	if not is_instance_valid(origin):
		return
	origin.remove_meta(SUNDER_META)
	var origin_pos: Vector2 = origin.global_position
	var expire_at_ms: int = Time.get_ticks_msec() + int(MARK_DURATION * 1000.0)
	var marked := 0
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
		if d <= SPREAD_RADIUS:
			candidates.append({"e": e, "d": d})
	candidates.sort_custom(func(a, b): return a.d < b.d)
	for c in candidates:
		if marked >= 2:
			break
		c.e.set_meta(MARK_META, expire_at_ms)
		marked += 1
