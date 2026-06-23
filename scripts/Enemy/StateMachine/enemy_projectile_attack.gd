extends "res://scripts/Enemy/StateMachine/enemy_timed_attack.gd"
## Projectile-delivery attack: fires a homing projectile at the target when the
## active window opens (the same projectile the player uses). The caster stands and
## casts — no kiting. Used for any ranged/caster attack (primary OR a second spell);
## drop one node per spell and give each its own projectile + cooldown + clip.
##
## Defaults: windup 0.45 (cast read), active 0 (fires once at the open), recover 0.25.

## Cast-pose candidates when attack_anim is left blank, best first. MiniFolks casters
## slice the cast as "attack_2"; the spell-named clips cover other packs / future art.
const _CAST_ANIMS: Array[String] = ["spell", "cast", "attack_2", "attack_1", "attack"]

@export_group("Projectile")
## The homing projectile this attack fires. Null = inherit the enemy-wide
## EnemyData.ranged_projectile_scene (the primary-ranged default); a SECOND spell
## node must set its own. Null on both = the shared default projectile.
@export var projectile_scene: PackedScene = null
## Projectile travel speed in px/sec. 0 = inherit EnemyData.ranged_projectile_speed.
@export var projectile_speed: float = 0.0


func _clip_anim(enemy: EnemyBase) -> String:
	if attack_anim != "":
		return attack_anim
	# Back-compat: honor a pinned animation_name on the node, else auto-pick a cast pose.
	if animation_name != "":
		return animation_name
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy.enemy_data else null
	if sf != null:
		for a in _CAST_ANIMS:
			if sf.has_animation(a):
				return a
	return ""


func _in_reach(enemy: EnemyBase, target: Node2D) -> bool:
	var r: float = reach if reach > 0.0 else (enemy.enemy_data.attack_range if enemy.enemy_data else 36.0)
	return EnemyBase.position_in_attack_box(enemy.global_position, target.global_position, r)


func _active_start(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy.current_target):
		return
	var scene: PackedScene = projectile_scene
	if scene == null and enemy.enemy_data != null:
		scene = enemy.enemy_data.ranged_projectile_scene
	var speed: float = projectile_speed
	if speed <= 0.0 and enemy.enemy_data != null:
		speed = enemy.enemy_data.ranged_projectile_speed
	enemy.fire_projectile(enemy.current_target, scene, speed)
