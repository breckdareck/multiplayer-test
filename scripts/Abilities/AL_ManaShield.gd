extends Node

## Ability logic for Mage's Mana Shield.
## Applies a buff that converts incoming damage into mana drain.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	# Absorption rate: 30% base + 2% per level (capped at 70% at max level 10)
	var absorption_rate: float = (0.30 + level_stats.level * 0.02)

	buff_component.apply_buff("Mana Shield", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Mana Shield")
	if not active_buff:
		return

	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.absorption_rate = absorption_rate
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	print("%s activated Mana Shield (Level %d) — %.0f%% absorption for %.0fs" % [
		owner_node.name, level_stats.level, absorption_rate * 100.0, duration])
