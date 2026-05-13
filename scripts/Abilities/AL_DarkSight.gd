extends Node

## Ability logic for Rogue's Dark Sight.
## Applies an invisibility buff that prevents enemies from targeting the player.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)

	buff_component.apply_buff("Dark Sight", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Dark Sight")
	if active_buff and active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	print("%s activated Dark Sight (Level %d) — invisible for %.0fs" % [
		owner_node.name, level_stats.level, duration])
