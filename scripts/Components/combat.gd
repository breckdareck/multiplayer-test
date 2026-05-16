class_name CombatComponent
extends Node

signal dealt_damage(target: Node, damage_values: Array, crit_values: Array)

@export var attack_hitbox: CollisionShape2D
@export_category("Debug - Weapon Stats")
## Weapon Multipliers = 1.2 ~ 1.75
@export var weapon_multiplier: float = 1.2

# Attack type tracking
enum AttackMode {NONE, BASIC, ABILITY}
var _current_attack_mode: AttackMode = AttackMode.NONE

# Basic attack data
var current_attack_data: String = "" # Using string ID as a flag for basic attack

# Ability attack data
var current_ability_data: AbilityData = null
var current_active_data: ActiveBehaviorData = null
var current_level_stats: AbilityLevelData = null

var hit_list: Array = []
var _unique_targets_for_attack: Dictionary = {}
var _pending_bodies: Array = []

var attack_damage: int:
	get:
		return calculate_attack_damage()
var min_damage: int:
	get:
		return roundi(attack_damage * 0.8)
var max_damage: int:
	get:
		return roundi(attack_damage * 1.2)

var original_attack_shape: Shape2D
var original_attack_transform: Vector2

var _stats_component: StatsComponent
var _class_component: ClassComponent
var _equipment_component: EquipmentComponent
var _ability_component: AbilityComponent

@onready var owner_node: CharacterBody2D = get_owner()
@onready var attack_hitbox_timer: Timer = $"../../AttackHitboxTimer"
@onready var hitbox_area: Area2D = attack_hitbox.get_parent()

func _ready() -> void:
	if not attack_hitbox:
		push_error("CombatComponent: Attack Hitbox not assigned!")
		return
	
	original_attack_shape = attack_hitbox.shape
	original_attack_transform = attack_hitbox.position
		
	_stats_component = get_parent().get_node_or_null("Stats")
	_class_component = get_parent().get_node_or_null("Class")
	_equipment_component = get_parent().get_node_or_null("Equipment")
	_ability_component = get_parent().get_node_or_null("Ability")

	hitbox_area.monitoring = false
	
	# Connect to hitbox area
	if not hitbox_area.area_entered.is_connected(_on_hitbox_area_entered):
		hitbox_area.area_entered.connect(_on_hitbox_area_entered)


func perform_attack(_attack_name: String, _duration: float) -> void:
	"""Called by the attack state when a basic attack is triggered"""
	if not multiplayer.is_server():
		return
		
	if current_attack_data != "" or current_ability_data != null:
		print("CombatComponent: Attack already in progress.")
		return
		
	# Set basic attack flag and data
	_current_attack_mode = AttackMode.BASIC
	current_attack_data = _attack_name
	
	attack_hitbox.shape = original_attack_shape
	attack_hitbox.position = original_attack_transform
	
	turn_on_hitbox()
	
	# Optional: Use another timer to call end_attack() after attack_duration.
	get_tree().create_timer(0.1).timeout.connect(end_attack)


const BASIC_ARROW_SCENE = preload("uid://d0ig4oiimrnei")
const BASIC_ARROW_SPEED: float = 250.0

func perform_ranged_attack(_attack_name: String, _duration: float) -> void:
	if not multiplayer.is_server():
		return

	if current_attack_data != "" or current_ability_data != null:
		return

	_current_attack_mode = AttackMode.BASIC
	current_attack_data = _attack_name

	if not _ability_component:
		return

	var direction := Vector2(owner_node.facing_direction, 0).normalized()
	var projectile := BASIC_ARROW_SCENE.instantiate()
	projectile.initialize(owner_node, null, null, null, BASIC_ARROW_SPEED, direction)
	projectile.set_meta("basic_attack_caster", owner_node)

	var current_map = owner_node.get_parent().get_parent()
	var container: Node = null
	if current_map and current_map.is_in_group("map_base"):
		container = current_map.get_node_or_null("Projectiles")
		if not container:
			container = Node.new()
			container.name = "Projectiles"
			current_map.add_child(container)
	if not container:
		return

	container.add_child(projectile, true)
	if is_instance_valid(owner_node.projectile_spawn_location):
		projectile.global_position = owner_node.projectile_spawn_location.global_position
	else:
		projectile.global_position = owner_node.global_position

	get_tree().create_timer(0.1).timeout.connect(func(): current_attack_data = "")


func process_ability_hit(ability: AbilityData, level_stats: AbilityLevelData) -> void:
	"""Called by the attack state when an ability attack is triggered"""
	if not multiplayer.is_server():
		return

	if current_attack_data != "" or current_ability_data != null:
		print("CombatComponent: Attack already in progress.")
		return

	_current_attack_mode = AttackMode.ABILITY
	current_ability_data = ability
	current_active_data = ability.active_behavior
	current_level_stats = level_stats
	
	attack_hitbox.shape = ability.active_behavior.hit_box_shape_data
	attack_hitbox.position = ability.active_behavior.hit_box_position_data

	turn_on_hitbox()
	
	var attack_duration = level_stats.cast_time
	if attack_duration <= 0.0:
		# Ensure a minimum duration for the hitbox to register hits in a single frame
		attack_duration = 0.05

	get_tree().create_timer(attack_duration).timeout.connect(end_ability_attack)


func turn_on_hitbox() -> void:
	if not multiplayer.is_server():
		return
		
	attack_hitbox.position.x = abs(attack_hitbox.position.x) * owner_node.facing_direction
	
	hit_list.clear()
	_unique_targets_for_attack.clear()
	_pending_bodies.clear()
		
	hitbox_area.monitoring = true


func end_attack() -> void:
	if not multiplayer.is_server():
		return
		
	_process_collected_bodies()
	
	hitbox_area.monitoring = false
	_current_attack_mode = AttackMode.NONE
	current_attack_data = ""


func end_ability_attack() -> void:
	if not multiplayer.is_server():
		return
		
	_process_collected_bodies()
		
	hitbox_area.monitoring = false
	_current_attack_mode = AttackMode.NONE
	current_ability_data = null
	current_active_data = null
	current_level_stats = null
	
	hit_list.clear()
	_unique_targets_for_attack.clear()


func _on_hitbox_area_entered(area: Area2D) -> void:
	if not multiplayer.is_server():
		return
	print("Hit: %s" % area.owner.name)
	if not "health_component" in (area.owner as EnemyBase):
		return
		
	var health_comp = area.owner.get("health_component")
	if not health_comp or health_comp.is_dead:
		return
	
	# NEW: Just collect the body, don't process yet
	if not _pending_bodies.has(area):
		_pending_bodies.append(area)


func _process_collected_bodies() -> void:
	# For projectiles, we might fire even if no body was collected.
	if current_ability_data and current_ability_data.active_behavior.is_projectile:
		# Sort bodies by distance to prioritize closest targets
		_pending_bodies.sort_custom(func(a, b):
			return owner_node.global_position.distance_squared_to(a.global_position) < owner_node.global_position.distance_squared_to(b.global_position)
		)

		var max_targets = current_level_stats.max_targets
		var targets_processed = 0

		for body_area in _pending_bodies:
			if targets_processed >= max_targets:
				break

			var health_comp = body_area.owner.get("health_component")
			if health_comp and not health_comp.is_dead:
				if _ability_component:
					# Spawn one projectile for each valid target
					_ability_component.spawn_projectile(current_ability_data, current_level_stats, body_area.owner)
				targets_processed += 1
		
		# If no targets were in the hitbox, spawn one projectile straight ahead
		if targets_processed == 0:
			if _ability_component:
				_ability_component.spawn_projectile(current_ability_data, current_level_stats, null)

		_pending_bodies.clear()
		return # We are done for projectiles

	# Melee / Hitbox attack processing
	if _pending_bodies.is_empty():
		return

	var max_targets = 0
	
	if current_ability_data and current_level_stats:
		max_targets = current_level_stats.max_targets
	elif current_attack_data != "":
		max_targets = 1
	else:
		_pending_bodies.clear()
		return
	
	_pending_bodies.sort_custom(func(a, b):
		return owner_node.global_position.distance_to(a.global_position) < owner_node.global_position.distance_to(b.global_position)
	)
	
	var targets_processed = 0
	for body in _pending_bodies:
		if targets_processed >= max_targets:
			break
		
		var health_comp = body.owner.get("health_component")
		if not health_comp or health_comp.is_dead:
			continue
		
		_unique_targets_for_attack[body] = true
		
		# Execute the full hit logic for this target
		_execute_hit(body.owner, current_ability_data, current_level_stats, current_attack_data)
		
		targets_processed += 1
	
	_pending_bodies.clear()


func process_projectile_hit(target_enemy: Node, ability: AbilityData, level_stats: AbilityLevelData) -> void:
	"""Public function for projectiles to call when they hit a target."""
	if not multiplayer.is_server():
		return

	print("CombatComponent: Processing projectile hit on %s" % target_enemy.name)
	var attack_name := "basic_arrow" if ability == null else ""
	_execute_hit(target_enemy, ability, level_stats, attack_name)


func _execute_hit(target_enemy: Node, ability: AbilityData, level_stats: AbilityLevelData, attack_name: String) -> void:
	"""Runs the full, authoritative damage calculation for a single hit on a single target."""
	var health_comp = target_enemy.get("health_component")
	if not health_comp or health_comp.is_dead:
		return

	var attacker_level = owner_node.level_component.level
	var target_level = target_enemy.monster_level

	# --- Hit Chance Calculation ---
	var level_diff = attacker_level - target_level
	# Base 95% chance to hit. Lose 2% chance for each level the monster is above you.
	var hit_chance = clamp(95.0 + (level_diff * 2.0), 5.0, 100.0)
	
	var max_hits = 1
	if ability and level_stats:
		max_hits = level_stats.max_hits
	
	var damage_values: Array = []
	var crit_values: Array = []
	
	for i in range(max_hits):
		var roll = randf() * 100
		if roll > hit_chance:
			damage_values.append(-1) # -1 signifies a MISS
			crit_values.append(false)
			print("Attack MISSED! (Roll: %.2f > Chance: %.2f)" % [roll, hit_chance])
			continue # Skip to the next hit

		# --- Damage Calculation ---
		var base_damage = 0
		if attack_name != "":
			base_damage = calculate_attack_damage()
		elif ability and level_stats:
			base_damage = calculate_ability_damage(ability, level_stats)

		var modified_damage = float(base_damage)

		if target_enemy.has_node("Stats"):
			var target_stats = target_enemy.get_node("Stats")
			var target_defense = target_stats.stats.get(Constants.StatType.DEFENSE).total_value

			var level_modifier = clamp(1.0 + (level_diff * 0.05), 0.5, 1.5)
			var defense_multiplier = 1.0 - (float(target_defense) / (target_defense + 500.0))

			modified_damage *= level_modifier * defense_multiplier
		
		var crit_chance = _stats_component.stats.get(Constants.StatType.CRITCHANCE).total_value
		var is_crit = (randf() * 100) < crit_chance
		
		if is_crit:
			var crit_damage_bonus = _stats_component.stats.get(Constants.StatType.CRITDAMAGE).total_value
			var crit_multiplier = randf_range(1.2, 1.5) + (crit_damage_bonus / 100.0)
			modified_damage *= crit_multiplier
		else:
			modified_damage *= randf_range(0.8, 1.2)

		var damage_to_deal = roundi(modified_damage)
		
		damage_values.append(damage_to_deal)
		crit_values.append(is_crit)
		
		health_comp.take_damage(damage_to_deal, self, true, is_crit, false)

		if damage_to_deal > 0:
			# Knockback logic
			var knockback_dir = owner.facing_direction
			var knockback_strength = 90.0
			var knockback_lift = -90.0
			var knockback_vec = Vector2(knockback_dir * knockback_strength, knockback_lift)
			if target_enemy.has_method("apply_knockback"):
				target_enemy.apply_knockback(knockback_vec)

		if _ability_component:
			var event_type = "on_crit" if is_crit else "on_hit"
			var context = {
				"base_damage": damage_to_deal,
				"target": target_enemy,
				"is_crit": is_crit
			}
			_ability_component.try_trigger_procs(event_type, target_enemy, context)

	# Apply target debuff if the ability defines one
	if ability and ability.applies_target_debuff and target_enemy is EnemyBase:
		var debuff_duration := 10.0
		if ability.debuff_duration_formula:
			debuff_duration = ability.debuff_duration_formula.calculate(level_stats.level)
		_apply_enemy_debuff(target_enemy, ability.applies_target_debuff, debuff_duration)

	# After the loop, emit signal first so listeners (e.g. Shadow Partner) can append hits
	if not damage_values.is_empty():
		dealt_damage.emit(target_enemy, damage_values, crit_values)

		# Now display the combined combo (signal handlers may have appended to the arrays)
		var spawn_pos = health_comp.damage_number_origin.global_position
		var dmg_spawner = null
		var map_to_spawn_on: Node = null
		var attacker = owner_node

		if attacker is MultiplayerPlayerV2:
			map_to_spawn_on = MapManager.get_player_map_node(attacker.player_id)
		else:
			for map_id in MapManager.active_maps.keys():
				var map_instance = MapManager.active_maps[map_id].scene_instance
				if is_instance_valid(map_instance) and map_instance.is_ancestor_of(attacker):
					map_to_spawn_on = map_instance
					break

		if is_instance_valid(map_to_spawn_on):
			dmg_spawner = map_to_spawn_on.find_child("DmgNumberSpawner", true, false)

		if dmg_spawner:
			dmg_spawner.display_number_combo(damage_values, crit_values, spawn_pos)


func calculate_ability_damage(_ability: AbilityData, level_stats: AbilityLevelData) -> int:
	var base_damage = _calculate_base_damage()
	
	# Apply ability-specific damage modifier from level stats
	var ability_damage = base_damage * (level_stats.damage_percent / 100.0)
	
	# NEW: Apply passive ability damage modifiers (Enhanced Basics)
	if _ability_component:
		var passive_modifier = _ability_component.get_ability_damage_modifier(_ability.ability_id)
		ability_damage *= passive_modifier
		print("Applied passive damage modifier: %.2fx" % passive_modifier)
	
	return roundi(ability_damage)


func calculate_attack_damage() -> int:
	# TODO: FIX THIS TO USE BASED ON THE CLASS AKA WEAPON ATTACK VS MAGIC ATTACK
	if not (_equipment_component and _equipment_component.weapon_slot and _equipment_component.weapon_slot.item):
		return 0
	
	var base_damage = _calculate_base_damage()
	return roundi(base_damage)


func _calculate_base_damage() -> int:
	if not _stats_component or not _class_component:
		return 0

	var weapon_attack = _stats_component.stats.get(Constants.StatType.WEAPONATTACK).total_value
	
	var primary_stat_type = ResourceManager.get_primary_stat(_class_component.current_class)
	var secondary_stat_type = ResourceManager.get_secondary_stat(_class_component.current_class)
	
	var primary_stat_value = _stats_component.stats.get(primary_stat_type).total_value
	var secondary_stat_value = _stats_component.stats.get(secondary_stat_type).total_value
	
	var stat_contribution: float = (primary_stat_value * 4 + secondary_stat_value)
	
	# This is the core shared formula
	return roundi(weapon_multiplier * stat_contribution * weapon_attack / 100.0)


func _apply_enemy_debuff(enemy: EnemyBase, debuff: BuffData, duration: float) -> void:
	if not enemy.stats_component:
		return

	var debuff_key := "debuff_%s" % debuff.buff_name
	if enemy.has_meta(debuff_key):
		return

	var saved_values: Dictionary = {}
	for stat_type in debuff.stat_modifiers:
		var modifier: StatData = debuff.stat_modifiers[stat_type]
		if enemy.stats_component.stats.has(stat_type):
			var enemy_stat: StatData = enemy.stats_component.stats[stat_type]
			saved_values[stat_type] = {
				"flat": enemy_stat.flat_bonus_value,
				"percent": enemy_stat.percent_bonus_value
			}
			enemy_stat.flat_bonus_value += modifier.flat_bonus_value
			enemy_stat.percent_bonus_value += modifier.percent_bonus_value

	enemy.set_meta(debuff_key, true)

	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		enemy.animated_sprite.modulate = Color(0.6, 0.5, 0.8, 1.0)

	get_tree().create_timer(duration).timeout.connect(
		func():
			if not is_instance_valid(enemy) or not is_instance_valid(enemy.stats_component):
				return
			for stat_type in saved_values:
				if enemy.stats_component.stats.has(stat_type):
					var enemy_stat: StatData = enemy.stats_component.stats[stat_type]
					enemy_stat.flat_bonus_value = saved_values[stat_type]["flat"]
					enemy_stat.percent_bonus_value = saved_values[stat_type]["percent"]
			enemy.remove_meta(debuff_key)
			if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
				enemy.animated_sprite.modulate = Color.WHITE
			print("Debuff '%s' expired on %s" % [debuff.buff_name, enemy.name])
	)
	print("Applied debuff '%s' to %s for %.1fs" % [debuff.buff_name, enemy.name, duration])
