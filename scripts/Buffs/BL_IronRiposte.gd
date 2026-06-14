extends Node

## Custom logic for Iron Riposte buff
## Reflects a percentage of damage back to attackers
## Cannot reflect more than half of the attacker's max HP

var reflect_percentage: float = 12.0  # Can be set dynamically
var source_ability_level: int = 1     # Track what level cast it

func on_apply(_owner_node: Node, _active_buff) -> void:
	pass

func on_remove(_owner_node: Node, _active_buff) -> void:
	pass


func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	# Optional: Could add a visual effect that pulses each second
	pass


func on_damaged(owner_node: Node, active_buff, damage_amount: int, source: Node) -> void:
	if not source:
		return

	# Calculate reflected damage
	var reflected_damage: int = roundi(damage_amount * (round(reflect_percentage) / 100.0) * active_buff.stacks)

	# Cap reflected damage at half of attacker's max HP
	var attacker_health_comp = source.get("health_component")
	if attacker_health_comp and "max_health" in attacker_health_comp:
		var max_reflect: int = int(attacker_health_comp.max_health / 2.0)
		reflected_damage = min(reflected_damage, max_reflect)
	
	# Apply reflected damage back to the attacker
	if reflected_damage > 0 and attacker_health_comp:
		attacker_health_comp.take_damage(reflected_damage, owner_node, true)
		EventJuice.proc(source, "RIPOSTE %d" % reflected_damage, EventJuice.COLOR_COUNTER, "res://assets/sounds/generated/sword_guard.wav", "phys_impact")
