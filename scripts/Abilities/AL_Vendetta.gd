extends Node

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## Vendetta (dagger active) — POISON SPENDER. Consumes ALL poison stacks on
## the target — the whole poison STATUS TAG (ADR 0013): Envenom, Caltrops'
## Poisoned Spikes, the weapon-pair imbue, anyone's — and folds a burst into
## Vendetta's own hit, scaled by the number of stacks consumed. Closes the
## build→spend loop across every poison source, not just Envenom's.
##
## SCALING (fixed 2026-06-02): the per-stack burst is folded into the main hit
## via `combat.pending_ability_damage_multiplier` (the sword-finisher mechanism)
## instead of a separate flat `WEAPONATTACK × pct × stacks` take_damage. The
## flat version was negligible at scale (it ignored the primary×4 term that
## dominates real hits). Now the spender scales with the full formula, shows as
## ONE damage number, and lands its burst even on a killing blow.
##
## The stacks are CONSUMED (every live poison meta is removed) so Toxicology /
## another Vendetta can't keep cashing the same stacks — you must re-build.

## Each consumed Envenom stack adds this fraction to the whole Vendetta hit.
## 3 stacks (the Envenom cap) → +90% damage on top of Vendetta's base.
const PER_STACK_PCT: float = 0.30

## Single-target strike resolution (matches the melee hitbox reach).
const STRIKE_RANGE: float = 60.0
const MAX_HEIGHT_DELTA: float = 50.0

## Lethal Vendetta (T3): when the target is in execute range (below this HP
## fraction) the burst is amplified by the bonus_execute_mult magnitude.
const EXECUTE_HP_THRESHOLD: float = 0.30


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
		return  # nothing to spend — Vendetta deals its normal base hit

	# Consume the entire poison TAG (all sources, summed) so the stacks can't
	# be cashed twice.
	var stacks: int = EnemyStatus.consume_tag(target, EnemyStatus.TAG_POISON)
	if stacks <= 0:
		return

	var burst: float = float(stacks) * PER_STACK_PCT

	# Lethal Vendetta (T3): if the target is in execute range, amplify the burst.
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		var execute_mult: float = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_execute_mult")
		if execute_mult > 0.0:
			var hc = target.get("health_component")
			if hc and is_instance_valid(hc) and hc.max_health > 0:
				if float(hc.current_health) / float(hc.max_health) < EXECUTE_HP_THRESHOLD:
					burst += execute_mult

	# Fold the burst into the whole hit (scales with the full damage formula,
	# shows as one number, applies on a kill). combat resets the multiplier in
	# end_ability_attack so it never bleeds into the next cast.
	combat.pending_ability_damage_multiplier = 1.0 + burst


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
