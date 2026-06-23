extends EnemyState

@export var idle_state: EnemyState
@export var melee_attack_state: EnemyState

var direction: Vector2 = Vector2.RIGHT
var patrol_timer: float

func enter() -> void:
	super.enter()
	# Randomize heading so the enemy doesn't always march the same way after
	# each idle break — wall/ledge bounces still flip it during the patrol.
	direction.x = 1.0 if randf() < 0.5 else -1.0
	_reset_patrol_timer()


func process_frame(delta: float) -> State:
	var aggro := _check_aggro()
	if aggro:
		return aggro
	patrol_timer -= delta
	if patrol_timer <= 0.0:
		if idle_state:
			return idle_state
		# If no idle state is set, just reset the timer and continue patrolling.
		_reset_patrol_timer()
	return null


func physics_update(delta: float) -> State:
	var initial_velocity = parent.velocity
	
	# If we have significant velocity, gradually slow down instead of immediate stop
	if abs(initial_velocity.y) > 0:
		parent.velocity.x = move_toward(initial_velocity.x, 0, 250 * delta)
	else:
		var enemy: EnemyBase = parent as EnemyBase
		# Set horizontal velocity based on direction
		parent.velocity.x = direction.x * enemy.movement_speed
	
	# Apply gravity
	parent.velocity.y += gravity * delta

	# Use CharacterBody2D's move_and_slide
	parent.move_and_slide()

	# Check for a wall collision
	if parent.is_on_wall():
		direction.x = - direction.x
	else:
		# Ledge detection: Check if there's ground ahead
		# First, create a transform that's moved forward in the direction we're walking
		var check_distance = 12.0 # Distance ahead to check
		var check_depth = 16.0 # How far down to check for ground
		
		# Create a position ahead of the enemy
		var forward_offset = Vector2(direction.x * check_distance, 0)
		var forward_transform = parent.global_transform.translated(forward_offset)
		
		# Now check if there's ground below that forward position
		var downward_vector = Vector2(0, check_depth)
		var has_ground_ahead = parent.test_move(forward_transform, downward_vector)
		
		if not has_ground_ahead:
			# No ground ahead - we're at a ledge, turn around
			direction.x = - direction.x

	# Update facing direction
	parent._update_facing()

	return null


func _reset_patrol_timer() -> void:
	patrol_timer = randf_range(1.0, 5.0)
