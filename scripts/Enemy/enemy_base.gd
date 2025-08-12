class_name EnemyBase
extends CharacterBody2D

# Emitted after the death animation finishes, signaling it can be returned to the pool.
signal ready_for_pooling

@export var movement_speed: float = 60.0
@export var damage: int = 10
@export var health_component: HealthComponent
@export var post_death_delay: float = 1.5 # Time to wait after death animation before disappearing.
@export var experience_reward: int = 10 # Experience granted to the player who kills this enemy

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var hitbox: Area2D = $Hitbox
@onready var body_hitbox: Area2D = $BodyHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var facing_direction: int = 1

func _ready() -> void:
	if not health_component:
		push_error("Enemy '%s' requires a HealthComponent to be assigned." % name)
		return

	if multiplayer.is_server():
		# The server listens for the death signal from the component.
		health_component.died.connect(_on_enemy_died)
		body_hitbox.body_entered.connect(_on_body_hitbox_body_entered)
		# Only connect animation_finished if AnimatedSprite2D exists (not on dedicated server)
		if animated_sprite:
			animated_sprite.animation_finished.connect(_on_animation_finished)
		await get_tree().process_frame

	# Initialize state machine with the same pattern as player
	state_machine.init(self, animated_sprite)


func _process(delta: float) -> void:
	if multiplayer.is_server():
		state_machine.process_frame(delta)


func _physics_process(delta: float) -> void:
	if multiplayer.is_server():
		state_machine.process_physics(delta)


func _on_enemy_died(killer: Node) -> void:
	# Grant experience to the player if possible
	print("Enemy: On Died Called")
	var exp_receiver = killer.get_owner() as MultiplayerPlayer
	if exp_receiver and exp_receiver.has_method("gain_experience"):
		exp_receiver.gain_experience(experience_reward)
	hitbox.monitoring = false
	body_hitbox.monitoring = false

	# On dedicated server, AnimatedSprite2D is stripped, so trigger pooling after delay
	if OS.has_feature("dedicated_server"):
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)

# --- Object Pooling Methods ---

## Deactivates the enemy, making it invisible and non-interactive.
## Called by the spawner when the enemy is returned to the pool.
func pool_deactivate() -> void:
	visible = false
	set_process(false)
	set_physics_process(false)
	collision_shape.set_deferred("disabled", true)
	hitbox.monitoring = false
	body_hitbox.monitoring = false
	# Move far away to prevent any lingering interactions.
	global_position = Vector2(INF, INF)


func pool_reset() -> void:
	# Reset health and death state using the component.
	if health_component:
		health_component.respawn()

	# Re-enable visuals, logic, and physics.
	visible = true
	set_process(true)
	set_physics_process(true)
	collision_shape.set_deferred("disabled", false)
	hitbox.monitoring = true
	body_hitbox.monitoring = true


func _update_facing() -> void:
	if velocity.x != 0:
		facing_direction = 1 if velocity.x > 0 else -1
		animated_sprite.flip_h = facing_direction < 0


func _on_body_hitbox_body_entered(body: Node) -> void:
	if not multiplayer.is_server():
		return

	# Only damage the player
	if body.has_node("Components/Health"):
		var health = body.get_node("Components/Health") as HealthComponent
		if health.is_dead or health.is_invulnerable:
			return

		# Knockback logic handled here
		var player_facing = 1
		if body.has_method("get_facing_direction"):
			player_facing = body.get_facing_direction()
		elif "facing_direction" in body:
			player_facing = body.facing_direction
		var knockback_dir: int        = -player_facing
		var knockback_strength: float = 150.0
		var knockback_lift: float     = -100.0 # negative Y is up in Godot
		var knockback_vec = Vector2(knockback_dir * knockback_strength, knockback_lift)
		health.take_damage(damage, self)
		if body.has_method("apply_knockback"):
			body.apply_knockback(knockback_vec)


func apply_knockback(knockback: Vector2) -> void:
	velocity.x = knockback.x
	velocity.y = knockback.y


func _on_animation_finished() -> void:
	# If the death animation has just finished, signal to the spawner that this
	# enemy instance is ready to be deactivated and returned to the pool, after a short delay.
	if animated_sprite.animation == "death": # Assumes death animation is named "death"
		# Create a one-shot timer to wait before disappearing.
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)


func emit_ready_for_pooling() -> void:
	"""Emits the signal that the spawner is waiting for."""
	ready_for_pooling.emit()
