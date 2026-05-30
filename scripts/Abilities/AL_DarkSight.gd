extends Node

## Ability logic for the Dagger discipline's Vanish.
## Applies an invisibility buff that prevents enemies from targeting the player.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)

	# PR 8 upgrade: buff_duration_bonus (+s). mana_flat_reduction is consumed
	# generically in AbilityComponent._consume_ability_resources — no read here.
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_duration_bonus")

	buff_component.apply_buff("Vanish", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Vanish")
	if active_buff and active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	print("%s activated Vanish (Level %d) — invisible for %.0fs" % [
		owner_node.name, level_stats.level, duration])
