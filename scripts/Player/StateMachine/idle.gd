extends State

@export var jump_state: State
@export var fall_state: State
@export var move_state: State
@export var slide_state: State
@export var attack_state: State
@export var crouch_state: State

func enter() -> void:
	super()
	
	parent.velocity.x = 0

func physics_update(delta: float) -> State:
	var player
	if parent is MultiplayerPlayerV2:
		player = parent

	# Store the initial velocity magnitude and direction
	var initial_velocity_x: float = parent.velocity.x

	# If we have significant velocity, gradually slow down instead of immediate stop
	if abs(initial_velocity_x) > 20:
		parent.velocity.x = move_toward(initial_velocity_x, 0, 150 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()

	# Check for attack input.
	if attack_state:
		if player.do_attack:
			return attack_state

	# Check for the specific "drop" command from the client.
	if player.do_drop and parent.is_on_floor():
		player.do_drop = false # Consume the input flag.

		# If we can drop, do it. Otherwise, convert the input to a regular jump.
		if player.can_drop_through_platform():
			player.drop_through_platform()
			return fall_state
		else:
			player.do_jump = true

	if player.do_jump and player.is_on_floor():
		return jump_state
	if player.direction != 0:
		return move_state

	if not parent.is_on_floor():
		player.coyote_timer.start()
		return fall_state

	return null
