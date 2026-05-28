extends Node

## Ability logic for the Staff discipline's Aether Ward.
## Applies a buff that converts incoming damage into mana drain.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	# Absorption rate: 30% base + 2% per level (capped at 70% at max level 20
	# scaling, then upgrades can push it higher).
	var absorption_rate: float = (0.30 + level_stats.level * 0.02)

	# PR 6/8 upgrades:
	#  buff_duration_bonus (+s) — Lasting / Eternal Ward
	#  absorption_bonus (+fraction) — Reinforced Ward
	#  mana_flat_reduction / cooldown_flat_reduction are consumed generically in
	#  AbilityComponent._consume_ability_resources — no read here.
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_duration_bonus")
		absorption_rate += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "absorption_bonus")

	buff_component.apply_buff("Aether Ward", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Aether Ward")
	if not active_buff:
		return

	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.absorption_rate = absorption_rate
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	print("%s activated Aether Ward (Level %d) — %.0f%% absorption for %.0fs" % [
		owner_node.name, level_stats.level, absorption_rate * 100.0, duration])
