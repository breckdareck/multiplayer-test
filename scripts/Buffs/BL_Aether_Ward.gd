extends Node

## Buff logic for the Staff discipline's Aether Ward.
## When the player takes damage, a portion is absorbed by draining mana instead.

var absorption_rate: float = 0.5
var source_ability_level: int = 1

func on_apply(_owner_node: Node, _active_buff) -> void:
	pass

func on_remove(_owner_node: Node, _active_buff) -> void:
	pass

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
		# Juice: the ward eating a hit was fully invisible — name the absorb.
		EventJuice.proc(owner_node, "WARD %d" % actual_drain, EventJuice.COLOR_BRITTLE, "res://assets/sounds/generated/sword_guard.wav", "ice_impact")

	# Shield breaks when mana runs out
	if mana_comp.current_mana <= 0:
		# Juice: the shield collapsing under fire is a "you're exposed now" beat.
		EventJuice.proc(owner_node, "WARD BROKEN", EventJuice.COLOR_BRITTLE, "res://assets/sounds/generated/escalation_brittle.wav", "ice_impact")
		var buff_comp = owner_node.get_node_or_null("Components/Buff")
		if buff_comp:
			buff_comp.remove_buff("Aether Ward")
