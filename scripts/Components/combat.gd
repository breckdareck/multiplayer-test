class_name CombatComponent
extends Node

@export var attack_map: Dictionary[String, AttackData]
@export var attack_hitbox: CollisionShape2D
@export_category("Debug - Weapon Stats")
## Weapon Multipliers = 1.2 ~ 1.75
@export var weapon_multiplier: float = 1.2

var hit_list: Array = []
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


func perform_attack(attack_name: String, duration: float) -> void:
	if not multiplayer.is_server():
		return
	
	turn_on_hitbox()
	
	# Optional: Use another timer to call end_attack() after attack_duration.
	get_tree().create_timer(duration).timeout.connect(end_attack)


func turn_on_hitbox() -> void:
	attack_hitbox.position.x = abs(attack_hitbox.position.x) * owner_node.facing_direction
	
	#hit_list.clear()
	hitbox_area.monitoring = true

	var overlapping_bodies = hitbox_area.get_overlapping_bodies()
	for body in overlapping_bodies:
		_on_hitbox_body_entered(body)


func end_attack() -> void:
	if not multiplayer.is_server():
		return
	hitbox_area.monitoring = false
	current_attack_data = null


func _on_hitbox_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return

	#if body in hit_list:
		#return

	if "health_component" in body:
		var health_comp = body.get("health_component")
		if health_comp and not health_comp.is_dead:
			var damage_to_deal = randi_range(min_damage, max_damage)
			
			print("CombatComponent: %s attack - Min: %d, Max: %d, Final: %d" % [_class_component.get_class_name(), min_damage, max_damage, damage_to_deal])
			
			health_comp.take_damage(damage_to_deal, self)
			hit_list.append(body)


func calculate_attack_damage() -> int:
	var weapon_attack = 0 # Default attack if no weapon
	if _equipment_component and _equipment_component.weapon_slot and _equipment_component.weapon_slot.item:
		var weapon_data = _equipment_component.weapon_slot.item as WeaponData
		if weapon_data:
			weapon_attack = weapon_data.weapon_attack

	if _stats_component and _class_component:
		var primary_stat = ResourceManager.get_primary_stat(_class_component.current_class)
		var secondary_stat = ResourceManager.get_secondary_stat(_class_component.current_class)
		var stats_value = _stats_component.stats.get(primary_stat).total_value * 4 + _stats_component.stats.get(secondary_stat).total_value
		return roundi(weapon_multiplier * stats_value * weapon_attack / 100)
	return 0
