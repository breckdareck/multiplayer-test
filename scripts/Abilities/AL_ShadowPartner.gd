extends Node

## Ability logic for Rogue's Shadow Partner.
## Applies a timed buff that spawns a shadow copy behind the player.
## The shadow mimics the player's attacks at reduced damage.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	var damage_percent: float = ability.scaling_data.damage_percent_formula.calculate(level_stats.level)

	buff_component.apply_buff("Shadow Partner", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Shadow Partner")
	if active_buff and active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.source_ability_level = level_stats.level
		active_buff.custom_logic_instance.damage_percent = damage_percent

	print("%s summoned Shadow Partner (Level %d) — %.0f%% damage for %.0fs" % [
		owner_node.name, level_stats.level, damage_percent, duration])
