class_name EnemyBase
extends CharacterBody2D

# Emitted after the death animation finishes, signaling it can be returned to the pool.
signal ready_for_pooling

@export var health_component: HealthComponent
@export var monster_level: int = 1
@export var movement_speed: float = 60.0
@export var damage: int = 10
@export var health_curve: Curve
@export var experience_curve: Curve
@export var respawnable: bool
@export var respawn_delay: int = 10

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var body_hitbox: Area2D = $BodyHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D

var experience_reward: int = 0:
	get():
		return int(experience_curve.sample(monster_level))
var post_death_delay: float = 1.5 # Time to wait after death animation before disappearing.
var damage_by_player: Dictionary = {}  # player_id : damage_amount
var facing_direction: int = 1
var _is_being_cleaned_up: bool = false
var initial_position: Vector2

func _ready() -> void:
	# Add to networked entities group for proper cleanup during channel switching
	add_to_group("networked_entities")
	
	if not health_component:
		push_error("Enemy '%s' requires a HealthComponent to be assigned." % name)
		return

	if multiplayer.is_server():
		# The server listens for the death signal from the component.
		initial_position = global_position
		health_component.max_health = int(health_curve.sample(monster_level))
		health_component.current_health = health_component.max_health
		health_component.died.connect(_on_enemy_died)
		health_component.damaged.connect(on_enemy_damaged)
		body_hitbox.body_entered.connect(_on_body_hitbox_body_entered)
		# Only connect animation_finished if AnimatedSprite2D exists (not on dedicated server)
		if animated_sprite:
			animated_sprite.animation_finished.connect(_on_animation_finished)
		await get_tree().process_frame

	# Initialize state machine with the same pattern as player
	state_machine.init(self, animated_sprite)


func _process(delta: float) -> void:
	if _is_being_cleaned_up:
		return
		
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		state_machine.process_frame(delta)
		if body_hitbox.monitoring:
			var overlapping_bodies = body_hitbox.get_overlapping_bodies()
			for body in overlapping_bodies:
				if body is MultiplayerPlayerV2:
					damage_on_overlap(body)

func _physics_process(delta: float) -> void:
	if _is_being_cleaned_up:
		return
		
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		state_machine.process_physics(delta)


func on_enemy_damaged(amount: int, source: Node) -> void:
	var player_id = null
	if source is MultiplayerPlayerV2:
		player_id = source.player_id
	else:
		player_id = source.owner.player_id
	if player_id != null:
		damage_by_player[player_id] = damage_by_player.get(player_id, 0) + amount


func _on_enemy_died(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return
		
	var total_damage = 0
	for dmg in damage_by_player.values():
		total_damage += dmg
		
	var players = get_tree().get_nodes_in_group("Players")
	for player_id in damage_by_player.keys():
		var share = float(damage_by_player[player_id]) / total_damage
		var exp_amount = int(experience_reward * share)
		var player = players[players.find_custom(func(p): return p.player_id == player_id)]
		if player and player.has_method("gain_experience"):
			print("PID: %s did %s%% damage to %s gaining %s exp" % [str(player_id), share*100, name, str(exp_amount)])
			player.gain_experience(exp_amount)
		
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	
	if respawnable:
		get_tree().create_timer(post_death_delay).timeout.connect(pool_deactivate)
		get_tree().create_timer(respawn_delay).timeout.connect(pool_reset)
		
	# On dedicated server, AnimatedSprite2D is stripped, so trigger pooling after delay
	if OS.has_feature("dedicated_server"):
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)

# --- Object Pooling Methods ---

## Deactivates the enemy, making it invisible and non-interactive.
## Called by the spawner when the enemy is returned to the pool.
func pool_deactivate() -> void:
	if _is_being_cleaned_up:
		return
		
	damage_by_player.clear()
	visible = false
	set_process(false)
	set_physics_process(false)
	collision_shape.set_deferred("disabled", true)
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	# Move far away to prevent any lingering interactions.
	global_position = Vector2(INF, INF)


func pool_reset() -> void:
	if _is_being_cleaned_up:
		return
	
	if respawnable:
		global_position = 	initial_position
	
	# Reset health and death state using the component.
	if health_component:
		health_component.respawn()

	# Re-enable visuals, logic, and physics.
	visible = true
	set_process(true)
	set_physics_process(true)
	collision_shape.set_deferred("disabled", false)
	attack_hitbox.monitoring = true
	body_hitbox.monitoring = true


func _update_facing() -> void:
	if _is_being_cleaned_up:
		return
		
	if velocity.x != 0:
		facing_direction = 1 if velocity.x > 0 else -1
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.flip_h = facing_direction < 0


func _on_body_hitbox_body_entered(body: Node) -> void:
	if _is_being_cleaned_up:
		return
		
	if not multiplayer.is_server():
		return
		
	damage_on_overlap(body)


func damage_on_overlap(body: Node):
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
	if _is_being_cleaned_up:
		return
		
	velocity.x = knockback.x
	velocity.y = knockback.y


func _on_animation_finished() -> void:
	if _is_being_cleaned_up:
		return
		
	# If the death animation has just finished, signal to the spawner that this
	# enemy instance is ready to be deactivated and returned to the pool, after a short delay.
	if animated_sprite.animation == "death": # Assumes death animation is named "death"
		# Create a one-shot timer to wait before disappearing.
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)


func emit_ready_for_pooling() -> void:
	"""Emits the signal that the spawner is waiting for."""
	if _is_being_cleaned_up:
		return
	ready_for_pooling.emit()


func cleanup_before_removal():
	print("Cleaning up enemy: ", name)
	_is_being_cleaned_up = true
	
	# Stop all processing
	set_process(false)
	set_physics_process(false)
	
	# Disconnect signals to prevent callbacks during cleanup
	if health_component and health_component.died.is_connected(_on_enemy_died):
		health_component.died.disconnect(_on_enemy_died)
	
	if body_hitbox and body_hitbox.body_entered.is_connected(_on_body_hitbox_body_entered):
		body_hitbox.body_entered.disconnect(_on_body_hitbox_body_entered)
	
	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	
	# Stop state machine processing
	if is_instance_valid(state_machine):
		if state_machine.has_method("cleanup"):
			state_machine.cleanup()
		state_machine.set_process(false)
	
	# Disable collision and monitoring
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if attack_hitbox:
		attack_hitbox.monitoring = false
	if body_hitbox:
		body_hitbox.monitoring = false


# Override _exit_tree to handle cleanup
func _exit_tree():
	cleanup_before_removal()
