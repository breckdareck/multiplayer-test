extends State

@export var idle_state: State
@export var move_state: State
@export var jump_state: State
@export var attack_state: State

@export_group("Physics Properties")
@export var air_acceleration: float = 600.0


func enter() -> void:
	super()
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# If we're coming from a roll, preserve the velocity that was set in roll.exit()
	if player.coming_from_slide:
		# We've handled the flag, now reset it
		player.coming_from_slide = false


func physics_update(delta: float) -> State:
	# Apply gravity
	parent.velocity.y += gravity * delta
	var player = parent as MultiplayerPlayer
	# Always allow air control now that knockback is handled by velocity directly
	var target_velocity_x: float = player.direction * move_speed
	parent.velocity.x = move_toward(parent.velocity.x, target_velocity_x, air_acceleration * delta)

	# Allow air attacks.
	if player.do_attack:
		return attack_state

	parent.move_and_slide()

	# Check for a coyote time jump.
	# We can only jump if the coyote timer is running.
	if player.do_jump and not player.coyote_timer.is_stopped():
		player.coyote_timer.stop() # Consume the coyote jump immediately
		return jump_state

	# Always consume inputs that are invalid while airborne to prevent buffering.
	# This prevents actions from being unintentionally queued until the player lands.
	if player.do_jump:
		player.do_jump = false
	if player.do_slide:
		player.do_slide = false

	# Transition to ground states upon landing
	if parent.is_on_floor():
		if player.direction != 0:
			return move_state
		else:
			return idle_state

	return null
