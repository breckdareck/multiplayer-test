extends State

@export var idle_state: State
@export var fall_state: State
@export var slide_state: State
@export var attack_state: State
@export var move_state: State

func enter() -> void:
	super()
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# Keep some momentum when entering crouch state, but reduce it
	if player.direction != 0:
		# If the player is actively moving, adjust velocity to the slower crouch speed
		parent.velocity.x = player.direction * (move_speed * 0.6)
	else:
		# If no input direction, slow to a stop
		parent.velocity.x = move_toward(parent.velocity.x, 0, move_speed * 0.5)

	# Activate the crouch effects (e.g., smaller collision shape).
	# This assumes a 'start_crouch_effects' function exists on your player script.
	player.start_crouch_effects()

func exit() -> void:
	super()
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# CRITICAL: Always restore the original collision shape when exiting the crouch state.
	# This ensures player returns to normal standing shape regardless of next state
	player.end_crouch_effects()

func physics_update(delta: float) -> State:
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# Apply gravity.
	parent.velocity.y += gravity * delta

	# Stay still in crouch - no movement in this state
	parent.velocity.x = 0
	parent.move_and_slide()

	# --- STATE TRANSITIONS ---
	
	# Check for roll
	if player.do_slide and parent.is_on_floor():
		return slide_state

	# Check for attack
	if player.do_attack:
		return attack_state

	# Handle directional movement - this takes priority over staying in crouch
	if player.direction != 0:
		return move_state

	# Transition to Fall if no longer on the floor.
	if not parent.is_on_floor():
		return fall_state

	# Exit crouch when down is released
	if not player.input_down:
		return idle_state

	# Handle dropping through a platform (Jump + Down).
	if player.do_drop:
		player.do_drop = false # Consume the input.
		# This assumes a 'can_drop_through_platform' helper exists on your player script.
		if player.can_drop_through_platform():
			player.drop_through_platform()
			return fall_state

	# The primary way to exit crouch is to release the "down" key.
	# The 'input_down' variable comes from your MultiplayerInput synchronizer.
	if not player.input_down:
		return idle_state

	return null
