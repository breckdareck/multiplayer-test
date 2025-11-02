extends Node

var is_input_locked := false

func set_input_locked(locked: bool):
	is_input_locked = locked

func is_locked() -> bool:
	return is_input_locked
