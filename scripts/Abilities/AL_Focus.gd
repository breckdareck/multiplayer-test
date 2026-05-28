extends Node

## Ability logic for the Bow discipline's Steady Aim.
## Applies a buff that boosts WEAPONATTACK and CRITCHANCE scaled by ability level.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	var attack_bonus: int = 10 + level_stats.level * 2       # 12–50 over 20 levels
	var crit_bonus: float = 3.0 + level_stats.level * 0.5    # 3.5–13.0 over 20 levels

	# PR 8 upgrade: buff_duration_bonus (+s). mana_flat_reduction is consumed
	# generically in AbilityComponent._consume_ability_resources — no read here.
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_duration_bonus")

	buff_component.apply_buff("Steady Aim", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Steady Aim")
	if not active_buff:
		return

	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.attack_bonus = attack_bonus
		active_buff.custom_logic_instance.crit_bonus = crit_bonus
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	active_buff.buff_data.stat_modifiers.clear()

	var atk_stat = StatData.new(Constants.StatType.WEAPONATTACK, 0)
	atk_stat.flat_bonus_value = attack_bonus
	active_buff.buff_data.stat_modifiers[Constants.StatType.WEAPONATTACK] = atk_stat

	var crit_stat = StatData.new(Constants.StatType.CRITCHANCE, 0)
	crit_stat.percent_bonus_value = crit_bonus
	active_buff.buff_data.stat_modifiers[Constants.StatType.CRITCHANCE] = crit_stat

	buff_component._force_stat_recalc()
	print("%s activated Steady Aim (Level %d) — +%d ATK, +%.1f%% CRIT for %.0fs" % [owner_node.name, level_stats.level, attack_bonus, crit_bonus, duration])
