extends Node

## Bulwark Stance — applies the B_Bulwark_Stance buff to the caster.
## Following the codebase pattern (AL_PowerGuard / AL_Steady_Aim / AL_Vow_Of_The_Vanguard):
## `applies_buff` on the AbilityData is metadata for UI/bots/pets, but the
## actual buff application is the AL script's job in execute().
##
## v1 keeps it simple: apply the buff for the level-scaled duration. The
## buff's BL_BulwarkStance logic handles the per-second MP drain and the
## auto-cancel when MP hits 0. Re-casting before the buff expires refreshes
## duration (REFRESH stack_behavior on B_Bulwark_Stance).
##
## A true on/off toggle (cancel via re-cast) is held for a T3 variant.

## +Defense granted by the stance — fallback only. The live value comes from the
## .tres custom_value_formulas["defense"] (100 at L1 → 250 at max_level), the same
## formula the $[value:defense] description placeholder reads, so the tooltip and
## the applied buff can never drift.
const DEFENSE_AT_MIN: float = 100.0   # at level 1
const DEFENSE_AT_MAX: float = 250.0   # at max_level


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	var buff_component = _owner_node.get_node_or_null("Components/Buff")
	if not buff_component:
		return

	var duration: float = 30.0
	if _ability.buff_duration_formula:
		duration = _ability.buff_duration_formula.calculate(_level_stats.level)

	# PR 6: "buff_duration_bonus" upgrade adds flat seconds.
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "buff_duration_bonus")

	buff_component.apply_buff("Bulwark Stance", _owner_node, duration)

	# Scale the +Defense with the ability's level (the buff .tres carries only the
	# unscaled default). Read from the shared formula so it matches the tooltip.
	var defense: float = _ability.get_custom_value("defense", _level_stats.level, DEFENSE_AT_MAX)
	if buff_component.has_method("scale_buff_stat"):
		buff_component.scale_buff_stat("Bulwark Stance", Constants.StatType.DEFENSE, defense)

	# T3 variants — stamp the owned variant's parameters onto the buff's logic
	# instance (the Iron Riposte idiom: AL reads upgrades once at cast, BL acts
	# on plain fields). All three share the bs_variant mutex group, so at most
	# one is non-zero.
	var active_buff = buff_component._active_buffs.get("Bulwark Stance")
	if active_buff and active_buff.custom_logic_instance and ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		var bl = active_buff.custom_logic_instance
		bl.reflect_percentage = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "stance_reflect")
		bl.damage_reduction = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "stance_damage_reduction")
		bl.mp_drain_disabled = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "stance_no_drain") > 0.0
