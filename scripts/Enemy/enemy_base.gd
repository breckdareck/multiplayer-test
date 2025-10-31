class_name EnemyBase
extends CharacterBody2D

# Emitted after the death animation finishes, signaling it can be returned to the pool.
signal ready_for_pooling

@export var health_component: HealthComponent
@export var stats_component: StatsComponent
@export var monster_level: int = 1
@export var movement_speed: float = 60.0
@export var health_curve: Curve
@export var experience_curve: Curve
@export var respawnable: bool
@export var respawn_delay: int = 10

@export_category("Drops")
@export var item_drops: Array[ItemDropResource] = []
const DROPPED_ITEM = preload("uid://b43dktokqxhjo")

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
		_spawn_drops(player)
		
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	
	if respawnable:
		get_tree().create_timer(post_death_delay).timeout.connect(pool_deactivate)
		get_tree().create_timer(respawn_delay).timeout.connect(pool_reset)
		
	# On dedicated server, AnimatedSprite2D is stripped, so trigger pooling after delay
	if OS.has_feature("dedicated_server"):
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)


func _spawn_drops(player: MultiplayerPlayerV2) -> void:
	if not multiplayer.is_server():
		return
	
	for drop_resource in item_drops:
		if drop_resource == null:
			continue
		
		# Check if this drop should occur
		if not drop_resource.should_drop():
			continue
		
		# Get the item data
		var item = drop_resource.get_item_data()
		if item == null:
			push_warning("Item '%s' not found in ResourceManager" % drop_resource.item_name)
			continue
		
		# Determine stack amount
		var amount = drop_resource.get_drop_amount()
		
		# Create dropped item instance
		var dropped_item = DROPPED_ITEM.instantiate() as DroppedItem
		
		# Position it at enemy's location with slight offset to prevent stacking
		var offset = Vector2(randf_range(-10, 10), randf_range(-10, 0))
		dropped_item.global_position = global_position + offset
		
		# Setup the dropped item
		dropped_item.setup(item, amount, player)
		
		# Add to scene
		get_tree().current_scene.get_node("Level/Game").add_child(dropped_item, true)
		
		rpc("client_setup_item", dropped_item.get_path(), item.item_id)
		
		print("Enemy '%s' dropped %dx %s for player %s" % [name, amount, item.name, player.username])

@rpc
func client_setup_item(dropped_item: NodePath, item_id: String):
	(get_node(dropped_item) as DroppedItem).sprite.texture = ResourceManager.get_item_data(item_id).icon

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


func _get_a_coefficient(level_diff: int) -> float:
	# New formula: Damage is modified by 5% for every level of difference.
	# If player is 10 levels lower (diff = -10), monster deals 50% more damage (A = 1.5).
	# If player is 10 levels higher (diff = 10), monster deals 50% less damage (A = 0.5).
	var modifier = 1.0 - (level_diff * 0.05)
	return clamp(modifier, 0.1, 5.0) # Clamp damage from 10% to 500%

func _get_b_coefficient(level_diff: int) -> float:
	if level_diff >= 0: return 1.00
	if level_diff == -1: return 0.99
	if level_diff == -2: return 0.98
	if level_diff == -3: return 0.97
	if level_diff == -4: return 0.96
	if level_diff == -5: return 0.95
	if level_diff == -6: return 0.94
	if level_diff == -7: return 0.93
	if level_diff == -8: return 0.92
	if level_diff == -9: return 0.91
	if level_diff == -10: return 0.90
	if level_diff == -11: return 0.88
	if level_diff == -12: return 0.86
	if level_diff == -13: return 0.84
	if level_diff == -14: return 0.82
	if level_diff == -15: return 0.80
	if level_diff == -16: return 0.78
	if level_diff == -17: return 0.76
	if level_diff == -18: return 0.74
	if level_diff == -19: return 0.72
	if level_diff == -20: return 0.70
	if level_diff == -21: return 0.68
	if level_diff == -22: return 0.66
	if level_diff == -23: return 0.64
	if level_diff == -24: return 0.62
	if level_diff == -25: return 0.60
	if level_diff == -26: return 0.58
	if level_diff == -27: return 0.56
	if level_diff == -28: return 0.54
	if level_diff == -29: return 0.52
	return 0.50 # -30 or lower

func damage_on_overlap(body: Node):
	if not stats_component:
		push_warning("Enemy %s is missing a StatsComponent! Cannot calculate damage." % name)
		return

	if body.has_node("Components/Health"):
		var health: HealthComponent = body.get_node("Components/Health")
		var player_stats: StatsComponent = body.get_node("Components/Stats")
		var player_level_comp: LevelingComponent = body.get_node("Components/Leveling")
		
		if health.is_dead or health.is_invulnerable:
			return

		# --- New Monster Damage Calculation ---
		var monster_att = stats_component.stats.get(Constants.StatType.WEAPONATTACK).total_value
		var player_def = player_stats.stats.get(Constants.StatType.DEFENSE).total_value
		var level_diff = player_level_comp.level - monster_level

		var a = _get_a_coefficient(level_diff)
		var b = _get_b_coefficient(level_diff)

		# Calculate Min Damage
		var b_def_min = b * player_def
		b_def_min = min(b_def_min, 0.68 * monster_att)
		var min_damage = a * (0.85 * monster_att - b_def_min)
		min_damage = max(1, min_damage)

		# Calculate Max Damage
		var b_def_max = b * player_def
		b_def_max = min(b_def_max, 0.80 * monster_att)
		var max_damage = a * (monster_att - b_def_max)
		max_damage = max(min_damage, max_damage)

		var final_damage = randi_range(roundi(min_damage), roundi(max_damage))

		health.take_damage(final_damage, self)

		# Knockback logic
		var knockback_dir = -body.facing_direction
		var knockback_strength = 150.0
		var knockback_lift = -100.0
		var knockback_vec = Vector2(knockback_dir * knockback_strength, knockback_lift)
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
