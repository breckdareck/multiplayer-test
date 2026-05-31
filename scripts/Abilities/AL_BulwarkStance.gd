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
