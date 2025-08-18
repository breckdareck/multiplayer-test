class_name MultiplayerPlayerV2
extends CharacterBody2D

const SPEED: float = 130.0
const JUMP_VELOCITY: float = -300.0

@export var player_id := 1:
	set(id):
		player_id = id
		# Safe access to InputSynchronizer
		var input_sync = get_node_or_null("%InputSynchronizer")
		if input_sync:
			input_sync.set_multiplayer_authority(id)

@export_category("Collision")
@export var platform_layer: int = 3

@export_category("Actions")
@export var slide_speed_boost: float = 250.0

@export_category("Components")
@export var health_component: HealthComponent
@export var combat_component: CombatComponent
@export var level_component: LevelingComponent
@export var debug_component: MyDebugComponent

@export_category("UI")
@export var player_HUD: Control

var username: String = ""

var direction: int = 0  # The current input direction from the synchronizer
var facing_direction: int = 1  # The last non-zero direction, for facing
var input_down: bool = false  # The current down input from the synchronizer

var do_attack: bool = false
var do_jump: bool = false
var do_drop: bool = false

var _sprite_base_offset_x: float
var _is_being_cleaned_up: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine = $StateMachine
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var drop_timer: Timer = $DropTimer
@onready var basic_attack_hitbox: CollisionShape2D = $Hitbox/BasicAttackHitbox
@onready var menu_container: MainMenu = get_tree().current_scene.get_node("%MenuContainer")


func _ready() -> void:
	if multiplayer.get_unique_id() == player_id:
		var menu_container_node = get_tree().current_scene.get_node("%MenuContainer")
		if menu_container_node and menu_container_node.has_method("get_username"):
			var user_name = (menu_container_node as MainMenu).get_username()
			set_username.rpc(user_name)
			request_load_data.rpc_id(1, username)
		else:
			print("Warning: Could not find MenuContainer or get_username method")

	if OS.has_feature("dedicated_server"):
		$Camera2D.queue_free()
		animated_sprite.visible = false
		animated_sprite.process_mode = Node.PROCESS_MODE_DISABLED
	else:
		if multiplayer.get_unique_id() == player_id:
			$Camera2D.make_current()
			debug_component.debug_panel.show()
			player_HUD.show()
			if OS.get_name() == "Android":
				player_HUD.get_child(1).show()
		else:
			$Camera2D.enabled = false

		# Store the base horizontal offset for correct positioning when flipping.
		_sprite_base_offset_x = abs(animated_sprite.offset.x)

	drop_timer.timeout.connect(_on_drop_timer_timeout)

	if multiplayer.is_server():
		# Connect to the health component's signals to react to death and respawn.
		health_component.died.connect(_on_player_died)
		$RespawnTimer.timeout.connect(_respawn)

		# Connect signals to save data when it changes
		if health_component:
			health_component.health_changed.connect(func(_c, _m): data_changed())
		if level_component:
			level_component.experience_changed.connect(func(_c, _e): data_changed())
			level_component.leveled_up.connect(func(_l): data_changed())

		await get_tree().process_frame

	debug_component.set_health_component(health_component)
	debug_component.set_player(self)

	state_machine.init(self, animated_sprite)


func _process(delta: float) -> void:
	if _is_being_cleaned_up:
		return

	if multiplayer.is_server():
		state_machine.process_frame(delta)


func _physics_process(delta: float) -> void:
	if _is_being_cleaned_up:
		return

	# Server-side authoritative logic
	if multiplayer.is_server():
		# Prevent player input from being processed while dead.
		if not health_component.is_dead:
			# Safe access to InputSynchronizer with validation
			var input_sync = get_node_or_null("%InputSynchronizer")
			if input_sync and is_instance_valid(input_sync):
				direction = input_sync.input_direction
				input_down = input_sync.input_down
			else:
				# Fallback if InputSynchronizer is not available
				direction = 0
				input_down = false
		else:
			# Clear input flags when dead to prevent movement.
			direction = 0
			input_down = false

		# Process physics in the current state
		state_machine.process_physics(delta)

	# Visual updates (runs on all instances)
	if state_machine.current_state and state_machine.current_state.allow_flip:
		animated_sprite.flip_h = facing_direction < 0
		animated_sprite.offset.x = (
		-_sprite_base_offset_x if facing_direction < 0 else _sprite_base_offset_x
		)


func _unhandled_input(event: InputEvent) -> void:
	if _is_being_cleaned_up:
		return

	if multiplayer.is_server():
		state_machine.process_input(event)


func apply_knockback(knockback: Vector2) -> void:
	if _is_being_cleaned_up:
		return

	# Simple knockback: directly set velocity. You may want to blend or add for smoother effect.
	velocity.x = knockback.x
	velocity.y = knockback.y


# Experience/Leveling
func gain_experience(amount: int) -> void:
	if _is_being_cleaned_up:
		return

	print("[DEBUG] Player %s gained %d EXP" % [str(self), amount])
	if level_component and level_component.has_method("add_exp"):
		level_component.add_exp(amount)


func _on_player_died(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return

	# This is called by the HealthComponent's 'died' signal on the server.
	$RespawnTimer.start()


@rpc("any_peer", "call_local", "reliable")
func _respawn() -> void:
	if _is_being_cleaned_up:
		return

	# This function must only run on the server.
	if not multiplayer.is_server():
		return

	# The server decides the respawn position and tells the component to respawn.
	position = MultiplayerManager.respawn_point
	do_attack = false
	do_jump = false
	do_drop = false
	health_component.respawn()
	

func can_drop_through_platform() -> bool:
	if _is_being_cleaned_up:
		return false

	# Check if the floor is a droppable platform.
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision.get_angle(up_direction) < floor_max_angle + 0.01:
			var collider_rid: RID = collision.get_collider_rid()
			var collider_layer_mask: int = PhysicsServer2D.body_get_collision_layer(collider_rid)
			if collider_layer_mask & (1 << (platform_layer - 1)):
				return true
			break  # We found the floor, no need to check other collisions.
	return false


func drop_through_platform() -> void:
	if _is_being_cleaned_up:
		return

	set_collision_mask_value(platform_layer, false)
	drop_timer.start()


func _on_drop_timer_timeout() -> void:
	if _is_being_cleaned_up:
		return

	set_collision_mask_value(platform_layer, true)

@rpc("any_peer", "call_local", "reliable")
func set_username(uname: String) -> void:
	print("Setting username to: ", uname, " for player_id: ", player_id)
	username = uname


func data_changed() -> void:
	if _is_being_cleaned_up:
		return

	# This function is called when any of the main variables change
	var data: Dictionary = save()
	save_on_server.rpc_id(1, JSON.stringify(data))


@rpc("any_peer", "call_local", "reliable")
func save_on_server(data: String) -> void:
	if not multiplayer.is_server():
		return

	print("%s: Saving on Server" % username)
	var parsed_data: Dictionary = JSON.parse_string(data)
	var file_path: String = "player_" + parsed_data["username"] + ".json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(data)
		file.close()


func save() -> Dictionary:
	var data: Dictionary = {
							   'username' = username,
							   'max_health' = health_component.max_health if health_component else 100,
							   'current_health' = health_component.current_health if health_component else 100,
							   'level' = level_component.level if level_component else 1,
							   'experience' = level_component.experience if level_component else 0
						   }
	return data

@rpc("any_peer", "call_local", "reliable")
func request_load_data(user_name: String) -> void:
	if not multiplayer.is_server():
		return

	var file_path: String = "player_" + user_name + ".json"
	if FileAccess.file_exists(file_path):
		var file = FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content = file.get_as_text()
			file.close()
			var parsed_json = JSON.parse_string(content)
			if typeof(parsed_json) == TYPE_DICTIONARY:
				load_data(parsed_json)

func load_data(data: Dictionary) -> void:
	if _is_being_cleaned_up:
		return

	print("Loading data")
	username = data.get("username", "Player")

	if health_component:
		health_component.set_block_signals(true)
		health_component.max_health = data.get("max_health", health_component.max_health)
		health_component.current_health = data.get("current_health", health_component.max_health)
		health_component.set_block_signals(false)
		health_component.health_changed.emit(health_component.current_health, health_component.max_health)

	if level_component:
		level_component.set_block_signals(true)
		level_component.level = data.get("level", 1)
		level_component.experience = data.get("experience", 0)
		level_component.set_block_signals(false)
		level_component.experience_changed.emit(level_component.experience, level_component.get_exp_to_next_level())
		level_component.leveled_up.emit(level_component.level)

# Cleanup method called before removal during channel switching
func cleanup_before_removal():
	print("Cleaning up MultiplayerPlayer: ", player_id)
	_is_being_cleaned_up = true

	# Stop all processing
	set_process(false)
	set_physics_process(false)

	# Disconnect all signals to prevent callbacks during cleanup
	if health_component and health_component.died.is_connected(_on_player_died):
		health_component.died.disconnect(_on_player_died)

	# Stop timers
	if is_instance_valid(drop_timer):
		drop_timer.stop()
	if is_instance_valid(coyote_timer):
		coyote_timer.stop()
	if has_node("RespawnTimer"):
		$RespawnTimer.stop()

	# Clear references that might cause issues
	menu_container = null

# Override _exit_tree to handle cleanup
func _exit_tree():
	cleanup_before_removal()
