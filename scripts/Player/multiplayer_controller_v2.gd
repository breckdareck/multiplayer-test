class_name MultiplayerPlayerV2
extends CharacterBody2D

const SPEED: float = 130.0
const JUMP_VELOCITY: float = -300.0
const SERVER_ID: int = 1

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
@export var stats_component: StatsComponent
@export var class_component: ClassComponent
@export var debug_component: MyDebugComponent

@export_category("UI")
@export var player_HUD: Control
@export var player_name_label: RichTextLabel

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
@onready var respawn_timer: Timer = $RespawnTimer
@onready var basic_attack_hitbox: CollisionShape2D = $Hitbox/BasicAttackHitbox
@onready var menu_container: MainMenu = get_tree().current_scene.get_node("%MenuContainer")


#=============================================================================
# GODOT LIFECYCLE METHODS
#=============================================================================

func _ready() -> void:
	if multiplayer.get_unique_id() == player_id:
		var menu_container: MainMenu = get_tree().current_scene.get_node_or_null("%MenuContainer") as MainMenu
		if is_instance_valid(menu_container) and menu_container.has_method("get_username"):
			var user_name: String = menu_container.get_username()
			set_username.rpc(user_name)
			request_load_data.rpc_id(SERVER_ID, user_name)
		else:
			push_warning("Could not find MenuContainer or get_username method.")

		# Request the sprite states of all other players from the server.
		request_all_sprite_states.rpc_id(SERVER_ID)

	# Server-specific setup
	if multiplayer.is_server():
		_setup_server_signals()
		# Handle sprite change on initial spawn
		await get_tree().process_frame
		_handle_sprite_change_on_server()

	# Client-specific setup
	if not OS.has_feature("dedicated_server"):
		_setup_client_visuals()

	# Initialize components
	if is_instance_valid(debug_component):
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

	# Server-authoritative physics processing
	if multiplayer.is_server():
		_update_input_from_synchronizer()
		state_machine.process_physics(delta)

	# Visual updates run on all peers (clients and server)
	_update_sprite_facing_direction()


func _unhandled_input(event: InputEvent) -> void:
	if _is_being_cleaned_up:
		return

	if multiplayer.is_server():
		state_machine.process_input(event)


func _exit_tree():
	cleanup_before_removal()

#=============================================================================
# PUBLIC METHODS
#=============================================================================

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


func cleanup_before_removal():
	print("MPController: Cleaning up MultiplayerPlayer: ", player_id)
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

	
#=============================================================================
# PRIVATE HELPER METHODS
#=============================================================================

func _setup_server_signals() -> void:
	if not multiplayer.is_server():
		return

	# Connect component signals to handle game logic and data saving.
	if level_component:
		level_component.experience_changed.connect(func(_c, _e): data_changed())
		level_component.leveled_up.connect(func(_l): data_changed())
		level_component.leveled_up.connect(_handle_sprite_change_on_server.unbind(1))
	
	if health_component:
		health_component.health_changed.connect(func(_c, _m): data_changed())

	if is_instance_valid(drop_timer):
		drop_timer.timeout.connect(_on_drop_timer_timeout)

	if is_instance_valid(respawn_timer):
		respawn_timer.timeout.connect(_respawn)


func _setup_client_visuals() -> void:
	var camera: Camera2D = $Camera2D

	if multiplayer.get_unique_id() == player_id:
		camera.make_current()
		if is_instance_valid(debug_component):
			debug_component.debug_panel.show()
		if is_instance_valid(player_HUD):
			player_HUD.show()
			# Show mobile controls on Android
			if OS.get_name() == "Android":
				var mobile_controls = player_HUD.get_child(1)
				if is_instance_valid(mobile_controls):
					mobile_controls.show()
	else:
		camera.enabled = false

	# Store sprite offset for correct flipping.
	_sprite_base_offset_x = abs(animated_sprite.offset.x)


func _update_input_from_synchronizer() -> void:
	# Do not process input if the player is dead.
	if is_instance_valid(health_component) and health_component.is_dead:
		direction = 0
		input_down = false
		return

	var input_sync: Node = get_node_or_null("%InputSynchronizer")
	if is_instance_valid(input_sync):
		direction = input_sync.input_direction
		input_down = input_sync.input_down
	else:
		# Fallback if the synchronizer is not found.
		direction = 0
		input_down = false


func _update_sprite_facing_direction() -> void:
	if state_machine.current_state and state_machine.current_state.allow_flip:
		animated_sprite.flip_h = facing_direction < 0

		var offset_sign: float = -1.0 if facing_direction < 0 else 1.0
		animated_sprite.offset.x = _sprite_base_offset_x * offset_sign


func _change_sprite() -> void:
	if player_id != multiplayer.get_unique_id():
		return

	if multiplayer.is_server():
		_handle_sprite_change_on_server() # Host client can call directly.
	else:
		request_sprite_change.rpc_id(SERVER_ID) # Remote clients must ask server.

		
func _handle_sprite_change_on_server() -> void:
	if not is_instance_valid(class_component) or not is_instance_valid(level_component):
		return

	var class_type: int = class_component.current_class
	var current_level: int = level_component.level

	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, current_level)
	if sprite_frames:
		change_sprite_rpc.rpc(class_component.get_class_name(), current_level)


func save() -> Dictionary:
	var data: Dictionary = {
	   'username': username,
	   'max_health': health_component.max_health if is_instance_valid(health_component) else 100,
	   'current_health': health_component.current_health if is_instance_valid(health_component) else 100,
	   'level': level_component.level if is_instance_valid(level_component) else 1,
	   'experience': level_component.experience if is_instance_valid(level_component) else 0
						   }
	return data


func load_data(data: Dictionary) -> void:
	if _is_being_cleaned_up:
		return

	print("Loading data for ", data.get("username", "Unknown"))
	username = data.get("username", "Player")

	print(data)
	if is_instance_valid(level_component):
		print("Level Component found")
		level_component.set_block_signals(true)
		level_component.level = data.get("level", 1)
		level_component.experience = data.get("experience", 0)
		level_component.set_block_signals(false)
		level_component.experience_changed.emit(level_component.experience, level_component.get_exp_to_next_level())
		level_component.leveled_up.emit(level_component.level)
		
	if is_instance_valid(health_component):
		print("Health Component found")
		health_component.set_block_signals(true)
		health_component.max_health = data.get("max_health", health_component.max_health)
		health_component.current_health = data.get("current_health", health_component.max_health)
		health_component.set_block_signals(false)
		health_component.health_changed.emit(health_component.current_health, health_component.max_health)


#=============================================================================
# SIGNAL HANDLERS
#=============================================================================

func _on_player_died(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return
	respawn_timer.start()


func _on_drop_timer_timeout() -> void:
	if _is_being_cleaned_up:
		return
	set_collision_mask_value(platform_layer, true)


func data_changed() -> void:
	if _is_being_cleaned_up:
		return
	var data_string: String = JSON.stringify(save())
	save_on_server.rpc_id(SERVER_ID, data_string)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id == player_id:
		return

	# Wait a frame to ensure the new peer is ready.
	await get_tree().process_frame

	print("Sending sprite data for player %d to new peer %d" % [player_id, peer_id])
	if is_instance_valid(class_component) and is_instance_valid(level_component):
		var _class_name: String = class_component.get_class_name()
		var current_level: int = level_component.level
		change_sprite_rpc.rpc_id(peer_id, _class_name, current_level)


#=============================================================================
# RPC (REMOTE PROCEDURE CALL) METHODS
#=============================================================================

# [SERVER-ONLY] Respawns the player at a designated point.
@rpc("any_peer", "call_local", "reliable")
func _respawn() -> void:
	if not multiplayer.is_server() or _is_being_cleaned_up:
		return

	# The server authoritatively sets the respawn position and resets state.
	position = MultiplayerManager.respawn_point
	do_attack = false
	do_jump = false
	do_drop = false
	if is_instance_valid(health_component):
		health_component.respawn()


# [CLIENT -> SERVER] Requests that the server save the provided player data.
@rpc("any_peer", "call_local", "reliable")
func save_on_server(data_string: String) -> void:
	if not multiplayer.is_server():
		return

	var parsed_data: Dictionary = JSON.parse_string(data_string)
	if parsed_data.is_empty():
		push_error("Failed to parse JSON for saving.")
		return

	var user_name: String = parsed_data.get("username", "")
	if user_name.is_empty(): return

	print("Server: Saving data for %s" % user_name)
	var file_path: String = "player_%s.json" % user_name
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(data_string)
		file.close()


# [CLIENT -> SERVER] Requests to load this player's data from a file.
@rpc("any_peer", "call_local", "reliable")
func request_load_data(user_name: String) -> void:
	if not multiplayer.is_server():
		return

	var file_path: String = "player_%s.json" % user_name
	if FileAccess.file_exists(file_path):
		var file := FileAccess.open(file_path, FileAccess.READ)
		if file:
			var content: String = file.get_as_text()
			file.close()
			var parsed_json = JSON.parse_string(content)
			if typeof(parsed_json) == TYPE_DICTIONARY:
				load_data(parsed_json)
	else:
		# If no save file exists, create one with default data.
		save_on_server(JSON.stringify(save()))


# [CLIENT -> SERVER] Asks the server to initiate a sprite change for this player.
@rpc("any_peer", "call_local", "reliable")
func request_sprite_change() -> void:
	if not multiplayer.is_server():
		return
	_handle_sprite_change_on_server()


# [SERVER -> CLIENTS] Broadcasts the sprite change to all clients.
@rpc("authority", "call_local", "reliable")
func change_sprite_rpc(_class_name: String, level: int) -> void:
	var class_type: int = ResourceManager.get_class_type_from_string(_class_name)
	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, level)
	if sprite_frames:
		animated_sprite.sprite_frames = sprite_frames
		animated_sprite.play("idle")
	else:
		push_warning("Could not find sprite for %s level %d" % [_class_name, level])


# [CLIENT -> SERVER] Client requests to change their class.
@rpc("any_peer", "call_local", "reliable")
func change_class_request(new_class: int) -> void:
	if not multiplayer.is_server():
		return

	if is_instance_valid(class_component):
		class_component.change_class_rpc.rpc(new_class)
		_handle_sprite_change_on_server()


# [CLIENT -> SERVER] A new client requests the sprite states of all existing players.
@rpc("any_peer", "call_local", "reliable")
func request_all_sprite_states() -> void:
	if not multiplayer.is_server():
		return
		
	var requester_id: int = multiplayer.get_remote_sender_id()
	for node in get_tree().get_nodes_in_group("players"):
		if node is MultiplayerPlayerV2 and node != self:
			node._on_peer_connected(requester_id)


# [ALL PEERS] Sets the username for this player instance across all clients.
@rpc("any_peer", "call_local", "reliable")
func set_username(uname: String) -> void:
	username = uname
	if is_instance_valid(player_name_label):
		player_name_label.text = username
