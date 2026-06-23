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
## The homing projectile this attack fires. Null = the shared default projectile
## (scenes/Gameplay/projectile_base.tscn).
@export var projectile_scene: PackedScene = null
## Projectile travel speed in px/sec (0 = a sane default).
@export var projectile_speed: float = 200.0

@export_group("Range")
## CollisionShape2D defining the CAST RANGE — author it and SEE it in the editor,
## exactly like the melee swing hitbox / breath cone. The caster stops here and fires.
## (It's a measurement region, never armed for damage — the projectile is homing.)
## Unset = fall back to the enemy-wide attack_range box.
@export var reach_shape: CollisionShape2D = null


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


func in_reach(enemy: EnemyBase, target: Node2D) -> bool:
	if reach_shape != null and reach_shape.shape != null:
		return target_in_reach_shape(enemy, target, reach_shape)
	# No cast-range shape authored yet — fall back to the enemy-wide attack_range box.
	return enemy.target_in_attack_zone(target)


func _active_start(enemy: EnemyBase) -> void:
	if not is_instance_valid(enemy.current_target):
		return
	enemy.fire_projectile(enemy.current_target, projectile_scene, projectile_speed)
