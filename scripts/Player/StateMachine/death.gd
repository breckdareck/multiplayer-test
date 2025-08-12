extends State

@export var respawn_state: State

func enter() -> void:
	super.enter()
	allow_flip = false
	# Let process_physics handle all movement changes for a smoother effect.

func process_physics(_delta: float) -> State:
	# We override the base process_physics to prevent the universal death check
	# from causing an infinite loop while we are in the Death state.

	# Apply gravity so the player continues to fall naturally.
	parent.velocity.y += gravity * _delta

	# Apply friction to slide to a stop horizontally.
	# You can adjust the '150' to control how quickly they stop.
	parent.velocity.x = move_toward(parent.velocity.x, 0, 250 * _delta)

	parent.move_and_slide()

	# Check if the server has respawned us (by setting is_dead to false on the HealthComponent).
	# This aligns with our component-based architecture.
	if not parent.health_component.is_dead:
		if respawn_state:
			return respawn_state
		push_error("Respawn state is not set for the Death state in the editor!")

	return null
