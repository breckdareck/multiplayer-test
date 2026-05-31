extends Node

## Buff logic for the Staff discipline's Aether Ward.
## When the player takes damage, a portion is absorbed by draining mana instead.

var absorption_rate: float = 0.5
var source_ability_level: int = 1

func on_apply(owner_node: Node, _active_buff) -> void:
	print("Aether Ward (Level %d) activated on %s! Absorbs %.0f%% of damage as mana" % [
		source_ability_level, owner_node.name, absorption_rate * 100.0])

func on_remove(owner_node: Node, _active_buff) -> void:
	print("Aether Ward expired on %s" % owner_node.name)

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass

func on_damaged(owner_node: Node, _active_buff, damage_amount: int, _source: Node) -> void:
	var mana_comp = owner_node.get("mana_component")
	var health_comp = owner_node.get("health_component")
	if not mana_comp or not health_comp:
		return

	# Absorb a portion of damage as mana drain, restore that much HP
	var absorbed: int = roundi(damage_amount * absorption_rate)
	var actual_drain: int = min(absorbed, mana_comp.current_mana)

	if actual_drain > 0:
		mana_comp.current_mana = max(0, mana_comp.current_mana - actual_drain)
		health_comp.current_health = min(health_comp.max_health, health_comp.current_health + actual_drain)

	# Shield breaks when mana runs out
	if mana_comp.current_mana <= 0:
		var buff_comp = owner_node.get_node_or_null("Components/Buff")
		if buff_comp:
			buff_comp.remove_buff("Aether Ward")
