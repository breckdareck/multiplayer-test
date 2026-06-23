extends "res://scripts/Enemy/StateMachine/enemy_timed_attack.gd"
## Hitbox-delivery (breath) attack: shows a child plume sprite at the mouth and arms a
## CollisionShape2D during the active window, damaging every overlapping player once via
## damage_on_overlap — the same hitbox-driven model as the melee swing, applied to a
## breath/cone. Reach/shape is the editor-authored CollisionShape2D, not math.
##
## Owns both node paths itself (no EnemyData fields). Defaults: windup 0.12 (mouth opens),
## active 0.55 (fire is live), recover 0.

@export_group("Breath")
## Child AnimatedSprite2D plume (authored at the mouth, hidden by default). Shown +
## looped ("play") for the whole attack, mirrored to facing.
@export var breath_sprite: NodePath = ^""
## CollisionShape2D (on the AttackHitbox) that defines the breath's damage area —
## mirrored to facing and armed during the active window.
@export var breath_hitbox: NodePath = ^""

## Bodies already struck this attack — each target is hit at most once.
var _hit_targets: Array[Node] = []


func _clip_anim(_enemy: EnemyBase) -> String:
	return attack_anim


func in_reach(enemy: EnemyBase, target: Node2D) -> bool:
	# The breath's reach IS its damage cone — the same authored CollisionShape2D.
	return target_in_reach_shape(enemy, target, _hit_shape(enemy))


func _attack_enter(enemy: EnemyBase) -> void:
	_hit_targets.clear()
	_show_breath(enemy, true)
	# Mirror the damage shape to facing, then start disarmed (armed on window open).
	var shape := _hit_shape(enemy)
	if shape:
		shape.position.x = absf(shape.position.x) * enemy.facing_direction
	_arm(enemy, false)


func _active_start(enemy: EnemyBase) -> void:
	_arm(enemy, true)


func _active_tick(enemy: EnemyBase) -> void:
	damage_overlapping(enemy, _hit_targets)


func _active_end(enemy: EnemyBase) -> void:
	_arm(enemy, false)


func exit() -> void:
	var enemy := parent as EnemyBase
	super.exit()  # disarms (via _active_end) + arms this attack's cooldown
	if enemy:
		_show_breath(enemy, false)


# --- helpers ---------------------------------------------------------------

func _hit_shape(enemy: EnemyBase) -> CollisionShape2D:
	if breath_hitbox.is_empty():
		return null
	return enemy.get_node_or_null(breath_hitbox) as CollisionShape2D


func _arm(enemy: EnemyBase, on: bool) -> void:
	arm_attack_hitbox(_hit_shape(enemy), on)


## Show/hide the plume, mirrored to the enemy's facing (read off the replicated
## main-sprite flip_h so it's correct on clients). Runs on every peer via enter/exit.
func _show_breath(enemy: EnemyBase, on: bool) -> void:
	if breath_sprite.is_empty():
		return
	var fx := enemy.get_node_or_null(breath_sprite) as AnimatedSprite2D
	if fx == null:
		return
	if not on:
		fx.stop()
		fx.visible = false
		return
	var face_left: bool = enemy.animated_sprite != null and enemy.animated_sprite.flip_h
	if not fx.has_meta("breath_base_x"):
		fx.set_meta("breath_base_x", absf(fx.position.x))
	fx.position.x = float(fx.get_meta("breath_base_x")) * (-1.0 if face_left else 1.0)
	fx.flip_h = face_left
	fx.visible = true
	fx.frame = 0
	fx.play("play")
