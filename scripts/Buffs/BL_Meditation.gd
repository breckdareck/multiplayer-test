extends Node

var source_ability_level: int = 1

func on_apply(_owner_node: Node, _active_buff) -> void:
	print("Communion (Level %d) activated on %s!" % [source_ability_level, _owner_node.name])

func on_remove(_owner_node: Node, _active_buff) -> void:
	print("Communion expired on %s" % _owner_node.name)

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass
