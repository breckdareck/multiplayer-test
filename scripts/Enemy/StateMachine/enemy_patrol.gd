extends EnemyState

@export var idle_state: EnemyState
@export var slash_attack_state: EnemyState

var direction: Vector2 = Vector2.RIGHT
var patrol_timer: float

func enter() -> void:
	super.enter()
	_reset_patrol_timer()


func process_frame(delta: float) -> State:
	patrol_timer -= delta
	if patrol_timer <= 0.0:
		if idle_state:
			return idle_state
		# If no idle state is set, just reset the timer and continue patrolling.
		_reset_patrol_timer()
	return null


func physics_update(delta: float) -> State:
	# Apply gravity
	parent.velocity.y += gravity * delta

	var enemy: EnemyBase = parent as EnemyBase
	# Set horizontal velocity based on direction
	parent.velocity.x = direction.x * enemy.movement_speed

	# Use CharacterBody2D's move_and_slide
	parent.move_and_slide()

	# Check for a wall collision
	if parent.is_on_wall():
		direction.x = -direction.x
	else:
		# To check for a ledge, we can simulate a small downward movement
		# from a position slightly in front of the enemy.
		var ledge_test_vector: Vector2 = Vector2(direction.x * 10, 10)
		var collision: bool            = parent.test_move(parent.transform, ledge_test_vector)
		if not collision:
			# There's no ground to collide with, so we're at a ledge.
			direction.x = -direction.x

	# Update facing direction
	parent._update_facing()

	return null


func _reset_patrol_timer() -> void:
	patrol_timer = randf_range(1.0, 5.0)
