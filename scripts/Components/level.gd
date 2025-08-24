class_name LevelingComponent
extends Node

signal leveled_up(new_level)
signal experience_changed(current_exp, exp_to_level)

@export var max_level = 100
@export var base_exp = 100
@export var exp_growth = 1.2

var level = 1:
	set(value):
		level = value
		leveled_up.emit(value)

var experience = 0:
	set(value):
		experience = value
		experience_changed.emit(value, get_exp_to_next_level())


func get_exp_to_next_level() -> int:
	return int(base_exp * pow(exp_growth, level - 1))


@rpc("any_peer", "call_local", "reliable")
func add_exp(amount: int) -> void:
	if not multiplayer.is_server():
		return
	if level >= max_level:
		return
	print("[DEBUG] Adding EXP to %s" % self.get_owner())
	experience += amount
	while experience >= get_exp_to_next_level() and level < max_level:
		experience -= get_exp_to_next_level()
		level += 1
