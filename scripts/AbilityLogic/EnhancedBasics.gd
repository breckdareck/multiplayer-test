class_name IronBodyLogic
extends RefCounted

func execute(caster: Node, ability: AbilityData, stats: AbilityLevelData):
	# Find the dedicated buff system
	var buff_comp = caster.get_node("Buffs") 

	var buff_data = {
		"source": ability.ability_name,
		"duration": stats.cooldown_time, # Or a separate buff duration field
		"modifiers": { "DEFENSE": 50 + stats.level * 10 }
	}
	
	# Apply to self
	buff_comp.apply_buff(caster, buff_data)
