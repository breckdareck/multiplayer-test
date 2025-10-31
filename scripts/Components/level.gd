class_name LevelingComponent
extends Node

const LEVEL_UP_SFX = preload("uid://dnabcnb0g8ovx")

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
			rpc_id(0, "play_level_up_sfx_rpc")

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

@rpc("any_peer", "call_local", "reliable")
func play_level_up_sfx_rpc():
	var audio_player = AudioStreamPlayer.new()
	add_child(audio_player)
	audio_player.stream = LEVEL_UP_SFX
	audio_player.bus = "SFX"
	audio_player.play()
	await audio_player.finished
	audio_player.queue_free()
