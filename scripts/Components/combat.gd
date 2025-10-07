class_name CombatComponent
extends Node

@export var attack_hitbox: CollisionShape2D
@export_category("Debug - Weapon Stats")
## Weapon Multipliers = 1.2 ~ 1.75
@export var weapon_multiplier: float = 1.2


var current_ability_data: AbilityData = null 
var current_active_data: ActiveBehaviorData = null
var current_damage_data: DamageData = null


var hit_list: Array = []
var _unique_targets_for_attack: Dictionary = {}


var current_attack_data: AttackData
var attack_damage: int:
	get:
		return calculate_attack_damage()
var min_damage: int:
	get:
		return roundi(attack_damage * 0.8)
var max_damage: int:
	get:
		return roundi(attack_damage * 1.2)
		
var _stats_component: StatsComponent
var _class_component: ClassComponent
var _equipment_component: EquipmentComponent

@onready var owner_node: CharacterBody2D = get_owner()
@onready var attack_hitbox_timer: Timer = $"../../AttackHitboxTimer" # Adjust path if needed.
@onready var hitbox_area: Area2D = attack_hitbox.get_parent()

func _ready() -> void:
	if not attack_hitbox:
		push_error("CombatComponent: Attack Hitbox not assigned!")
		return
		
	_stats_component = get_parent().get_node_or_null("Stats")
	_class_component = get_parent().get_node_or_null("Class")
	_equipment_component = get_parent().get_node_or_null("Equipment")

	hitbox_area.monitoring = false
	if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)


func perform_attack(_attack_name: String, _duration: float) -> void:
	if not multiplayer.is_server():
		return
	
	turn_on_hitbox()
	
	# Optional: Use another timer to call end_attack() after attack_duration.
	get_tree().create_timer(0.1).timeout.connect(end_attack)


func turn_on_hitbox() -> void:
	if not multiplayer.is_server():
		return
		
	attack_hitbox.position.x = abs(attack_hitbox.position.x) * owner_node.facing_direction
	
	hit_list.clear()
	_unique_targets_for_attack.clear()
	
	if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)
		
	hitbox_area.monitoring = true


func end_attack() -> void:
	if not multiplayer.is_server():
		return
	hitbox_area.monitoring = false
	current_attack_data = null


func _on_hitbox_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return

	if not "health_component" in body:
		return
		
	var health_comp = body.get("health_component")
	if not health_comp or health_comp.is_dead:
		return
		
	var max_targets = 2
	var max_hits = 2
	if current_damage_data:
		max_targets = current_damage_data.max_targets
		max_hits = current_damage_data.max_hits

	var is_new_target = not _unique_targets_for_attack.has(body)
	
	if is_new_target:
		if _unique_targets_for_attack.size() >= max_targets:
			return
		_unique_targets_for_attack[body] = true 
		
	var hits_on_body = hit_list.count(body)
	
	if is_new_target:
		var hits_to_apply = max_hits 
		for i in range(hits_to_apply): 
			var is_first_hit = (i == 0)
			var ignore_invuln_flag = not is_first_hit
			var damage_to_deal = randi_range(min_damage, max_damage)

			health_comp.take_damage(damage_to_deal, self, ignore_invuln_flag)

			hit_list.append(body)

			print("CombatComponent: HIT! Ability Attack - Target: %s, Hit #%d/%d, IgnoreInvuln: %s, Damage: %d" %
				[body.name, hits_on_body + i + 1, max_hits, str(ignore_invuln_flag), damage_to_deal])


func calculate_attack_damage() -> int:
	# TODO: FIX THIS TO USE BASED ON THE CLASS AKA WEAPON ATTACK VS MAGIC ATTACK
	
	if current_ability_data and current_damage_data:
		var damage_data = current_damage_data
		var ability_percent = damage_data.damage_percent
		var fixed_damage = damage_data.fixed_damage
		var scaling_stat_name = damage_data.scaling_stat
		
		var primary_stat_value = _stats_component.stats.get(scaling_stat_name).total_value
		var weapon_attack = _stats_component.stats.get(Constants.StatType.WEAPONATTACK).total_value # Or MAGICATTACK
		
		# Maplestory-like Ability Damage Formula:
		# FinalDamage = [PrimaryStat * Multiplier * WeaponAttack / 100] * (AbilityPercent / 100) + FixedDamage
		
		# Simplified Example (you'll refine this formula):
		var base_damage = roundi(weapon_multiplier * primary_stat_value * weapon_attack / 100)
		var final_damage = roundi(base_damage * (float(ability_percent) / 100.0)) + fixed_damage
		
		return final_damage
	else:
		var weapon_attack = 0 # Default attack if no weapon
		if _equipment_component and _equipment_component.weapon_slot and _equipment_component.weapon_slot.item and _stats_component:
			weapon_attack = _stats_component.stats.get(Constants.StatType.WEAPONATTACK).total_value
			if _class_component:
				var primary_stat = ResourceManager.get_primary_stat(_class_component.current_class)
				var secondary_stat = ResourceManager.get_secondary_stat(_class_component.current_class)
				var stats_value = _stats_component.stats.get(primary_stat).total_value * 4 + _stats_component.stats.get(secondary_stat).total_value
				return roundi(weapon_multiplier * stats_value * weapon_attack / 100)
		return 0


func process_ability_hit(ability: AbilityData) -> void:
	if not multiplayer.is_server():
		return

	current_ability_data = ability
	current_active_data = ability.active_behavior
	current_damage_data = ability.damage_data

	turn_on_hitbox()

	var attack_duration = 0.1 # Placeholder: Use ability.active_behavior.animation_length
	get_tree().create_timer(attack_duration).timeout.connect(end_ability_attack)


func end_ability_attack() -> void:
	if not multiplayer.is_server():
		return
		
	hitbox_area.monitoring = false
	current_ability_data = null
	current_active_data = null
	current_damage_data = null
	
	hit_list.clear()
	_unique_targets_for_attack.clear()
