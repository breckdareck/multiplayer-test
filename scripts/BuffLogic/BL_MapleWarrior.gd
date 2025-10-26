extends Node

var stats_percent: int = 1
var source_ability_level: int = 1 

func on_apply(owner_node: Node, active_buff) -> void:
	print("Maple Warrior (Level %d) activated on %s! Stats increased by %.0f%%" % 
		[source_ability_level, owner_node.name, stats_percent])
		

func on_remove(owner_node: Node, active_buff) -> void:
	print("Maple Warrior expired on %s" % owner_node.name)


func on_tick(owner_node: Node, active_buff, delta: float) -> void:
	# Optional: Could add a visual effect that pulses each second
	pass
