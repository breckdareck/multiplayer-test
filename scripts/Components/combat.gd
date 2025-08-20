class_name CombatComponent
extends Node

@export var attack_map: Dictionary[String, AttackData]
@export var attack_hitbox: CollisionShape2D

var hit_list: Array = []
var current_attack_data: AttackData

var _stats_component: StatsComponent
var _class_component: ClassComponent

@onready var owner_node: CharacterBody2D = get_owner()
@onready var attack_hitbox_timer: Timer = $"../../AttackHitboxTimer" # Adjust path if needed.
@onready var hitbox_area: Area2D = attack_hitbox.get_parent()

func _ready() -> void:
	if not attack_hitbox:
		push_error("CombatComponent: Attack Hitbox not assigned!")
		return
		
	_stats_component = get_parent().get_node_or_null("Stats")
	_class_component = get_parent().get_node_or_null("Class")

	hitbox_area.monitoring = false
	if not hitbox_area.body_entered.is_connected(_on_hitbox_body_entered):
		hitbox_area.body_entered.connect(_on_hitbox_body_entered)

	if not attack_hitbox_timer.timeout.is_connected(_on_attack_hitbox_timer_timeout):
		attack_hitbox_timer.timeout.connect(_on_attack_hitbox_timer_timeout)


func perform_attack(attack_name: String) -> void:
	if not multiplayer.is_server():
		return

	if not attack_map.has(attack_name):
		push_error("Invalid attack name: " + attack_name)
		return
	
	current_attack_data = attack_map[attack_name]
	attack_hitbox_timer.wait_time = current_attack_data.damage_delay
	attack_hitbox_timer.start()

	attack_hitbox.position.x = abs(attack_hitbox.position.x) * owner_node.facing_direction
	
	# Optional: Use another timer to call end_attack() after attack_duration.
	get_tree().create_timer(current_attack_data.attack_duration).timeout.connect(end_attack)


func _on_attack_hitbox_timer_timeout() -> void:
	hit_list.clear()
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

	if body in hit_list:
		return

	if current_attack_data == null:
		push_error("CombatComponent: current_attack_data is null in _on_hitbox_body_entered!")
		return

	if "health_component" in body:
		var health_comp = body.get("health_component")
		if health_comp and not health_comp.is_dead:
			var damage_to_deal = current_attack_data.damage
			var final_damage = damage_to_deal
			
			# Use stats component for damage calculations
			if _stats_component and _class_component:
				if _class_component.current_class == Constants.ClassType.SWORDSMAN:
					# Swordsman gets bonus from strength
					final_damage += _stats_component.get_strength() * 0.2
				elif _class_component.current_class == Constants.ClassType.ARCHER:
					# Archer gets bonus from dexterity
					final_damage += _stats_component.get_dexterity() * 0.15
				elif _class_component.current_class == Constants.ClassType.MAGE:
					# Mage gets bonus from intelligence
					final_damage += _stats_component.get_intelligence() * 0.25
				
				print("CombatComponent: %s attack - Base: %d, Class bonus: %d, Final: %d" % [_class_component.get_class_name(), damage_to_deal, final_damage - damage_to_deal, final_damage])
			
			health_comp.take_damage(final_damage, self)
			hit_list.append(body)
