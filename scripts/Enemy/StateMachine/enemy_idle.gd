extends EnemyState

@export var patrol_state: EnemyState
@export var slash_attack_state: EnemyState

var idle_timer: float

func enter() -> void:
	super.enter()
	parent.velocity.x = 0
	_reset_idle_timer()


func process_frame(delta: float) -> State:
	var aggro := _check_aggro()
	if aggro:
		return aggro
	idle_timer -= delta
	if idle_timer <= 0.0:
		if patrol_state:
			return patrol_state
		# Fallback to reset timer if no state is assigned
		_reset_idle_timer()
	return null


func physics_update(delta: float) -> State:
	# Store the initial velocity magnitude and direction
	var initial_velocity_x: float = parent.velocity.x

	# If we have significant velocity, gradually slow down instead of immediate stop
	if abs(initial_velocity_x) > 0:
		parent.velocity.x = move_toward(initial_velocity_x, 0, 250 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	return null


func _reset_idle_timer() -> void:
	idle_timer = randf_range(1.0, 5.0)
