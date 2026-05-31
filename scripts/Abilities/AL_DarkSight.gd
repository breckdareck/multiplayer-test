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
	if not active_buff:
		return
	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	# PR 10 upgrades: Vanish has no base stat bonuses (pure stealth), but the
	# upgrade keys let it layer ATK / CRIT bonuses for "buff window" damage.
	# Applied identically to the other 3 buff abilities (Steady Aim, Eagle Eye,
	# Bloodlust) so the upgrade pattern is consistent.
	var extra_atk: int = 0
	var extra_critchance: float = 0.0
	var extra_critdmg: float = 0.0
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		extra_atk = int(ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_attack_bonus"))
		extra_critchance = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critchance_bonus")
		extra_critdmg = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critdamage_bonus")

	if extra_atk > 0 or extra_critchance > 0.0 or extra_critdmg > 0.0:
		active_buff.buff_data = active_buff.buff_data.duplicate()
		active_buff.buff_data.stat_modifiers.clear()
		if extra_atk > 0:
			var atk = StatData.new(Constants.StatType.WEAPONATTACK, 0)
			atk.flat_bonus_value = extra_atk
			active_buff.buff_data.stat_modifiers[Constants.StatType.WEAPONATTACK] = atk
		if extra_critchance > 0.0:
			var critchance = StatData.new(Constants.StatType.CRITCHANCE, 0)
			critchance.percent_bonus_value = extra_critchance
			active_buff.buff_data.stat_modifiers[Constants.StatType.CRITCHANCE] = critchance
		if extra_critdmg > 0.0:
			var critdmg = StatData.new(Constants.StatType.CRITDAMAGE, 0)
			critdmg.percent_bonus_value = extra_critdmg
			active_buff.buff_data.stat_modifiers[Constants.StatType.CRITDAMAGE] = critdmg
		buff_component._force_stat_recalc()

	print("%s activated Vanish (Level %d) — invisible for %.0fs" % [
		owner_node.name, level_stats.level, duration])
