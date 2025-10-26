extends Node

const BASE_DURATION = 30

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return
	
	var duration = BASE_DURATION * level_stats.level
	var stats_percent = ceil(level_stats.level / 2.0)
	
	# Apply the buff with custom duration parameter
	buff_component.apply_buff("Maple Warrior", owner_node, duration)
	
	# Get the active buff instance
	var active_buff = buff_component._active_buffs.get("Maple Warrior")
	if not active_buff:
		return
	
	# Customize the buff's logic parameters
	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.stats_percent = stats_percent
		active_buff.custom_logic_instance.source_ability_level = level_stats.level
	
	# Clear any existing stat modifiers and build new ones from scaling formulas
	active_buff.buff_data.stat_modifiers.clear()
	
	for bonus in ability.scaling_data.stat_bonus_formulas:
		# Create a new StatData with base_value = 0 (the buff adds bonuses, not base stats)
		var stat_data = StatData.new(bonus.stat_type, 0)
		
		# Apply flat bonus if formula exists
		if bonus.flat_bonus_formula:
			stat_data.flat_bonus_value = int(bonus.flat_bonus_formula.calculate(level_stats.level))
		
		# Apply percent bonus if formula exists
		if bonus.percent_bonus_formula:
			stat_data.percent_bonus_value = bonus.percent_bonus_formula.calculate(level_stats.level)
		
		# Add to buff's stat modifiers
		active_buff.buff_data.stat_modifiers[bonus.stat_type] = stat_data
	
	# Force stat recalculation to apply the new modifiers
	buff_component._force_stat_recalc()
	
	print("%s activated Maple Warrior (Level %d) - Duration: %ds, Stats: +%.0f%%" % 
		[owner_node.name, level_stats.level, duration, stats_percent])
