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
	var damage_to_deal = 0
	
	# 1. Determine Attack Type and Get Stats
	if current_ability_data and current_level_stats:
		# ABILITY ATTACK PATH (uses AbilityLevelData)
		max_targets = current_level_stats.max_targets
		max_hits = current_level_stats.max_hits
		
	elif current_attack_data != "": 
		# BASIC ATTACK PATH (uses hardcoded basic attack values)
		# Assuming basic attacks hit 1 target 1 time unless specified otherwise
		max_targets = 1 
		max_hits = 1
		
	else:
		# No active attack or attack finished prematurely
		_pending_bodies.clear()
		return
	
	# Sort bodies by distance to owner
	_pending_bodies.sort_custom(func(a, b): 
		return owner_node.global_position.distance_to(a.global_position) < owner_node.global_position.distance_to(b.global_position)
	)
	
	# Process only max_targets closest bodies
	var targets_processed = 0
	for body in _pending_bodies:
		if targets_processed >= max_targets:
			break
		
		var health_comp = body.owner.get("health_component")
		if not health_comp or health_comp.is_dead:
			continue
		
		# Mark this target as hit
		_unique_targets_for_attack[body] = true
		
		# Apply max_hits to this target
		for i in range(max_hits):
			if current_attack_data != "":
				# BASIC ATTACK DAMAGE CALCULATION (Explicitly calling the function)
				var calculated_attack_damage = calculate_attack_damage()
				var min_dmg = roundi(calculated_attack_damage * 0.8)
				var max_dmg = roundi(calculated_attack_damage * 1.2)
				damage_to_deal = randi_range(min_dmg, max_dmg)
				print("CombatComponent: HIT! Basic Attack - Target: %s, Damage: %d" %
					[body.name, damage_to_deal])
				
			elif current_ability_data and current_level_stats:
				# ABILITY ATTACK DAMAGE CALCULATION
				damage_to_deal = calculate_ability_damage(current_ability_data, current_level_stats)
				print("CombatComponent: HIT! Ability Attack: %s - Target: %s, Hit #%d/%d, Damage: %d" %
					[current_ability_data.ability_name, body.name, i + 1, max_hits, damage_to_deal])
			
			health_comp.take_damage(damage_to_deal, self, true)
			hit_list.append(body)
		
		targets_processed += 1
	
	_pending_bodies.clear()


func calculate_ability_damage(_ability: AbilityData, level_stats: AbilityLevelData) -> int:
	var base_damage = _calculate_base_damage()
	
	# Apply ability-specific modifier
	var total_damage_pre_crit: float = base_damage * (level_stats.damage_percent / 100.0)
	
	# Apply variance
	var min_dmg = roundi(total_damage_pre_crit * 0.8)
	var max_dmg = roundi(total_damage_pre_crit * 1.2)
	
	return randi_range(min_dmg, max_dmg)


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
