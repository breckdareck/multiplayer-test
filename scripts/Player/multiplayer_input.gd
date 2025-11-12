# Your original input system with responsive improvements and channel switching fixes
extends MultiplayerSynchronizer

@export var sync_facing_direction := 1:
	set(value):
		sync_facing_direction = value
		# Safe access to player node
		if is_instance_valid(player) and player.has_method("set"):
			player.facing_direction = value

var input_direction
var input_down: bool
var portal_interact: bool
var is_left_pressed := false
var is_right_pressed := false
var _is_being_cleaned_up := false

@onready var player = $".."

func _ready():
	self.set_visibility_for(1, true)
	if get_multiplayer_authority() != multiplayer.get_unique_id():
		set_process(false)
		set_physics_process(false)

	input_direction = Input.get_axis("Move Left", "Move Right")
	input_down = Input.is_action_pressed("Move Down")
	portal_interact = Input.is_action_just_pressed("Portal Interact")

func _physics_process(_delta: float) -> void:
	if InputManager.is_locked():
		return
	# Don't process if being cleaned up
	if _is_being_cleaned_up:
		return

	# Safe check for player validity
	if not is_instance_valid(player):
		return

	# Get horizontal input from keyboard.
	var keyboard_input = Input.get_axis("Move Left", "Move Right")

	if keyboard_input != 0:
		# Prioritize keyboard input.
		input_direction = keyboard_input
	else:
		# If no keyboard input, use on-screen button state.
		input_direction = int(is_right_pressed) - int(is_left_pressed)

	# Update facing direction immediately when input changes
	if input_direction != 0:
		sync_facing_direction = input_direction

	# Get down input
	input_down = Input.is_action_pressed("Move Down")

func _process(_delta: float) -> void:
	if InputManager.is_locked():
		return
	# Don't process if being cleaned up
	if _is_being_cleaned_up:
		return

	# Safe check for player validity
	if not is_instance_valid(player):
		return

	if Input.is_action_just_pressed("Jump"):
		if Input.is_action_pressed("Move Down"):
			drop.rpc()
		else:
			jump.rpc()

	if Input.is_action_just_pressed("Attack") or Input.is_action_pressed("Attack"):
		attack.rpc()
	
	if Input.is_action_just_pressed("Pickup") or Input.is_action_pressed("Pickup"):
		pickup.rpc(true)
	else:
		pickup.rpc(false)
	
	if Input.is_action_just_pressed("Portal Interact"):
		portal.rpc()

@rpc("call_local")
func portal():
	if multiplayer.is_server() and is_instance_valid(player):
		player.do_portal_interact = true

@rpc("call_local")
func jump():
	if multiplayer.is_server() and is_instance_valid(player):
		player.do_jump = true

@rpc("call_local")
func drop():
	if multiplayer.is_server() and is_instance_valid(player):
		player.do_drop = true

@rpc("call_local")
func attack():
	if multiplayer.is_server() and is_instance_valid(player):
		player.do_attack = true

@rpc("call_local")
func pickup(value: bool):
	if multiplayer.is_server() and is_instance_valid(player):
		player.do_pickup = value

func _on_left_button_button_down() -> void:
	if _is_being_cleaned_up:
		return
	is_left_pressed = true

func _on_left_button_button_up() -> void:
	if _is_being_cleaned_up:
		return
	is_left_pressed = false

func _on_right_button_button_down() -> void:
	if _is_being_cleaned_up:
		return
	is_right_pressed = true

func _on_right_button_button_up() -> void:
	if _is_being_cleaned_up:
		return
	is_right_pressed = false

func _on_attack_button_pressed() -> void:
	if _is_being_cleaned_up:
		return
	attack.rpc()

func _on_jump_button_pressed() -> void:
	if _is_being_cleaned_up:
		return
	jump.rpc()


# Cleanup method called before removal during channel switching
func cleanup_before_removal():
	print("Cleaning up InputSynchronizer for player: ", get_multiplayer_authority())
	_is_being_cleaned_up = true

	# Stop all processing
	set_process(false)
	set_physics_process(false)

	# Clear player reference to prevent access after cleanup
	player = null

	# Reset input states
	input_direction = 0
	input_down = false
	is_left_pressed = false
	is_right_pressed = false
	sync_facing_direction = 1

# Override _exit_tree to handle cleanup
func _exit_tree():
	cleanup_before_removal()
