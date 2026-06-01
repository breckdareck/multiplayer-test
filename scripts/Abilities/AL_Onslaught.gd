extends Node

## Vanguard's Onslaught (sword active) — CHANNEL + PIERCE. After a brief
## wind-up channel (managed by the ability's cast_time formula), unleashes
## a forward thrust that PIERCES every enemy in a horizontal line in the
## facing direction. Each enemy pierced grants +1 combo point — weaves
## the channel into the combo mesh without OP-scaling.
##
## Distinct from sword's other movement / spender abilities:
##   - Vault Strike: leap-arc + small AoE landing, single target focus
##   - Charge!: line-dash that hits enemies in path AS YOU MOVE, multi-build
##   - Onslaught: STATIONARY channel, big release, pierces a line in front
##
## The actual line-pierce collision is handled by the ability's
## active_behavior hitbox + the cast_time wind-up keeps the player rooted
## during the channel. THIS script handles per-pierce combo build via
## on_hit only.

const COMBO_PER_PIERCE: int = 1


func on_hit(owner_node: Node, _target: Node, ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	var combo_comp = owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp) or not combo_comp.has_method("add_combo_point"):
		return
	# Unstoppable (T3): +combo per pierced enemy.
	var extra: int = 0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		extra = int(ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_combo_per_hit"))
	# add_combo_point() adds exactly 1; loop for the total per-pierce count.
	for _i in range(COMBO_PER_PIERCE + extra):
		combo_comp.add_combo_point()
