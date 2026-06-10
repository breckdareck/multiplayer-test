extends Node

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## Shared upgrade hook — SLOW ON HIT. Attached as the logic_script of abilities
## whose T3 variant slows struck enemies (Skyfall's Grounding Fall, Fan of
## Knives' Hamstring Fan, ...). on_hit no-ops unless the ability owns an
## upgrade with effect_key "bonus_slow_on_hit" (magnitude = slow fraction,
## e.g. 0.4 = 40% slower), so attaching this script costs nothing until the
## variant is purchased.
##
## Mirrors StaffElementComponent._apply_slow's save/restore/meta/tint idiom —
## movement_speed is a plain EnemyBase field (read live by enemy_chase /
## enemy_patrol every physics frame), so we scale it directly and restore the
## saved base on a timer. Own meta key, independent of the staff chill and the
## Glacial freeze, so none of them clobber another's saved base speed.

const SLOW_DURATION: float = 2.5
const SLOW_META: String = "upgrade_slow_on_hit"


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	var slow_pct: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		slow_pct = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_slow_on_hit")
	if slow_pct <= 0.0:
		return
	apply_slow(_target, slow_pct, SLOW_DURATION)


## Static so other AL_*.gd scripts with their own on_hit can reuse the exact
## same slow (same meta key = the two applications can never double-stack).
static func apply_slow(target: Node, slow_pct: float, duration: float) -> void:
	if not (target is EnemyBase):
		return
	var enemy := target as EnemyBase
	# No point slowing a corpse — the hit may have already killed it.
	var hc = enemy.get("health_component")
	if hc != null and is_instance_valid(hc) and hc.is_dead:
		return
	# Already slowed by this hook — no-op. Re-applying would compound the
	# reduction off the already-reduced base and the restore would then write
	# back a wrong value; the existing slow runs out its own timer.
	if enemy.has_meta(SLOW_META):
		return

	var original_speed: float = enemy.movement_speed
	enemy.movement_speed = original_speed * (1.0 - clampf(slow_pct, 0.0, 0.9))
	enemy.set_meta(SLOW_META, original_speed)
	EnemyStatus.register(enemy, EnemyStatus.TAG_CHILL, SLOW_META, null)

	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		enemy.animated_sprite.modulate = Color(0.75, 0.8, 1.0, 1.0)

	# `enemy.get_tree()` — logic_scripts are instantiated via
	# `logic_script.new()` and never enter the scene tree, so self.get_tree()
	# is null. The enemy IS in the tree (same pattern as AL_GlacialSpike).
	enemy.get_tree().create_timer(duration).timeout.connect(
		func():
			if not is_instance_valid(enemy):
				return
			# Restore from the saved value rather than dividing back out —
			# robust against movement_speed being reassigned meanwhile.
			if enemy.has_meta(SLOW_META):
				enemy.movement_speed = enemy.get_meta(SLOW_META)
				enemy.remove_meta(SLOW_META)
			if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
				enemy.animated_sprite.modulate = Color.WHITE
	)
