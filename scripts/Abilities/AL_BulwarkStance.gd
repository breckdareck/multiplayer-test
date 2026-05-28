extends Node

## Bulwark Stance — applies the B_Bulwark_Stance buff to the caster.
## Following the codebase pattern (AL_PowerGuard / AL_Focus / AL_MapleWarrior):
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

	buff_component.apply_buff("Bulwark Stance", _owner_node, duration)
