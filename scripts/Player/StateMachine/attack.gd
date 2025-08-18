extends State

var player

@export var idle_state: State
@export var fall_state: State

var _was_on_floor: bool = false

# --- Combo System ---
@export_category("Combo")
@export var max_combo_steps: int = 2
var _combo_input_buffered: bool = false
var _current_combo_step: int = 0

@onready var animation_player: AnimationPlayer = owner.get_node_or_null("../../AnimationPlayer")
@onready var attack_state_timer: Timer = $"../../AttackStateTimer"

func enter() -> void:
	super()
	allow_flip = false
	if parent is MultiplayerPlayer:
		player = parent
	elif parent is MultiplayerPlayerV2:
		player = parent
	player.do_attack = false

	_was_on_floor = parent.is_on_floor()
	if parent.is_on_floor():
		parent.velocity.x = 0

	_current_combo_step = 1
	_start_attack_for_step(_current_combo_step)

	_combo_input_buffered = false

func _play_animation(anim_name: String) -> void:
	if (not multiplayer.is_server() || MultiplayerManager.host_mode_enabled) and not anim_name.is_empty():
		if animation_player:
			animation_player.play(anim_name)
		else:
			animations.play(anim_name)

@rpc("authority", "call_local", "reliable")
func _execute_combo_step_rpc(step: int):
	"""RPC called by the server to command clients to execute a specific combo step."""
	_current_combo_step = step
	_start_attack_for_step(step)
	_combo_input_buffered = false

func _start_attack_for_step(step: int):
	"""Plays the correct animation and starts the timer with its exact duration."""
	var anim_name: String = "attack_" + str(step)
	_play_animation(anim_name)
	var duration: float = _get_animation_duration(anim_name)
	#print("Attack anim: ", anim_name, " duration: ", duration)
	var buffer: float = 0.02
	attack_state_timer.start(max(duration - buffer, 0.01))
	if multiplayer.is_server():
		if player.combat_component:
			player.combat_component.perform_attack(anim_name)

func _get_animation_duration(anim_name: String) -> float:
	var sprite_frames: SpriteFrames = player.animated_sprite.sprite_frames
	if not sprite_frames.has_animation(anim_name):
		return 0.0

	var frame_count: int = sprite_frames.get_frame_count(anim_name)
	var anim_fps: float = sprite_frames.get_animation_speed(anim_name)
	if frame_count == 0 or anim_fps <= 0.0:
		return 0.0

	var total_duration: float = 0.0
	for i in range(frame_count):
		var frame_duration: float = sprite_frames.get_frame_duration(anim_name, i)
		total_duration += frame_duration / anim_fps

	# Optionally, account for the sprite's speed_scale
	if player.animated_sprite.speed_scale > 0.0:
		total_duration /= player.animated_sprite.speed_scale

	return total_duration

func physics_update(delta: float) -> State:
	# Apply gravity so the player falls if attacking mid-air.
	var now_on_floor = parent.is_on_floor()
	if not _was_on_floor and now_on_floor:
		parent.velocity.x = 0
	_was_on_floor = now_on_floor
	parent.velocity.y += gravity * delta
	parent.move_and_slide()

	# Only the server should process input and make decisions about state transitions.
	if multiplayer.is_server():
		# During the attack, buffer the next attack input if pressed.
		if player.do_attack:
			_combo_input_buffered = true
			player.do_attack = false # Consume the flag immediately.

		# Consume other inputs to prevent buffering other actions during the attack.
		if player.do_jump:
			player.do_jump = false
		if player is MultiplayerPlayer:
			if player.do_slide:
				player.do_slide = false

		# Once the attack timer is finished, the server decides what to do next.
		if attack_state_timer.is_stopped():
			# Check if we can and should continue the combo.
			if _combo_input_buffered and _current_combo_step < max_combo_steps:
				_current_combo_step += 1
				# The server calls an RPC to command itself (call_local) and all clients
				# to execute the next combo step, ensuring everyone is in sync.
				_execute_combo_step_rpc.rpc(_current_combo_step)
			else:
				# --- Combo finished or broken, exit the state ---
				# The state change will be synced by the MultiplayerSynchronizer.
				return idle_state if parent.is_on_floor() else fall_state


	return null

func exit() -> void:
	super()
	# Always reset the combo counter when leaving the attack state.
	_current_combo_step = 0
