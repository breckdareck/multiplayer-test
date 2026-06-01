extends Node

## Backstab (dagger active) — POSITIONAL BONUS: when struck from behind (i.e.
## the attacker is on the side the enemy is NOT facing), the hit deals an
## additional flat percentage of WEAPONATTACK. Rewards spatial awareness
## without needing telegraphed enemy attacks — only the enemy's facing
## direction is read.
##
## Fires per landed hit via on_hit. The bonus is gated on the attacker
## standing on the enemy's back side; EnemyBase carries a `facing_direction`
## field set by enemy_chase / enemy_patrol (positive = facing right). If the
## attacker is on the opposite side, the bonus fires. If the enemy is
## facing the attacker (chasing them, for instance), no bonus.
##
## Off-back this does nothing. Pairs with Shadowstep (blink THROUGH the
## enemy, land facing-away from it for a guaranteed Backstab on the next
## hit) and Smoke Bomb (enemy aggro dropped → enemy stops facing you).

const BONUS_PCT: float = 0.50   ## +50% of WEAPONATTACK on a from-behind hit


func on_hit(owner_node: Node, target: Node, _ability: AbilityData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(target):
		return
	if not (target is EnemyBase):
		return

	var enemy := target as EnemyBase
	var hc = enemy.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return

	# Determine which side the attacker is on relative to the enemy.
	# enemy.facing_direction: +1 facing right, -1 facing left (read from EnemyBase).
	var enemy_facing: int = 1
	if "facing_direction" in enemy:
		enemy_facing = int(enemy.facing_direction)
		if enemy_facing == 0:
			enemy_facing = 1
	# Attacker side: +1 if attacker is to the right of the enemy, -1 if left.
	var attacker_side: int = 1 if owner_node.global_position.x > enemy.global_position.x else -1
	# "From behind" = attacker is on the side opposite to the enemy's facing.
	if attacker_side == enemy_facing:
		return  # enemy is facing the attacker — no bonus

	# Bonus strike, scaled off WEAPONATTACK. Bypasses i-frames so it lands
	# alongside the main hit (mirrors AL_Eviscerate's execute strike).
	var stats = owner_node.get("stats_component")
	if stats == null or not stats.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn: int = int(stats.stats[Constants.StatType.WEAPONATTACK].total_value)
	var bonus: int = maxi(1, roundi(wpn * BONUS_PCT))
	hc.take_damage(bonus, owner_node, true, false, true)
