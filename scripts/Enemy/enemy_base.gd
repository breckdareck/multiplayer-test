class_name EnemyBase
extends CharacterBody2D

# Emitted after the death animation finishes, signaling it can be returned to the pool.
signal ready_for_pooling

@export var enemy_data: EnemyData

@export var respawnable: bool
@export var respawn_delay: int = 10

@export_category("Components")
@export var health_component: HealthComponent
@export var stats_component: StatsComponent

@export_category("Curves")
@export var health_curve: Curve
@export var experience_curve: Curve
@export var wep_att_curve: Curve
@export var magic_att_curve: Curve
@export var wep_def_curve: Curve
@export var magic_def_curve: Curve
@export var monies_curve: Curve

@export_category("UI")
@export var name_label: Label

# Internal properties populated from EnemyData
var monster_name: String
var monster_level: int
var movement_speed: float

@export_category("Drops")
var item_drops: Array[ItemDropResource] = []
const DROPPED_ITEM = preload("uid://b43dktokqxhjo")

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var body_hitbox: Area2D = $BodyHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D


var experience_reward: int = 0:
	get():
		if experience_curve:
			return int(experience_curve.sample(monster_level))
		return 0
var post_death_delay: float = 1.5 # Time to wait after death animation before disappearing.
var damage_by_player: Dictionary = {} # player_id : damage_amount
var facing_direction: int = 1
var _is_being_cleaned_up: bool = false
var initial_position: Vector2


func _apply_enemy_data() -> void:
	monster_name = enemy_data.monster_name
	monster_level = enemy_data.monster_level
	movement_speed = enemy_data.movement_speed
	item_drops = enemy_data.item_drops

	# Set Monies Coin Drop Min and Max Amounts based on Curve
	var filtered_array: Array[ItemDropResource] = item_drops.filter(func(drop): return drop.item_name == "Coin")
	if len(filtered_array) > 0:
		filtered_array[0].min_amount = roundi(monies_curve.sample(monster_level) * 0.9)
		filtered_array[0].max_amount = roundi(monies_curve.sample(enemy_data.monster_level) * 1.1)
	else:
		var monies_drop = ItemDropResource.new()
		monies_drop.drop_chance = 0.9
		monies_drop.min_amount = roundi(monies_curve.sample(monster_level) * 0.9)
		monies_drop.max_amount = roundi(monies_curve.sample(monster_level) * 1.1)
		item_drops.append(monies_drop)

	if animated_sprite:
		animated_sprite.sprite_frames = enemy_data.sprite_frames
	
	if stats_component:
		var curve_stats: Dictionary[Constants.StatType, StatData] = {}
		curve_stats[Constants.StatType.WEAPONATTACK] = StatData.new(Constants.StatType.WEAPONATTACK, roundi(wep_att_curve.sample(monster_level)))
		curve_stats[Constants.StatType.MAGICATTACK] = StatData.new(Constants.StatType.MAGICATTACK, roundi(magic_att_curve.sample(monster_level)))
		curve_stats[Constants.StatType.DEFENSE] = StatData.new(Constants.StatType.DEFENSE, roundi(wep_def_curve.sample(monster_level)))
		curve_stats[Constants.StatType.MAGICDEFENSE] = StatData.new(Constants.StatType.MAGICDEFENSE, roundi(magic_def_curve.sample(monster_level)))
		
		stats_component.stats = curve_stats
		
	var character_collision_shape_node: CollisionShape2D = $CollisionShape2D
	if character_collision_shape_node and enemy_data.character_collision_shape:
		character_collision_shape_node.shape = enemy_data.character_collision_shape
		
	var body_hitbox_shape_node: CollisionShape2D = $BodyHitbox/EnemyBody
	if body_hitbox_shape_node and enemy_data.body_hitbox_shape:
		body_hitbox_shape_node.shape = enemy_data.body_hitbox_shape
		
	var attack_hitbox_shape_node: CollisionShape2D = $AttackHitbox/SlashCollisionShape
	if attack_hitbox_shape_node and enemy_data.attack_hitbox_shape:
		attack_hitbox_shape_node.shape = enemy_data.attack_hitbox_shape


func _ready() -> void:
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)
	if enemy_data:
		_apply_enemy_data()
	else:
		push_error("Enemy '%s' is missing EnemyData resource." % name)
		return
	# Add to networked entities group for proper cleanup during channel switching
	add_to_group("networked_entities")
	add_to_group("Enemies")
	
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

	name_label.text = "Lv.%d %s" % [monster_level, monster_name]
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
		if multiplayer.is_server():
			for pid in _get_players_on_same_map():
				client_show_name_label.rpc_id(pid)


func _on_enemy_died(_killer: Node) -> void:
	call_deferred("_deferred_death_processing", _killer)


func _deferred_death_processing(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return
	
	print("Enemy died. Killer: ", _killer, " Type: ", typeof(_killer))

	var total_damage = 0
	for dmg in damage_by_player.values():
		total_damage += dmg
		
	var killer_player_id = -1
	if _killer.owner is MultiplayerPlayerV2:
		killer_player_id = _killer.owner.player_id
	
	print("Determined killer_player_id: ", killer_player_id)

	var killer_party_id = PartyManager.get_player_party_id(killer_player_id)
	print("Determined killer_party_id: ", killer_party_id)
	
	var players_to_reward: Array[int] = []
	var eligible_player_ids_for_drops: Array[int] = []
	var party_exp_bonus_multiplier = 1.0
	var non_damage_dealer_exp_percentage = 0.25 # 25% of base EXP for non-damage dealers in party

	if killer_party_id != -1:
		# Killer is in a party, distribute EXP to all party members who are on the same map
		var all_party_members = PartyManager.get_party_members(killer_player_id)
		var players_on_map = _get_players_on_same_map()
		
		for member_id in all_party_members:
			if member_id in players_on_map:
				players_to_reward.append(member_id)
				
		print("Players in party on same map to reward: ", players_to_reward)
		# All party members (regardless of map) are eligible for drops
		eligible_player_ids_for_drops = all_party_members
		# Party XP bonus: 10% for 2 members, +5% per additional member (up to 25% at 5 members)
		if players_to_reward.size() > 1:
			party_exp_bonus_multiplier = 1.0 + (0.05 * players_to_reward.size())
		 
		var total_party_damage = 0
		for member_id in players_to_reward:
			if damage_by_player.has(member_id):
				total_party_damage += damage_by_player[member_id]
		print("Total party damage: ", total_party_damage)
		
		for member_id in players_to_reward:
			var exp_amount = 0
			var player_node = PlayerManager.get_player_node(member_id)
			if not player_node:
				print("Could not find player node for member ID: ", member_id)
				continue

			if damage_by_player.has(member_id) and total_party_damage > 0:
				# Player dealt damage, calculate share based on damage
				var share = float(damage_by_player[member_id]) / total_party_damage
				exp_amount = int(experience_reward * share * party_exp_bonus_multiplier)
				print("Member %d (damage dealer) share: %f, base exp: %d, bonus: %f, final exp: %d" % [member_id, share, experience_reward, party_exp_bonus_multiplier, exp_amount])
			else:
				# Player is in party but didn't deal damage, give a fixed percentage
				exp_amount = ceili(experience_reward * non_damage_dealer_exp_percentage * party_exp_bonus_multiplier)
				print("Member %d (non-damage dealer) base exp: %d, non-damage : %f, bonus: %f, final exp: %d" % [member_id, experience_reward, non_damage_dealer_exp_percentage, party_exp_bonus_multiplier, exp_amount])
			
			player_node.gain_experience(exp_amount)
			print("PID: %s (Party) gained %s exp from %s" % [str(member_id), str(exp_amount), name])
	else:
		# No party, distribute EXP only to damage dealers
		players_to_reward.append_array(damage_by_player.keys())
		eligible_player_ids_for_drops = players_to_reward
		print("No party. Players to reward: ", players_to_reward)
		for player_id in players_to_reward:
			var share = float(damage_by_player[player_id]) / total_damage
			var exp_amount = int(experience_reward * share)
			var player_node = PlayerManager.get_player_node(player_id)
			if player_node and player_node.has_method("gain_experience"):
				print("PID: %s did %s%% damage to %s gaining %s exp" % [str(player_id), share * 100, name, str(exp_amount)])
				player_node.gain_experience(exp_amount)
				
	# Record kills for achievement tracking
	for player_id in players_to_reward:
		var player_node = PlayerManager.get_player_node(player_id)
		if player_node and player_node is MultiplayerPlayerV2:
			AchievementManager.record_kill(player_node.username, monster_name)

	# Spawn drops for all eligible players
	if not eligible_player_ids_for_drops.is_empty():
		_spawn_drops(eligible_player_ids_for_drops)
		
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	
	if respawnable:
		get_tree().create_timer(post_death_delay).timeout.connect(pool_deactivate)
		get_tree().create_timer(respawn_delay).timeout.connect(pool_reset)
		
	# On dedicated server, AnimatedSprite2D is stripped, so trigger pooling after delay
	if OS.has_feature("dedicated_server"):
		get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)


func _spawn_drops(eligible_player_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	
	# Server needs to find the map this enemy is in
	var map_instance = null
	
	# Try to find map by walking up the tree to find a parent map container
	var parent = get_parent()
	while parent:
		if parent.name.begins_with("Map_"):
			map_instance = parent
			break
		parent = parent.get_parent()
	
	# If not found by walking tree, try to get from current scene structure
	if not map_instance:
		var root = get_tree().current_scene
		if root:
			var maps_node = root.get_node_or_null("Maps")
			if maps_node:
				# Find any Map_* child
				for child in maps_node.get_children():
					if child.name.begins_with("Map_"):
						map_instance = child
						break
	
	if not map_instance:
		push_error("EnemyBase: Could not determine map instance for enemy %s" % name)
		return

	# Find the GlobalDropHandler specific to this map
	var drop_handler = map_instance.get_node_or_null("GlobalDropHandler")
	if not drop_handler:
		push_error("EnemyBase: GlobalDropHandler not found in map %s" % map_instance.name)
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
		
		# Position it at enemy's location with slight offset to prevent stacking
		var offset = Vector2(randf_range(-10, 10), randf_range(-10, 0))
		var spawn_pos = global_position + offset
		
		# Delegate spawning to GlobalDropHandler which handles RPCs and map filtering
		drop_handler.create_dropped_item(item, amount, spawn_pos, eligible_player_ids, map_instance)
		
		print("Enemy '%s' dropped %dx %s for eligible players: %s" % [name, amount, item.name, str(eligible_player_ids)])


@rpc("any_peer", "call_local", "reliable")
func client_show_name_label():
	name_label.show()
	
@rpc("any_peer", "call_local", "reliable")
func client_hide_name_label():
	name_label.hide()

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
	
	# CRITICAL: Disable the synchronizer to stop sending delta updates
	var sync = get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_process_mode(Node.PROCESS_MODE_DISABLED)
	
	# Move far away to prevent any lingering interactions.
	global_position = Vector2(INF, INF)
	
	if multiplayer.is_server():
		for pid in _get_players_on_same_map():
			client_hide_name_label.rpc_id(pid)


func pool_reset() -> void:
	if _is_being_cleaned_up:
		return
	
	if respawnable:
		global_position = initial_position
	
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
	
	# CRITICAL: Re-enable the synchronizer to resume sending delta updates
	var sync = get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_process_mode(Node.PROCESS_MODE_INHERIT)


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
		var knockback_dir = - body.facing_direction
		var knockback_strength = 120.0
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


func _get_players_on_same_map() -> Array:
	if not multiplayer.is_server(): return []
	
	# Try to find map by walking up the tree to find a parent map container
	var parent = get_parent()
	var map_name = ""
	while parent:
		if parent.name.begins_with("Map_"):
			map_name = parent.name.replace("Map_", "")
			break
		parent = parent.get_parent()
	
	if map_name != "":
		return MapManager.get_players_on_map(map_name)
	return []
