extends Node

## Combo-engaging augment locked in v1 design grilling 2026-05-31: Vow's
## stat-buff potency scales with combo count consumed at cast.
##   0 combo = COMBO_FLOOR × full potency (small baseline)
##   3 combo = 1.0 × full potency (the original/current full Vow)
## So Vow no longer ignores the combo gauge — it draws from it. Players
## who cast at 0 combo still get a usable buff; players who hold combo
## for Vow get the full payoff. The combo is CONSUMED on cast (same path
## Crescent Cleave / Sundering Blow take).
const COMBO_FLOOR: float = 0.50  ## potency at 0 combo (50% of the full value)
const MAX_COMBO: float = 3.0


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	if not _owner_node.multiplayer.is_server():
		return

	var owner_id := int(str(_owner_node.name))
	var party_members := PartyManager.get_party_members(owner_id)

	if party_members.is_empty():
		party_members = [owner_id]

	var duration = _ability.buff_duration_formula.calculate(_level_stats.level)
	# PR 15: read the display % from the .tres formula instead of hardcoded
	# ceil(level/2.0) (which was tuned for old max_level 20 and would have
	# halved the displayed number at the new max_level 10). The actual stat
	# modifiers below already read from the .tres formula in the loop, so
	# this just keeps the display + BL passthrough consistent.
	var stats_percent: float = 0.0
	if not _ability.scaling_data.stat_bonus_formulas.is_empty():
		var first_pct_formula = _ability.scaling_data.stat_bonus_formulas[0].percent_bonus_formula
		if first_pct_formula:
			stats_percent = first_pct_formula.calculate(_level_stats.level)

	# PR 6 upgrades: buff_duration_bonus (+s) and vow_stat_bonus (+% to the
	# all-stats buff). Read once; applied to duration + stats_percent below.
	var _ac = _owner_node.get("ability_component")
	if _ac and _ac.has_method("get_ability_upgrade_magnitude"):
		duration += _ac.get_ability_upgrade_magnitude(_ability.ability_id, "buff_duration_bonus")
		stats_percent += _ac.get_ability_upgrade_magnitude(_ability.ability_id, "vow_stat_bonus")

	# Combo-engaging augment: spend the current combo via SwordComboComponent's
	# spend_combo (returns the actual count consumed), then scale stats_percent
	# in the range [COMBO_FLOOR, 1.0] by combo / MAX_COMBO. Same spend path
	# Crescent Cleave / Sundering Blow / Earthsplitter take.
	var combo_consumed: int = 0
	var combo_comp = _owner_node.get("sword_combo_component")
	if combo_comp != null and is_instance_valid(combo_comp) and combo_comp.has_method("spend_combo"):
		combo_consumed = int(combo_comp.spend_combo())
	var combo_fraction: float = clampf(float(combo_consumed) / MAX_COMBO, 0.0, 1.0)
	var combo_mult: float = COMBO_FLOOR + (1.0 - COMBO_FLOOR) * combo_fraction
	stats_percent *= combo_mult
	duration *= combo_mult

	var caster_players_node := _owner_node.get_parent()

	for member_id in party_members:
		var member_node = PlayerManager.get_player_node(member_id)
		if not member_node or member_node.get_parent() != caster_players_node:
			continue

		var buff_component: BuffComponent = member_node.get_node_or_null("Components/Buff")
		if not buff_component:
			continue

		buff_component.apply_buff("Vow of the Vanguard", _owner_node, duration)

		var active_buff = buff_component._active_buffs.get("Vow of the Vanguard")
		if not active_buff:
			continue

		if active_buff.custom_logic_instance:
			active_buff.custom_logic_instance.stats_percent = stats_percent
			active_buff.custom_logic_instance.source_ability_level = _level_stats.level

		active_buff.buff_data = active_buff.buff_data.duplicate()
		active_buff.buff_data.stat_modifiers.clear()

		var modifier_data := {}
		for bonus in _ability.scaling_data.stat_bonus_formulas:
			var stat_data = StatData.new(bonus.stat_type, 0)
			if bonus.flat_bonus_formula:
				stat_data.flat_bonus_value = int(bonus.flat_bonus_formula.calculate(_level_stats.level))
			if bonus.percent_bonus_formula:
				stat_data.percent_bonus_value = bonus.percent_bonus_formula.calculate(_level_stats.level)
			active_buff.buff_data.stat_modifiers[bonus.stat_type] = stat_data
			modifier_data[bonus.stat_type] = {
				"flat": stat_data.flat_bonus_value,
				"percent": stat_data.percent_bonus_value
			}

		buff_component._force_stat_recalc()
		if not buff_component.is_bot_owned():
			buff_component.sync_buff_stat_modifiers.rpc("Vow of the Vanguard", modifier_data)

	#print("%s activated Vow of the Vanguard (Level %d) - Duration: %ds, Stats: +%.0f%% [%d members]" %
		#[_owner_node.name, _level_stats.level, duration, stats_percent, party_members.size()])
