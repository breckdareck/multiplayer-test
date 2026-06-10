extends Node

## Backstab (dagger active) — POSITIONAL BONUS. When the player strikes an enemy
## from BEHIND (the side the enemy is facing away from), Backstab deals
## bonus damage. Rewards getting behind a target — pairs perfectly with the
## reworked Shadowstep, which blinks the player behind the furthest enemy.
##
## SCALING (fixed 2026-06-02): the from-behind bonus is folded into the main
## hit via `combat.pending_ability_damage_multiplier` (the same mechanism the
## sword combo finisher uses) instead of a separate flat-WEAPONATTACK
## take_damage. This means:
##   - the bonus scales with the FULL damage formula (primary×4 + secondary)
##     × attack — a flat `WEAPONATTACK × 0.5` was negligible at scale because
##     it ignored the primary-stat term that dominates real hits.
##   - the bonus shows as ONE damage number (no awkward second hit), and
##   - it applies even on a KILLING blow (it's part of the hit that kills),
##     fixing the "only shows if the enemy survives" complaint.
##
## The positional check + multiplier are set in execute() (before the hit is
## rolled). Backstab is single-target, so we resolve the one enemy the strike
## will land on by scanning the small forward strike range.

## From-behind damage bonus (fraction added to the whole hit). 0.75 = +75%.
## Strong because it requires positioning (the player must be behind the
## target), which is real setup cost.
const BACKSTAB_BONUS_PCT: float = 0.75

## How far in front to look for the strike target (matches the melee hitbox
## reach so we resolve the enemy the hitbox will actually hit).
const STRIKE_RANGE: float = 60.0
const MAX_HEIGHT_DELTA: float = 50.0

## Player meta written by AL_Shadowstep when it blinks BEHIND a target — a
## brief grace window during which Backstab counts as "from behind" even
## though the enemy (which faces its movement direction) has already turned
## to face the player. This makes the designed Shadowstep → Backstab combo
## reliably land the bonus, since enemies face their target almost instantly
## (facing_direction tracks velocity.x). Consumed on a backstab.
const SHADOWSTEP_WINDOW_META: String = "backstab_window_until_ms"


func execute(owner_node: Node, ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var combat = owner_node.get("combat_component")
	if combat == null or not is_instance_valid(combat):
		return

	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1

	var target: Node = _nearest_strike_target(owner_node, facing)
	if target == null:
		return  # nothing to backstab — the hit (if any) deals normal damage

	# "From behind" is satisfied by EITHER:
	#  (a) the positional check — the player is on the side the enemy is facing
	#      away from. enemy.facing_direction: +1 right, -1 left; player_side is
	#      +1 if right of the enemy, -1 if left. Behind when those differ. (This
	#      is unreliable against an aggroed enemy, which faces the player almost
	#      instantly because facing tracks velocity — but works on a stationary
	#      / fleeing / patrolling enemy.)
	#  (b) a fresh Shadowstep window — the player just blinked behind the
	#      target. This is the designed combo and the reliable trigger.
	var enemy_facing: int = 1
	if "facing_direction" in target:
		enemy_facing = int(target.facing_direction)
		if enemy_facing == 0:
			enemy_facing = 1
	var player_side: int = 1 if owner_node.global_position.x > target.global_position.x else -1
	var positional_behind: bool = (player_side != enemy_facing)

	var window_behind: bool = false
	if owner_node.has_meta(SHADOWSTEP_WINDOW_META):
		if Time.get_ticks_msec() < int(owner_node.get_meta(SHADOWSTEP_WINDOW_META)):
			window_behind = true
		owner_node.remove_meta(SHADOWSTEP_WINDOW_META)  # one backstab per blink

	if not positional_behind and not window_behind:
		return  # striking the enemy's FRONT — no backstab bonus

	# From behind — compute the bonus. Lethal Backstab (T3) doubles it against
	# a full-health target (the assassin-opener payoff: hit the fresh, unaware
	# target hardest).
	var bonus: float = BACKSTAB_BONUS_PCT
	var lethal_applied: bool = false
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		# Sharper Backstab (T1): flat increase to the from-behind bonus fraction.
		bonus += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_positional_dmg")
		var fullhp_mult: float = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "backstab_fullhp_mult")
		if fullhp_mult > 0.0 and _is_full_health(target):
			bonus *= fullhp_mult
			lethal_applied = true

	# Fold the bonus into the whole hit. combat resets this to 1.0 in
	# end_ability_attack so it never bleeds into the next cast.
	combat.pending_ability_damage_multiplier = 1.0 + bonus
	#print("Backstab from behind: +%.0f%% damage%s" % [bonus * 100.0, " (LETHAL — full-HP target)" if lethal_applied else ""])


## Crippling Backstab (T3): the hit also slows the target. Fires per landed hit
## (combat.gd dispatches on_hit). Mirrors AL_Caltrops' save/restore/meta slow.
const SLOW_META: String = "backstab_slow"
const SLOW_DURATION: float = 2.0

func on_hit(owner_node: Node, target: Node, ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not (target is EnemyBase) or not is_instance_valid(target):
		return
	var ability_comp = owner_node.get("ability_component")
	if ability_comp == null or ability == null or not ability_comp.has_method("get_ability_upgrade_magnitude"):
		return
	var slow_pct: float = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_slow_apply")
	if slow_pct <= 0.0:
		return

	var e := target as EnemyBase
	if e.has_meta(SLOW_META):
		return  # already slowed by this effect — let the timer run out
	var original_speed: float = e.movement_speed
	e.movement_speed = original_speed * (1.0 - clampf(slow_pct, 0.0, 0.95))
	e.set_meta(SLOW_META, original_speed)
	EnemyStatus.register(e, EnemyStatus.TAG_CHILL, SLOW_META, null)
	e.get_tree().create_timer(SLOW_DURATION).timeout.connect(
		func():
			if not is_instance_valid(e):
				return
			if e.has_meta(SLOW_META):
				e.movement_speed = e.get_meta(SLOW_META)
				e.remove_meta(SLOW_META)
	)


## Nearest living enemy within STRIKE_RANGE in the facing direction, same map.
## Backstab is single-target, so we only need the closest one the hitbox lands on.
func _nearest_strike_target(owner_node: Node, facing: int) -> Node:
	if owner_node.get_tree() == null:
		return null
	var origin: Vector2 = owner_node.global_position
	var owner_map: Node = null
	for map_id in MapManager.active_maps.keys():
		var inst = MapManager.active_maps[map_id].get("scene_instance")
		if is_instance_valid(inst) and inst.is_ancestor_of(owner_node):
			owner_map = inst
			break

	var best: Node = null
	var best_dist: float = STRIKE_RANGE + 1.0
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		if owner_map != null and not owner_map.is_ancestor_of(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var dx: float = enemy.global_position.x - origin.x
		if facing > 0 and dx <= 0.0:
			continue
		if facing < 0 and dx >= 0.0:
			continue
		var dist: float = absf(dx)
		if dist > STRIKE_RANGE:
			continue
		if absf(enemy.global_position.y - origin.y) > MAX_HEIGHT_DELTA:
			continue
		if dist < best_dist:
			best_dist = dist
			best = enemy
	return best


## "Full health" is >= 99% so a sliver of chip/rounding doesn't deny the
## Lethal bonus on what is visually a fresh target.
func _is_full_health(target: Node) -> bool:
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc):
		return false
	if not ("max_health" in hc) or not ("current_health" in hc):
		return false
	var maxh: float = float(hc.max_health)
	if maxh <= 0.0:
		return false
	return float(hc.current_health) / maxh >= 0.99
