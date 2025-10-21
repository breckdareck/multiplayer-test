extends Node

## Custom logic for Power Guard buff
## Reflects a percentage of damage back to attackers
## Cannot reflect more than half of the attacker's max HP

var reflect_percentage: float = 12.0  # Can be set dynamically
var source_ability_level: int = 1     # Track what level cast it

func on_apply(owner_node: Node, active_buff) -> void:
	print("Power Guard (Level %d) activated on %s! Reflects %.0f%% damage" % 
		[source_ability_level, owner_node.name, reflect_percentage])
		

func on_remove(owner_node: Node, active_buff) -> void:
	print("Power Guard expired on %s" % owner_node.name)


func on_tick(owner_node: Node, active_buff, delta: float) -> void:
	# Optional: Could add a visual effect that pulses each second
	pass


func on_damaged(owner_node: Node, active_buff, damage_amount: int, source: Node) -> void:
	if not source:
		return
	
	
	print("Recieved Dmg Amount: %d" % damage_amount)
	print("Power Guard: On Damaged %d%% " % round(reflect_percentage))
	
	
	# Calculate reflected damage
	var reflected_damage: int = roundi(damage_amount * (round(reflect_percentage) / 100.0) * active_buff.stacks)
	
	print("Reflected Dmg: %d" % reflected_damage)
	
	# Cap reflected damage at half of attacker's max HP
	var attacker_health_comp = source.get("health_component")
	if attacker_health_comp and "max_health" in attacker_health_comp:
		var max_reflect: int = int(attacker_health_comp.max_health / 2.0)
		reflected_damage = min(reflected_damage, max_reflect)
	
	# Apply reflected damage back to the attacker
	if reflected_damage > 0 and attacker_health_comp:
		print("Power Guard reflects %d damage back to %s!" % [reflected_damage, source.name])
		attacker_health_comp.take_damage(reflected_damage, owner_node, true)
