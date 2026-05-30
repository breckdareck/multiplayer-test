extends Node

## Ability logic for the Staff discipline's Communion — a party-wide empower
## buff that raises MP regeneration and ATTACK POWER. Mirrors AL_Maple_Warrior's
## party-application pattern.
##
## PR-balance (2026-05-29): Communion now grants a FLAT buff to BOTH WEAPONATTACK
## and MAGICATTACK, so a physical party member benefits as much as a caster —
## this is what lets Staff be the universal SUPPORT off-hand (carry it alongside
## any weapon for the group damage rite). FLAT, not percent: WEAPONATTACK/
## MAGICATTACK have base 0 (gear-driven), so a percent bonus multiplies 0 = dead
## (the old MAGICATTACK-percent buff did nothing). The MP-regen line stays as-is.

## Flat attack power granted to BOTH attack stats, scaled by ability level.
const COMMUNION_ATK_BASE: float = 12.0
const COMMUNION_ATK_PER_LEVEL: float = 3.0

func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	if not _owner_node.multiplayer.is_server():
		return

	var owner_id := int(str(_owner_node.name))
	var party_members := PartyManager.get_party_members(owner_id)

	if party_members.is_empty():
		party_members = [owner_id]

	var duration = _ability.buff_duration_formula.calculate(_level_stats.level)

	# PR 6/8 upgrades:
	#  buff_duration_bonus (+s) — Extended / Enduring Rite
	#  communion_matk_bonus (+% magic attack) — Empowered Communion
	#  mana_flat_reduction / cooldown_flat_reduction consumed generically in
	#  AbilityComponent._consume_ability_resources — no read here.
	var matk_bonus: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_duration_bonus")
		matk_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "communion_matk_bonus")

	var caster_players_node := _owner_node.get_parent()

	for member_id in party_members:
		var member_node = PlayerManager.get_player_node(member_id)
		if not member_node or member_node.get_parent() != caster_players_node:
			continue

		var buff_component: BuffComponent = member_node.get_node_or_null("Components/Buff")
		if not buff_component:
			continue

		buff_component.apply_buff("Communion", _owner_node, duration)

		var active_buff = buff_component._active_buffs.get("Communion")
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
			# Empowered Communion stacks onto the magic-attack percent bonus.
			if bonus.stat_type == Constants.StatType.MAGICATTACK:
				stat_data.percent_bonus_value += matk_bonus
			active_buff.buff_data.stat_modifiers[bonus.stat_type] = stat_data
			modifier_data[bonus.stat_type] = {
				"flat": stat_data.flat_bonus_value,
				"percent": stat_data.percent_bonus_value
			}

		# Universal FLAT attack buff on BOTH stats (overwrites the dead MAGICATTACK
		# percent from the .tres). matk_bonus (Empowered Communion upgrade) folds in
		# as a flat add. This is the group damage rite that makes Staff a support
		# off-hand for any loadout.
		var atk_flat: int = int(COMMUNION_ATK_BASE + COMMUNION_ATK_PER_LEVEL * _level_stats.level + matk_bonus)
		for atk_stat in [Constants.StatType.WEAPONATTACK, Constants.StatType.MAGICATTACK]:
			var sd := StatData.new(atk_stat, 0)
			sd.flat_bonus_value = atk_flat
			active_buff.buff_data.stat_modifiers[atk_stat] = sd
			modifier_data[atk_stat] = {"flat": atk_flat, "percent": 0.0}

		buff_component._force_stat_recalc()
		if not buff_component.is_bot_owned():
			buff_component.sync_buff_stat_modifiers.rpc("Communion", modifier_data)

	print("%s activated Communion (Level %d) - Duration: %ds [%d members]" %
		[_owner_node.name, _level_stats.level, duration, party_members.size()])
