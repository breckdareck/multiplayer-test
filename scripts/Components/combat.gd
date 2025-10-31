class_name CombatComponent
extends Node

@export var attack_hitbox: CollisionShape2D
@export_category("Debug - Weapon Stats")
## Weapon Multipliers = 1.2 ~ 1.75
@export var weapon_multiplier: float = 1.2

# Attack type tracking
enum AttackMode { NONE, BASIC, ABILITY }
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
	if _pending_bodies.is_empty():
		return
	
	var max_targets = 0
	var max_hits = 0
	
	if current_ability_data and current_level_stats:
		max_targets = current_level_stats.max_targets
		max_hits = current_level_stats.max_hits
	elif current_attack_data != "": 
		max_targets = 1 
		max_hits = 1
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
		
		var target_enemy = body.owner
		var attacker_level = owner_node.level_component.level
		var target_level = target_enemy.monster_level

		# --- Hit Chance Calculation ---
		var level_diff = attacker_level - target_level
		# Base 95% chance to hit. Lose 2% chance for each level the monster is above you.
		var hit_chance = clamp(95.0 + (level_diff * 2.0), 5.0, 100.0)
		
		for i in range(max_hits):
			var roll = randf() * 100
			if roll > hit_chance:
				var miss_spawn_pos = health_comp.damage_number_origin.global_position + Vector2(randf_range(-8, 8), randf_range(-5, 5))
				get_node("/root/MainMenu/Level/Game").get_node("%DmgNumberSpawner").display_number(-1, miss_spawn_pos, false, false)
				print("Attack MISSED! (Roll: %.2f > Chance: %.2f)" % [roll, hit_chance])
				continue # Skip to the next hit

			# --- Damage Calculation ---
			var base_damage = 0
			if current_attack_data != "":
				base_damage = calculate_attack_damage()
			elif current_ability_data and current_level_stats:
				base_damage = calculate_ability_damage(current_ability_data, current_level_stats)

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
			
			health_comp.take_damage(damage_to_deal, self, true, is_crit)
			hit_list.append(body)
			
			if _ability_component:
				var event_type = "on_crit" if is_crit else "on_hit"
				var context = {
					"base_damage": damage_to_deal,
					"target": body.owner,
					"is_crit": is_crit
				}
				_ability_component.try_trigger_procs(event_type, body.owner, context)
		
		targets_processed += 1
	
	_pending_bodies.clear()


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
