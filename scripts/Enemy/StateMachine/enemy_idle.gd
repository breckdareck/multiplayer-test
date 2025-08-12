extends EnemyState

@export var patrol_state: EnemyState
@export var slash_attack_state: EnemyState

var idle_timer: float

func enter() -> void:
	super.enter()
	parent.velocity = Vector2.ZERO
	_reset_idle_timer()


func process_frame(delta: float) -> State:
	idle_timer -= delta
	if idle_timer <= 0.0:
		if patrol_state:
			return patrol_state
		# Fallback to reset timer if no state is assigned
		_reset_idle_timer()
	return null


func physics_update(delta: float) -> State:
	# Apply gravity
	parent.velocity.y += gravity * delta
	# Ensure no horizontal movement
	parent.velocity.x = 0
	parent.move_and_slide()
	return null


func _reset_idle_timer() -> void:
	idle_timer = randf_range(1.0, 5.0)
