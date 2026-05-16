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
var input_up: bool
var portal_interact: bool
var is_left_pressed := false
var is_right_pressed := false
var _is_being_cleaned_up := false

@onready var player = $".."

func _ready():
	# Add visibility filter to prevent cross-map sync issues
	if multiplayer.has_multiplayer_peer():
		add_visibility_filter(_check_visibility_by_map)
	
	self.set_visibility_for(1, true)
	if get_multiplayer_authority() != multiplayer.get_unique_id():
		set_process(false)
		set_physics_process(false)

	input_direction = Input.get_axis("Move Left", "Move Right")
	input_down = Input.is_action_pressed("Move Down")
	input_up = Input.is_action_pressed("Move Up")
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

	# Get vertical input
	input_down = Input.is_action_pressed("Move Down")
	input_up = Input.is_action_pressed("Move Up")

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
			PlayerManager.player_input.rpc_id(1, "drop")
		else:
			PlayerManager.player_input.rpc_id(1, "jump")

	if Input.is_action_just_pressed("Attack") or Input.is_action_pressed("Attack"):
		PlayerManager.player_input.rpc_id(1, "attack")
	
	if Input.is_action_just_pressed("Pickup") or Input.is_action_pressed("Pickup"):
		PlayerManager.player_input.rpc_id(1, "pickup", true)
	else:
		PlayerManager.player_input.rpc_id(1, "pickup", false)
	
	if Input.is_action_just_pressed("Portal Interact"):
		PlayerManager.player_input.rpc_id(1, "portal")


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
	PlayerManager.player_input.rpc_id(1, "attack")

func _on_jump_button_pressed() -> void:
	if _is_being_cleaned_up:
		return
	PlayerManager.player_input.rpc_id(1, "jump")


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
	input_up = false
	is_left_pressed = false
	is_right_pressed = false
	sync_facing_direction = 1

# Override _exit_tree to handle cleanup
func _exit_tree():
	cleanup_before_removal()


func _check_visibility_by_map(peer_id: int) -> bool:
	"""Visibility filter - only visible to players on same map"""
	if not multiplayer.is_server():
		return true # Clients don't filter
	
	if _is_being_cleaned_up:
		return false # Being cleaned up, hide from everyone
	
	if not is_instance_valid(player):
		return false # Player invalid
	
	# Get this player's ID
	var my_id = get_multiplayer_authority()
	if my_id <= 0:
		return false # Invalid authority
	
	# Server always sees everyone
	if peer_id == 1:
		return true
	
	# Check if both players are on the same map
	var my_map = MapManager.get_player_map(my_id)
	var their_map = MapManager.get_player_map(peer_id)
	
	if my_map.is_empty() or their_map.is_empty():
		return false # Not on any map or disconnected
	
	return my_map == their_map # Only visible if on same map
