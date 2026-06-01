extends Node

## Vendetta (dagger active) — POISON SPENDER. Consumes ALL Envenom poison
## stacks on the target and folds a burst into Vendetta's own hit, scaled by
## the number of stacks consumed. Closes the Envenom→spend loop: today Envenom
## builds Poison and only Toxicology passively reads it; Vendetta cashes it in.
##
## SCALING (fixed 2026-06-02): the per-stack burst is folded into the main hit
## via `combat.pending_ability_damage_multiplier` (the sword-finisher mechanism)
## instead of a separate flat `WEAPONATTACK × pct × stacks` take_damage. The
## flat version was negligible at scale (it ignored the primary×4 term that
## dominates real hits). Now the spender scales with the full formula, shows as
## ONE damage number, and lands its burst even on a killing blow.
##
## The stacks are CONSUMED (the envenom_poison meta is removed) so Toxicology /
## another Vendetta can't keep cashing the same stacks — you must re-build.

const POISON_META: String = "envenom_poison"
## Each consumed Envenom stack adds this fraction to the whole Vendetta hit.
## 3 stacks (the Envenom cap) → +90% damage on top of Vendetta's base.
const PER_STACK_PCT: float = 0.30

## Single-target strike resolution (matches the melee hitbox reach).
const STRIKE_RANGE: float = 60.0
const MAX_HEIGHT_DELTA: float = 50.0


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
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
	if target == null or not target.has_meta(POISON_META):
		return  # nothing to spend — Vendetta deals its normal base hit

	var state: Dictionary = target.get_meta(POISON_META)
	var stacks: int = int(state.get("stacks", 0))
	if stacks <= 0:
		return

	# Consume the entire pool so the stacks can't be cashed twice.
	target.remove_meta(POISON_META)

	# Fold the burst into the whole hit (scales with the full damage formula,
	# shows as one number, applies on a kill). combat resets the multiplier in
	# end_ability_attack so it never bleeds into the next cast.
	combat.pending_ability_damage_multiplier = 1.0 + (float(stacks) * PER_STACK_PCT)


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
