extends Node

var stats_percent: int = 1
var source_ability_level: int = 1 

func on_apply(_owner_node: Node, _active_buff) -> void:
	pass

func on_remove(_owner_node: Node, _active_buff) -> void:
	pass


func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	# Optional: Could add a visual effect that pulses each second
	pass
