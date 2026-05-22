extends EnemyState
class_name EnemyAttackState

@export var return_state: EnemyState

## Failsafe: if the attack animation never reports finished (missing or looping
## animation), bail out anyway so the enemy can't get stuck mid-swing.
const MAX_ATTACK_TIME: float = 1.5

var attack_finished: bool = false
var _attack_time: float = 0.0

func enter() -> void:
	super.enter()
	# Most attacks will stop the enemy's movement.
	parent.velocity = Vector2.ZERO
	attack_finished = false
	_attack_time = 0.0
	if not animations.animation_finished.is_connected(_on_attack_animation_finished):
		animations.animation_finished.connect(_on_attack_animation_finished)

func _on_attack_animation_finished():
	attack_finished = true


func process_frame(delta: float) -> State:
	_attack_time += delta
	# Wait for the attack animation to finish (or the failsafe to trip).
	if not (attack_finished or _attack_time >= MAX_ATTACK_TIME):
		return null
	# Keep fighting if the target is still alive and in play; otherwise fall
	# back to the configured return state (idle/patrol).
	var enemy := parent as EnemyBase
	if enemy and enemy.is_valid_target(enemy.current_target):
		var chase := get_node_or_null("../chase")
		if chase:
			return chase
	return return_state


func physics_update(delta: float) -> State:
	# Apply gravity but prevent horizontal movement during the attack.
	parent.velocity.y += gravity * delta
	parent.velocity.x = 0
	parent.move_and_slide()
	return null
