extends MultiplayerSynchronizer

@export var sync_facing_direction := 1:
	set(value):
		sync_facing_direction = value
		if player:
			player.facing_direction = value

@onready var player = $".."
var input_direction
var input_down: bool


func _ready():
	if get_multiplayer_authority() != multiplayer.get_unique_id():
		set_process(false)
		set_physics_process(false)

	input_direction = Input.get_axis("Move Left", "Move Right")
	input_down = Input.is_action_pressed("Move Down")


func _physics_process(_delta: float) -> void:
	# Get horizontal input direction
	input_direction = Input.get_axis("Move Left", "Move Right")
	# Update facing direction immediately when input changes
	if input_direction != 0:
		sync_facing_direction = input_direction
	# Get down input
	input_down = Input.is_action_pressed("Move Down")


func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("Jump"):
		if Input.is_action_pressed("Move Down"):
			drop.rpc()
		else:  # Otherwise, it's a regular jump.
			jump.rpc()

	if Input.is_action_just_pressed("Slide"):
		slide.rpc()

	if Input.is_action_just_pressed("Attack"):
		attack.rpc()


@rpc("call_local")
func jump():
	if multiplayer.is_server():
		player.do_jump = true


@rpc("call_local")
func drop():
	if multiplayer.is_server():
		player.do_drop = true


@rpc("call_local")
func slide():
	if multiplayer.is_server():
		player.do_slide = true


@rpc("call_local")
func attack():
	if multiplayer.is_server():
		player.do_attack = true
