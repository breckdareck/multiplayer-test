extends Node

## Buff logic for Archer's Focus ability.
## Stat modifiers (WEAPONATTACK, CRITCHANCE) are set dynamically by AL_Focus.gd.

var attack_bonus: int = 15
var crit_bonus: float = 5.0
var source_ability_level: int = 1

func on_apply(owner_node: Node, _active_buff) -> void:
	print("Focus (Level %d) activated on %s! +%d ATK, +%.1f%% CRIT" % [source_ability_level, owner_node.name, attack_bonus, crit_bonus])

func on_remove(owner_node: Node, _active_buff) -> void:
	print("Focus expired on %s" % owner_node.name)

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass
