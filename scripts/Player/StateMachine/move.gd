extends State

@export var idle_state: State
@export var fall_state: State
@export var jump_state: State
@export var slide_state: State
@export var attack_state: State
@export var crouch_state: State

func enter() -> void:
	super()
	var player
	if parent is MultiplayerPlayer:
		player = parent
	elif parent is MultiplayerPlayerV2:
		player = parent

	# If we're coming from a roll, preserve the velocity that was set in roll.exit()
	if player is MultiplayerPlayer:
		if player.coming_from_slide:
			# We've handled the flag, now reset it
			player.coming_from_slide = false

func physics_update(delta: float) -> State:
	var player
	if parent is MultiplayerPlayer:
		player = parent
	elif parent is MultiplayerPlayerV2:
		player = parent

	# Store the initial velocity magnitude and direction
	var initial_velocity_x: float = parent.velocity.x
	
	# Knockback logic removed; adjust velocity normally
	if abs(initial_velocity_x) > player.SPEED and player.direction != 0 and sign(initial_velocity_x) == sign(player.direction):
		# Only gradually adjust to normal speed over time
		parent.velocity.x = move_toward(initial_velocity_x, player.direction * player.SPEED, 100 * delta)
	parent.velocity.y += gravity * delta
	
	var movement: float = player.direction * move_speed

	# Check for roll input first, as it's a key defensive/movement option.
	if player is MultiplayerPlayer:
		if player.do_slide and parent.is_on_floor():
			return slide_state

	# Check for attack input.
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

	if movement == 0:
		return idle_state

	parent.velocity.x = move_toward(parent.velocity.x, movement, 1200 * delta)
		
	parent.move_and_slide()

	if not parent.is_on_floor():
		player.coyote_timer.start()
		return fall_state

	return null
