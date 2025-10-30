class_name LevelingComponent
extends Node

const LEVEL_UP_SFX = preload("uid://dnabcnb0g8ovx")

signal leveled_up(new_level)
signal experience_changed(current_exp, exp_to_level)

@export var max_level = 100
@export var level_curve: Curve

var level:int = 1:
	set(value):
		if value > level:
			play_level_up_sfx()
		level = value
		leveled_up.emit(value)

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

func play_level_up_sfx():
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.stream = LEVEL_UP_SFX
	audio_player.bus = "SFX"
	audio_player.play()
	await audio_player.finished
	audio_player.queue_free()
