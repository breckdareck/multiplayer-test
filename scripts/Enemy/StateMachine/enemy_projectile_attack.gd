extends "res://scripts/Enemy/StateMachine/enemy_timed_attack.gd"
## Projectile-delivery attack: fires a homing projectile at the target when the
## active window opens (the same projectile the player uses). The caster stands and
## casts — no kiting. Covers both the PRIMARY ranged attack and a SECONDARY bolt.
##   - PRIMARY:   reads EnemyData.ranged_projectile_* and a cast pose.
##   - SECONDARY: reads EnemyData.secondary_projectile_* and secondary_attack_anim.
##
## Defaults: windup 0.45 (cast read), active 0 (fires once at the open), recover 0.25.
## Injected by EnemyBase (ranged_attack / secondary_attack) or authored in a scene.

## Cast-pose candidates for the PRIMARY ranged attack, best first. MiniFolks casters
## slice the cast as "attack_2"; the spell-named clips cover other packs / future art.
const _CAST_ANIMS: Array[String] = ["spell", "cast", "attack_2", "attack_1", "attack"]


func _clip_anim(enemy: EnemyBase) -> String:
	if enemy.enemy_data == null:
		return ""
	if config == Config.SECONDARY:
		return enemy.enemy_data.secondary_attack_anim
	# PRIMARY: honor the authored animation_name on this node — lets a multi-spell
	# caster pin its primary cast clip (e.g. "attack_1") so it doesn't collide with
	# the secondary's clip. Falls back to auto-picking a cast pose when left blank.
	if animation_name != "":
		return animation_name
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames
	if sf == null:
		return ""
	for a in _CAST_ANIMS:
		if sf.has_animation(a):
			return a
	return ""


func _active_start(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy.current_target):
		return
	if config == Config.SECONDARY:
		enemy.fire_secondary_projectile(enemy.current_target)
	else:
		enemy.fire_projectile(enemy.current_target)
