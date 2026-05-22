extends EnemyAttackState
## Goblin-family melee swing. Faces the target on enter, lands one hit mid-swing
## on every player/bot in front of the enemy, then starts the per-enemy attack
## cooldown on exit.

@export var slash_hitbox_shape: CollisionShape2D

var _hit_landed: bool = false

func enter() -> void:
	super.enter() # zeroes velocity and resets the attack timer
	_hit_landed = false
	if slash_hitbox_shape:
		slash_hitbox_shape.disabled = false
	# Face the target so the swing connects on the correct side.
	var enemy := parent as EnemyBase
	if enemy and is_instance_valid(enemy.current_target):
		enemy.face_toward(enemy.current_target.global_position)


func physics_update(delta: float) -> State:
	if not _hit_landed:
		_hit_landed = true
		var enemy := parent as EnemyBase
		if enemy:
			enemy.perform_slash_hit()
	return super.physics_update(delta)


func exit() -> void:
	if slash_hitbox_shape:
		slash_hitbox_shape.disabled = true
	var enemy := parent as EnemyBase
	if enemy:
		enemy.start_attack_cooldown()
	super.exit()
