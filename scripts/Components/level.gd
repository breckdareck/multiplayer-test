class_name LevelingComponent
extends Node



signal leveled_up(new_level)
signal experience_changed(current_exp, exp_to_level)

@export var max_level = 100
@export var level_curve: Curve

var _is_loading_data: bool = false
var level:int = 1:
	set(value):
		var old_level = level
		level = value
		leveled_up.emit(value)
		# Only play SFX if level increased, it's the server, and not during data loading
		if level > old_level and multiplayer.is_server() and not _is_loading_data:
			rpc_id(0, "play_sfx_rpc", "res://assets/sounds/level_up.wav", get_owner().global_position)

var experience = 0:
	set(value):
		experience = value
		experience_changed.emit(value, get_exp_to_next_level())


func get_exp_to_next_level() -> int:
	return int(level_curve.sample(level-1))


@rpc("any_peer", "call_local", "reliable")
func add_exp(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if level >= max_level:
		return
		
	experience += amount
	while experience >= get_exp_to_next_level() and level < max_level:
		experience -= get_exp_to_next_level()
		level += 1


