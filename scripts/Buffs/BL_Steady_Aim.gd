extends Node

## Buff logic for the Bow discipline's Steady Aim ability.
## Stat modifiers (WEAPONATTACK, CRITCHANCE) are set dynamically by AL_Steady_Aim.gd.

var attack_bonus: int = 15
var crit_bonus: float = 5.0
var source_ability_level: int = 1

func on_apply(_owner_node: Node, _active_buff) -> void:
	pass

func on_remove(_owner_node: Node, _active_buff) -> void:
	pass

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass
