extends Node

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return
	
	# Calculate reflect percentage based on ability level
	var reflect_percent = 12.0 + (level_stats.level - 1  * 2.0)  # 12% + 2% per level
	
	# Apply the buff
	buff_component.apply_buff("Power Guard", owner_node)
	
	# Customize the buff's logic parameters
	var active_buff = buff_component._active_buffs.get("Power Guard")
	if active_buff and active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.reflect_percentage = reflect_percent
		active_buff.custom_logic_instance.source_ability_level = level_stats.level
	
	print("%s activated Power Guard (Level %d)!" % [owner_node.name, level_stats.level])
