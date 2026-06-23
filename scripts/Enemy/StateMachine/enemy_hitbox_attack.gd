extends "res://scripts/Enemy/StateMachine/enemy_timed_attack.gd"
## Hitbox-delivery attack: arms a CollisionShape2D (EnemyData.secondary_hitbox_shape)
## during the active window and damages every overlapping player once via
## damage_on_overlap — the same hitbox-driven model as the melee slash, applied to a
## breath/cone. Shows the breath plume sprite (EnemyData.secondary_breath_sprite) for
## the whole attack. Reach/shape is the editor-authored CollisionShape2D, not math.
##
## Currently the SECONDARY breath delivery. Defaults: windup 0.12 (mouth opens),
## active 0.55 (fire is live), recover 0. Injected by EnemyBase or authored in a scene.

## Bodies already struck this attack — each target is hit at most once.
var _hit_targets: Array[Node] = []


func _clip_anim(enemy: EnemyBase) -> String:
	return enemy.enemy_data.secondary_attack_anim if enemy.enemy_data else ""


func _attack_enter(enemy: EnemyBase) -> void:
	_hit_targets.clear()
	# Show the mouth plume for the whole attack (a cast, not an impact).
	enemy.play_secondary_breath_vfx()
	# Mirror the damage shape to facing, then start disarmed (armed on window open).
	var shape := _hit_shape(enemy)
	if shape:
		shape.position.x = absf(shape.position.x) * enemy.facing_direction
	_arm(enemy, false)


func _active_start(enemy: EnemyBase) -> void:
	_arm(enemy, true)


func _active_tick(enemy: EnemyBase) -> void:
	var hitbox: Area2D = enemy.attack_hitbox
	if hitbox == null or not hitbox.monitoring:
		return
	for body in hitbox.get_overlapping_bodies():
		if body in _hit_targets:
			continue
		if not enemy.is_valid_target(body):
			continue
		_hit_targets.append(body)
		enemy.damage_on_overlap(body)


func _active_end(enemy: EnemyBase) -> void:
	_arm(enemy, false)


func exit() -> void:
	var enemy := parent as EnemyBase
	super.exit()  # disarms (via _active_end) + starts the cooldown
	if enemy:
		enemy.stop_secondary_breath_vfx()


# --- helpers ---------------------------------------------------------------

## The breath's damage CollisionShape2D (EnemyData.secondary_hitbox_shape), or null.
func _hit_shape(enemy: EnemyBase) -> CollisionShape2D:
	if enemy.enemy_data == null or enemy.enemy_data.secondary_hitbox_shape.is_empty():
		return null
	return enemy.get_node_or_null(enemy.enemy_data.secondary_hitbox_shape) as CollisionShape2D


func _arm(enemy: EnemyBase, on: bool) -> void:
	var shape := _hit_shape(enemy)
	if shape:
		shape.disabled = not on
	if enemy.attack_hitbox:
		enemy.attack_hitbox.monitoring = on
