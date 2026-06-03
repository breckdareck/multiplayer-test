extends Node

func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	var buff_component = _owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return
	
	var duration = _ability.buff_duration_formula.calculate(_level_stats.level)

	# Calculate reflect percentage based on ability level
	var reflect_percent = round(12 + ((_level_stats.level - 1)  * 2))  # 12% + 2% per level

	# PR 6 upgrades: buff_duration_bonus (+s) and reflect_bonus (+% reflected).
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_duration_bonus")
		reflect_percent += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "reflect_bonus")

	# Apply the buff
	buff_component.apply_buff("Iron Riposte", _owner_node, duration)
	
	# Customize the buff's logic parameters
	var active_buff = buff_component._active_buffs.get("Iron Riposte")
	if active_buff and active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.reflect_percentage = reflect_percent
		active_buff.custom_logic_instance.source_ability_level = _level_stats.level
	
	print("%s activated Iron Riposte (Level %d)!" % [_owner_node.name, _level_stats.level])
