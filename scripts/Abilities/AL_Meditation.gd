extends Node

func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	if not _owner_node.multiplayer.is_server():
		return

	var owner_id := int(str(_owner_node.name))
	var party_members := PartyManager.get_party_members(owner_id)

	if party_members.is_empty():
		party_members = [owner_id]

	var duration = _ability.buff_duration_formula.calculate(_level_stats.level)
	var caster_players_node := _owner_node.get_parent()

	for member_id in party_members:
		var member_node = PlayerManager.get_player_node(member_id)
		if not member_node or member_node.get_parent() != caster_players_node:
			continue

		var buff_component: BuffComponent = member_node.get_node_or_null("Components/Buff")
		if not buff_component:
			continue

		buff_component.apply_buff("Meditation", _owner_node, duration)

		var active_buff = buff_component._active_buffs.get("Meditation")
		if not active_buff:
			continue

		if active_buff.custom_logic_instance:
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
		buff_component.sync_buff_stat_modifiers.rpc("Meditation", modifier_data)

	print("%s activated Meditation (Level %d) - Duration: %ds [%d members]" %
		[_owner_node.name, _level_stats.level, duration, party_members.size()])
