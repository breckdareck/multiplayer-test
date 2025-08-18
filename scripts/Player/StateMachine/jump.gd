extends State

# The jump state should only transition to the fall state.
@export var fall_state: State
@export var attack_state: State

@export var jump_velocity: float = -300.0

func enter() -> void:
	super()
	parent.velocity.y = jump_velocity
	var player
	if parent is MultiplayerPlayer:
		player = parent
	elif parent is MultiplayerPlayerV2:
		player = parent
	player.do_jump = false

	# A regular jump should immediately stop any active coyote timer
	# to prevent weird interactions.
	player.coyote_timer.stop()

func physics_update(delta: float) -> State:
	var player
	if parent is MultiplayerPlayer:
		player = parent
	elif parent is MultiplayerPlayerV2:
		player = parent
	var movement: float           = player.direction * move_speed

	# Allow attacking while jumping.
	if player.do_attack:
		return attack_state

	# This is the key to a good-feeling jump.
	# On the frame the jump starts, `_is_on_floor` (which was set at the
	# start of the physics frame) is still true.
	# This skips gravity for one frame, giving the jump its full power.
	if not player.is_on_floor():
		parent.velocity.y += gravity * delta

	# Consume other inputs mid-air to prevent buffering.
	if player is MultiplayerPlayer:
		if player.do_slide:
			player.do_slide = false
	if player.do_jump:
		player.do_jump = false

	parent.velocity.x = movement
	parent.move_and_slide()

	# When upward momentum is lost, transition to the fall state.
	# The fall state will handle all landing logic from here.
	if parent.velocity.y >= 0:
		return fall_state

	return null
