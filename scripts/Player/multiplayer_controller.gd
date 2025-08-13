class_name MultiplayerPlayer
extends CharacterBody2D

const SPEED: float = 130.0
const JUMP_VELOCITY: float = -300.0

@export var player_id := 1:
	set(id):
		player_id = id
		%InputSynchronizer.set_multiplayer_authority(id)

@export_category("Collision")
@export var platform_layer: int = 3

@export_category("Actions")
@export var slide_speed_boost: float = 250.0

@export_category("Components")
@export var health_component: HealthComponent
@export var combat_component: CombatComponent
@export var debug_component: MyDebugComponent
@export var level_component: LevelingComponent

@export_category("UI")
@export var player_HUD: Control


var direction: int = 0  # The current input direction from the synchronizer
var facing_direction: int = 1  # The last non-zero direction, for facing
var input_down: bool = false  # The current down input from the synchronizer

var do_attack: bool = false
var do_jump: bool = false
var do_slide: bool = false
var do_drop: bool = false
var coming_from_slide: bool = false

# Variables to store original shape properties
var _original_shape: Shape2D
var _original_shape_position: Vector2
var _sprite_base_offset_x: float

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine = $StateMachine
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var drop_timer: Timer = $DropTimer
@onready var slide_timer: Timer = $SlideTimer
@onready var standing_collision_shape: CollisionShape2D = $StandingCollisionShape
@onready var crouch_collision_shape: CollisionShape2D = $CrouchCollisionShape
@onready var basic_attack_hitbox: CollisionShape2D = $Hitbox/BasicAttackHitbox


func _ready() -> void:
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

	# Store original shape data to restore it after roll/crouch
	_original_shape = standing_collision_shape.shape.duplicate()
	_original_shape_position = standing_collision_shape.position

	drop_timer.timeout.connect(_on_drop_timer_timeout)

	if multiplayer.is_server():
		# Connect to the health component's signals to react to death and respawn.
		health_component.died.connect(_on_player_died)
		$RespawnTimer.timeout.connect(_respawn)

		await get_tree().process_frame

	debug_component.set_health_component(health_component)
	debug_component.set_player(self)

	state_machine.init(self, animated_sprite)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		state_machine.process_frame(delta)


func _physics_process(delta: float) -> void:
	# Server-side authoritative logic
	if multiplayer.is_server():
		# Prevent player input from being processed while dead.
		if not health_component.is_dead:
			# Update direction from input synchronizer
			direction = %InputSynchronizer.input_direction
			input_down = %InputSynchronizer.input_down
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


func apply_knockback(knockback: Vector2) -> void:
	# Simple knockback: directly set velocity. You may want to blend or add for smoother effect.
	velocity.x = knockback.x
	velocity.y = knockback.y


# Experience/Leveling
func gain_experience(amount: int) -> void:
	print("[DEBUG] Player %s gained %d EXP" % [str(self), amount])
	if level_component and level_component.has_method("add_exp"):
		level_component.add_exp(amount)


func _on_player_died(_killer: Node) -> void:
	# This is called by the HealthComponent's 'died' signal on the server.
	$RespawnTimer.start()


@rpc("any_peer", "call_local", "reliable")
func _respawn() -> void:
	# This function must only run on the server.
	if not multiplayer.is_server():
		return

	# The server decides the respawn position and tells the component to respawn.
	position = MultiplayerManager.respawn_point
	do_attack = false
	do_jump = false
	do_slide = false
	do_drop = false
	coming_from_slide = false
	health_component.respawn()


func _change_collision_shape(new_shape_node: CollisionShape2D) -> void:
	"""A helper to safely disable one collision shape and enable another."""
	# Simply toggle collision shapes directly - no deferred calls
	if new_shape_node == standing_collision_shape:
		standing_collision_shape.set_deferred("disabled", false)
		crouch_collision_shape.set_deferred("disabled", true)
	else:
		standing_collision_shape.set_deferred("disabled", true)
		crouch_collision_shape.set_deferred("disabled", false)


func start_slide_effects() -> void:
	slide_timer.start()
	_change_collision_shape(crouch_collision_shape)


func end_slide_effects() -> void:
	_change_collision_shape(standing_collision_shape)


func start_crouch_effects() -> void:
	_change_collision_shape(crouch_collision_shape)


func end_crouch_effects() -> void:
	_change_collision_shape(standing_collision_shape)


func can_drop_through_platform() -> bool:
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
	set_collision_mask_value(platform_layer, false)
	drop_timer.start()


func _on_drop_timer_timeout() -> void:
	set_collision_mask_value(platform_layer, true)


func _unhandled_input(event: InputEvent) -> void:
	if multiplayer.is_server():
		state_machine.process_input(event)
