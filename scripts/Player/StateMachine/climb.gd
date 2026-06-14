extends State

# Vertical climb state. Entered when the player is overlapping a Ladder area
# and presses Up or Down. While climbing, gravity is suppressed and the player
# passes through solid tiles and one-way platforms by temporarily clearing
# collision mask bits 1 (tiles) and the platform layer.

@export var idle_state: State
@export var fall_state: State

@export var climb_speed: float = 43.0

# Velocities applied when dismounting a ladder via Jump + horizontal direction.
# Much smaller than a full jump — a tiny upward hop with a sideways kick, not a
# launch. Tune to taste.
@export var dismount_velocity_y: float = -110.0
@export var dismount_velocity_x: float = 140.0

const TILE_COLLISION_LAYER: int = 1

func enter() -> void:
	super()
	if not multiplayer.is_server():
		return
	var player := parent as MultiplayerPlayerV2
	if not player:
		return

	parent.velocity = Vector2.ZERO
	# Juice: a soft grab cue — climbing had zero tactile feedback.
	AudioManager.play_sfx_for_map(MapManager.get_player_map(player.player_id), "res://assets/sounds/generated/land_soft.wav", player.global_position, -8.0)

	# Snap the player horizontally to the active ladder so they don't drift
	# off-column while climbing.
	var ladder: Node = player.get_active_ladder()
	if is_instance_valid(ladder) and ladder is Node2D:
		parent.global_position.x = (ladder as Node2D).global_position.x

	# Pass through solids + one-way platforms while on the ladder.
	parent.set_collision_mask_value(TILE_COLLISION_LAYER, false)
	parent.set_collision_mask_value(player.platform_layer, false)

	# If a drop-through is still in flight, cancel it — climb owns the mask now.
	if is_instance_valid(player.drop_timer):
		player.drop_timer.stop()

func exit() -> void:
	if not multiplayer.is_server():
		return
	var player := parent as MultiplayerPlayerV2
	if not player:
		return
	parent.set_collision_mask_value(TILE_COLLISION_LAYER, true)
	parent.set_collision_mask_value(player.platform_layer, true)

func physics_update(_delta: float) -> State:
	var player := parent as MultiplayerPlayerV2
	if not player:
		return null

	# Jump dismount — only when a horizontal direction is also held. Plain
	# Jump while climbing is consumed but ignored, so jumping alone won't
	# leap up off the ladder.
	if player.do_jump:
		player.do_jump = false
		if player.direction != 0:
			# Apply a small hop + sideways kick directly and go to fall, instead
			# of routing through jump_state (which would apply the full -300
			# launch). The fall state then handles air control and landing.
			parent.velocity = Vector2(player.direction * dismount_velocity_x, dismount_velocity_y)
			return fall_state

	# Left the ladder area (climbed off the top or bottom).
	if not player.is_in_ladder_zone():
		return fall_state

	var vy: float = 0.0
	if player.input_up:
		vy -= climb_speed
	if player.input_down:
		vy += climb_speed

	parent.velocity = Vector2(0, vy)
	parent.move_and_slide()
	return null
