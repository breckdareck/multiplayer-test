extends Node

## Ability logic for the Dagger discipline's Killing Edge (formerly Vanish).
##
## PR 11 (2026-05-31): Vanish was redundant with the dagger's signature
## stealth (ShadowmeldComponent). Repurposed as a non-stealth burst-window
## self-buff: short duration (L1: 5s, L10: 15s) granting +CRITCHANCE and
## +CRITDAMAGE for a focused damage push. Materially different from the bow's
## Steady Aim — Steady Aim is sustained ATK + CRITCHANCE, this is short-burst
## CRITCHANCE + CRITDAMAGE.
##
## Upgrades (buff_attack_bonus / buff_critchance_bonus / buff_critdamage_bonus)
## layer on top of the base stats — same pattern as the other 3 buff abilities.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	# Base scaling (L1 -> L10):
	#   crit chance: 5 + L*2  -> L1: 7%, L10: 25%
	#   crit damage: 10 + L*3 -> L1: 13%, L10: 40%
	var crit_chance_bonus: float = 5.0 + level_stats.level * 2.0
	var crit_damage_bonus: float = 10.0 + level_stats.level * 3.0

	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_duration_bonus")

	buff_component.apply_buff("Killing Edge", owner_node, duration)

	var active_buff = buff_component._active_buffs.get("Killing Edge")
	if not active_buff:
		return
	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	# PR 10 upgrade extras: layer on top of base.
	var extra_atk: int = 0
	var extra_critchance: float = 0.0
	var extra_critdmg: float = 0.0
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		extra_atk = int(ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_attack_bonus"))
		extra_critchance = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critchance_bonus")
		extra_critdmg = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critdamage_bonus")

	active_buff.buff_data = active_buff.buff_data.duplicate()
	active_buff.buff_data.stat_modifiers.clear()

	var critchance_stat = StatData.new(Constants.StatType.CRITCHANCE, 0)
	critchance_stat.percent_bonus_value = crit_chance_bonus + extra_critchance
	active_buff.buff_data.stat_modifiers[Constants.StatType.CRITCHANCE] = critchance_stat

	var critdmg_stat = StatData.new(Constants.StatType.CRITDAMAGE, 0)
	critdmg_stat.percent_bonus_value = crit_damage_bonus + extra_critdmg
	active_buff.buff_data.stat_modifiers[Constants.StatType.CRITDAMAGE] = critdmg_stat

	if extra_atk > 0:
		var atk_stat = StatData.new(Constants.StatType.WEAPONATTACK, 0)
		atk_stat.flat_bonus_value = extra_atk
		active_buff.buff_data.stat_modifiers[Constants.StatType.WEAPONATTACK] = atk_stat

	buff_component._force_stat_recalc()

	print("%s activated Killing Edge (Level %d) — +%.1f%% crit / +%.1f%% critdmg for %.0fs" % [
		owner_node.name, level_stats.level,
		crit_chance_bonus + extra_critchance,
		crit_damage_bonus + extra_critdmg,
		duration])
