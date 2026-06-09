extends State

@export var idle_state: State
@export var move_state: State
@export var jump_state: State
@export var attack_state: State
@export var climb_state: State

@export_group("Physics Properties")
@export var air_acceleration: float = 600.0


func enter() -> void:
	super()


func physics_update(delta: float) -> State:
	# Apply gravity
	parent.velocity.y += gravity * delta
	var player
	if parent is MultiplayerPlayerV2:
		player = parent
	# Always allow air control now that knockback is handled by velocity directly
	var target_velocity_x: float = player.direction * move_speed
	parent.velocity.x = move_toward(parent.velocity.x, target_velocity_x, air_acceleration * delta)

	# Allow air attacks.
	if player.do_attack:
		return attack_state

	# Grab a ladder mid-fall if overlapping one and pressing up or down.
	if climb_state and player.is_in_ladder_zone() and (player.input_up or player.input_down):
		return climb_state

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

	# Transition to ground states upon landing
	if parent.is_on_floor():
		# Quiet landing thud (server-broadcast to the map; no-op on clients).
		AudioManager.play_sfx_for_map(MapManager.get_player_map(player.player_id),
				"res://assets/sounds/generated/land_soft.wav", player.global_position, -6.0)
		if player.direction != 0:
			return move_state
		else:
			return idle_state

	return null
