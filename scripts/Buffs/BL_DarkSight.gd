extends Node

## Buff logic for Rogue's Dark Sight.
## Sets an is_invisible meta flag on the player so enemy AI can check it.

var source_ability_level: int = 1

func on_apply(owner_node: Node, _active_buff) -> void:
	owner_node.set_meta("is_invisible", true)
	print("Dark Sight (Level %d) activated — %s is now invisible!" % [
		source_ability_level, owner_node.name])

func on_remove(owner_node: Node, _active_buff) -> void:
	owner_node.set_meta("is_invisible", false)
	print("Dark Sight expired on %s" % owner_node.name)

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass
