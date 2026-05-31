extends Node

func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	if not _owner_node.multiplayer.is_server():
		return

	var owner_id := int(str(_owner_node.name))
	var party_members := PartyManager.get_party_members(owner_id)

	if party_members.is_empty():
		party_members = [owner_id]

	var duration = _ability.buff_duration_formula.calculate(_level_stats.level)

	# PR 8 upgrade: buff_duration_bonus (+s). mana_flat_reduction is consumed
	# generically in AbilityComponent._consume_ability_resources — no read here.
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_duration_bonus")

	var caster_players_node := _owner_node.get_parent()

	for member_id in party_members:
		var member_node = PlayerManager.get_player_node(member_id)
		if not member_node or member_node.get_parent() != caster_players_node:
			continue

		var buff_component: BuffComponent = member_node.get_node_or_null("Components/Buff")
		if not buff_component:
			continue

		buff_component.apply_buff("Bloodlust", _owner_node, duration)

		var active_buff = buff_component._active_buffs.get("Bloodlust")
		if not active_buff:
			continue

		if active_buff.custom_logic_instance:
			active_buff.custom_logic_instance.source_ability_level = _level_stats.level

		active_buff.buff_data = active_buff.buff_data.duplicate()
		active_buff.buff_data.stat_modifiers.clear()

		# PR 10 upgrade extras (caster's upgrades only — applied to every party member).
		var extra_atk: int = 0
		var extra_critchance: float = 0.0
		var extra_critdmg: float = 0.0
		if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
			extra_atk = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_attack_bonus"))
			extra_critchance = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_critchance_bonus")
			extra_critdmg = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_critdamage_bonus")

		var modifier_data := {}
		for bonus in _ability.scaling_data.stat_bonus_formulas:
			var stat_data = StatData.new(bonus.stat_type, 0)
			if bonus.flat_bonus_formula:
				stat_data.flat_bonus_value = int(bonus.flat_bonus_formula.calculate(_level_stats.level))
			if bonus.percent_bonus_formula:
				stat_data.percent_bonus_value = bonus.percent_bonus_formula.calculate(_level_stats.level)
			match bonus.stat_type:
				Constants.StatType.WEAPONATTACK:
					stat_data.flat_bonus_value += extra_atk
				Constants.StatType.CRITCHANCE:
					stat_data.percent_bonus_value += extra_critchance
				Constants.StatType.CRITDAMAGE:
					stat_data.percent_bonus_value += extra_critdmg
			active_buff.buff_data.stat_modifiers[bonus.stat_type] = stat_data
			modifier_data[bonus.stat_type] = {
				"flat": stat_data.flat_bonus_value,
				"percent": stat_data.percent_bonus_value
			}
		_layer_upgrade_only_stat(active_buff, modifier_data, Constants.StatType.WEAPONATTACK, extra_atk, 0.0)
		_layer_upgrade_only_stat(active_buff, modifier_data, Constants.StatType.CRITCHANCE, 0, extra_critchance)
		_layer_upgrade_only_stat(active_buff, modifier_data, Constants.StatType.CRITDAMAGE, 0, extra_critdmg)

		buff_component._force_stat_recalc()
		if not buff_component.is_bot_owned():
			buff_component.sync_buff_stat_modifiers.rpc("Bloodlust", modifier_data)

	print("%s activated Bloodlust (Level %d) - Duration: %ds [%d members]" %
		[_owner_node.name, _level_stats.level, duration, party_members.size()])


## Helper: if an upgrade-only stat (one not in base scaling_data) has a non-zero
## extra magnitude, write it to stat_modifiers / modifier_data so it survives
## the sync RPC.
func _layer_upgrade_only_stat(active_buff, modifier_data: Dictionary, stat_type: int, extra_flat: int, extra_pct: float) -> void:
	if extra_flat == 0 and extra_pct == 0.0:
		return
	if active_buff.buff_data.stat_modifiers.has(stat_type):
		return
	var stat_data = StatData.new(stat_type, 0)
	stat_data.flat_bonus_value = extra_flat
	stat_data.percent_bonus_value = extra_pct
	active_buff.buff_data.stat_modifiers[stat_type] = stat_data
	modifier_data[stat_type] = { "flat": extra_flat, "percent": extra_pct }
