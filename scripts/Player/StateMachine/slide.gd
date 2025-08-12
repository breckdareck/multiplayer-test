extends State

@export var idle_state: State
@export var move_state: State
@export var fall_state: State
@export var jump_state: State
@export var attack_state: State

@export_category("Roll Physics")
# Remove all deceleration-related variables
# We'll maintain constant velocity throughout the roll

func enter() -> void:
	super()
	allow_flip = false
	var player: MultiplayerPlayer = parent as MultiplayerPlayer
	player.do_slide = false # Consume the input immediately

	# Determine the roll direction. If standing still, use the sprite's facing direction.
	var slide_direction = sign(parent.velocity.x)
	if slide_direction == 0:
		slide_direction = player.facing_direction

	# First activate roll effects (changes collision shape)
	player.start_slide_effects()

	# THEN set the velocity (AFTER changing collision shape)
	# We'll maintain this velocity throughout the entire roll
	parent.velocity.x = slide_direction * player.slide_speed_boost

func physics_update(delta: float) -> State:
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# --- JUMP CANCEL LOGIC ---
	# Allow the player to cancel the roll with a jump.
	# We only allow this if the player is on the floor to prevent exploits
	# like jumping after rolling off a ledge.
	if player.do_jump and parent.is_on_floor():
		return jump_state

	# Allow the player to cancel the roll with an attack.
	if player.do_attack:
		return attack_state

	# Consume any inputs that are not used to prevent buffering.
	# If we are airborne during a roll, a jump input should be consumed.
	if player.do_jump:
		player.do_jump = false
	# A roll cannot be initiated from a roll.
	if player.do_slide:
		player.do_slide = false

	# Apply gravity
	parent.velocity.y += gravity * delta

	# Store horizontal velocity before move_and_slide
	var velocity_before: float = parent.velocity.x

	parent.move_and_slide()

	# Check if velocity was zeroed by move_and_slide
	if abs(parent.velocity.x) < 0.1 and abs(velocity_before) > 0.1:
		# Restore the horizontal velocity
		parent.velocity.x = velocity_before

	# When the roll timer finishes, check if we should transition to the next state
	if player.slide_timer.is_stopped():
		# If we are on the ground, transition to the appropriate ground state
		if parent.is_on_floor():
			# If player is holding a direction, go to move state
			if player.direction != 0:
				return move_state
			else:
				return idle_state
		# If in the air, go to fall state
		else:
			return fall_state

	return null

func exit() -> void:
	super()
	# Get reference to player for clarity
	var player: MultiplayerPlayer = parent as MultiplayerPlayer

	# Set a flag to indicate we're coming from a roll
	player.coming_from_slide = true

	# Stop timer if still running
	if not player.slide_timer.is_stopped():
		player.slide_timer.stop()

	# Save the current roll velocity direction before changing states
	var slide_direction = sign(parent.velocity.x)

	# Change collision shape back to standing
	player.end_slide_effects()

	# Check if player is holding a direction
	if player.direction != 0:
		# Set velocity based on player's input direction and normal movement speed
		parent.velocity.x = player.direction * player.SPEED
	# If player isn't holding a direction but was rolling in a direction, maintain some momentum
	elif slide_direction != 0:
		# Keep 40% of roll speed when exiting roll without directional input
		parent.velocity.x = slide_direction * player.SPEED * 0.4
