extends EnemyState
class_name EnemyAttackState

@export var return_state: EnemyState

var attack_finished: bool = false

func enter() -> void:
	super.enter()
	# Most attacks will stop the enemy's movement.
	parent.velocity = Vector2.ZERO
	attack_finished = false
	if not animations.animation_finished.is_connected(_on_attack_animation_finished):
		animations.animation_finished.connect(_on_attack_animation_finished)

func _on_attack_animation_finished():
	attack_finished = true


func process_frame(_delta: float) -> State:
	# Wait for the attack animation to finish, then transition.
	if attack_finished and return_state:
		return return_state
	return null


func physics_update(delta: float) -> State:
	# Apply gravity but prevent horizontal movement during the attack.
	parent.velocity.y += gravity * delta
	parent.velocity.x = 0
	parent.move_and_slide()
	return null
