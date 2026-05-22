extends EnemyAttackState
## Goblin-family melee swing. The AttackHitbox area is live only during the
## contact frames of the slash animation and is mirrored to the enemy's facing,
## so the hit lands when the swing visually connects — the same hitbox-driven
## model the player's CombatComponent uses.

@export var slash_hitbox_shape: CollisionShape2D

## Animation-frame window (inclusive) during which the hitbox deals damage.
## Tuned for the shared 8-frame SF_Goblin "slash_attack" clip: frames 0-3 are
## the wind-up, 4-7 the swing-through where the weapon actually connects.
const HIT_FRAME_START: int = 4
const HIT_FRAME_END: int = 7

var _hitbox_active: bool = false
## Bodies already struck this swing — each target is hit at most once.
var _hit_targets: Array[Node] = []


func enter() -> void:
	super.enter() # plays the slash animation, zeroes velocity, resets the timer
	_hit_targets.clear()

	var enemy := parent as EnemyBase
	if enemy:
		# Face the target, then mirror the hitbox shape to that side (the same
		# trick CombatComponent.turn_on_hitbox uses for the player).
		if is_instance_valid(enemy.current_target):
			enemy.face_toward(enemy.current_target.global_position)
		if slash_hitbox_shape:
			slash_hitbox_shape.position.x = absf(slash_hitbox_shape.position.x) * enemy.facing_direction

	# Start the swing with the hitbox off — it only arms on the contact frames.
	_set_hitbox_enabled(false)


func physics_update(delta: float) -> State:
	_update_hitbox()
	return super.physics_update(delta)


func exit() -> void:
	_set_hitbox_enabled(false)
	var enemy := parent as EnemyBase
	if enemy:
		enemy.start_attack_cooldown()
	super.exit()


## Arms the hitbox during the contact frames of the swing and damages every
## valid target caught inside it (once each).
func _update_hitbox() -> void:
	var enemy := parent as EnemyBase
	if enemy == null:
		return

	var frame := _current_slash_frame(enemy)
	var should_be_active := frame >= HIT_FRAME_START and frame <= HIT_FRAME_END
	if should_be_active != _hitbox_active:
		_set_hitbox_enabled(should_be_active)

	if not _hitbox_active:
		return

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


func _set_hitbox_enabled(on: bool) -> void:
	_hitbox_active = on
	if slash_hitbox_shape:
		slash_hitbox_shape.disabled = not on
	var enemy := parent as EnemyBase
	if enemy and enemy.attack_hitbox:
		enemy.attack_hitbox.monitoring = on


func _current_slash_frame(enemy: EnemyBase) -> int:
	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		return enemy.animated_sprite.frame
	# No sprite to read (headless edge case) — treat the swing as in-window so
	# the hit still lands.
	return HIT_FRAME_START
