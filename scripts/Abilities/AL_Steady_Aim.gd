extends Node

## Ability logic for the Bow discipline's Steady Aim.
## Applies a buff that boosts WEAPONATTACK and CRITCHANCE scaled by ability level.

func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData):
	var buff_component: BuffComponent = owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = ability.buff_duration_formula.calculate(level_stats.level)
	# PR 9 (2026-05-31): rescaled for max_level 10 (was 20). Endpoints preserved
	# at L10: +50 ATK, +13% crit (same as old L20). Slightly stronger early.
	var attack_bonus: int = 10 + level_stats.level * 4       # 14–50 over 10 levels
	var crit_bonus: float = 3.0 + level_stats.level * 1.0    # 4–13% over 10 levels

	# PR 8 upgrade: buff_duration_bonus (+s). mana_flat_reduction is consumed
	# generically in AbilityComponent._consume_ability_resources — no read here.
	# PR 10 upgrades: buff_attack_bonus, buff_critchance_bonus, buff_critdamage_bonus
	# fold into the buff's stat_modifiers below (BuffStatBonuses helper).
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_duration_bonus")

	buff_component.apply_buff("Steady Aim", owner_node, duration)

	# Bow signature synergy: Steady Aim FREEZES Momentum decay for its duration, so
	# you can reposition / line up shots without bleeding your ramp. No-op for a
	# non-bow caster (the component only exists on the player root; guarded).
	var momentum = owner_node.get("bow_momentum_component")
	if momentum != null and is_instance_valid(momentum) and momentum.has_method("pause_decay"):
		momentum.pause_decay(duration)

	var active_buff = buff_component._active_buffs.get("Steady Aim")
	if not active_buff:
		return

	if active_buff.custom_logic_instance:
		active_buff.custom_logic_instance.attack_bonus = attack_bonus
		active_buff.custom_logic_instance.crit_bonus = crit_bonus
		active_buff.custom_logic_instance.source_ability_level = level_stats.level

	active_buff.buff_data.stat_modifiers.clear()

	# Base buff stats + upgrade-driven extras folded into the same modifier map.
	var extra_atk: int = 0
	var extra_critchance: float = 0.0
	var extra_critdmg: float = 0.0
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		extra_atk = int(ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_attack_bonus"))
		extra_critchance = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critchance_bonus")
		extra_critdmg = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "buff_critdamage_bonus")

	var atk_stat = StatData.new(Constants.StatType.WEAPONATTACK, 0)
	atk_stat.flat_bonus_value = attack_bonus + extra_atk
	active_buff.buff_data.stat_modifiers[Constants.StatType.WEAPONATTACK] = atk_stat

	# CRITCHANCE/CRITDAMAGE units are already percentages — additive via
	# flat_bonus_value, not percent_bonus_value (which multiplies base 5 / 0).
	var crit_stat = StatData.new(Constants.StatType.CRITCHANCE, 0)
	crit_stat.flat_bonus_value = int(crit_bonus + extra_critchance)
	active_buff.buff_data.stat_modifiers[Constants.StatType.CRITCHANCE] = crit_stat

	if extra_critdmg > 0.0:
		var critdmg_stat = StatData.new(Constants.StatType.CRITDAMAGE, 0)
		critdmg_stat.flat_bonus_value = int(extra_critdmg)
		active_buff.buff_data.stat_modifiers[Constants.StatType.CRITDAMAGE] = critdmg_stat

	buff_component._force_stat_recalc()
	print("%s activated Steady Aim (Level %d) — +%d ATK, +%.1f%% CRIT for %.0fs" % [owner_node.name, level_stats.level, attack_bonus + extra_atk, crit_bonus + extra_critchance, duration])
