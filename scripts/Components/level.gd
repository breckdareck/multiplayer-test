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
			AudioManager.play_sfx_for_map(MapManager.get_player_map(get_owner().player_id), "res://assets/sounds/level_up.mp3", get_owner().global_position)
			# NEW: Notify PartyManager of the level change
			PartyManager.notify_player_data_changed(get_owner().player_id)
			# A nearby bot may congratulate a PLAYER's ding (the flash/sound is
			# visible map-wide). Bot dings route through BotBrain._on_leveled_up
			# instead, gated on their own level_up line being heard.
			if not BotManager.is_bot(get_owner().player_id):
				BotManager.queue_grats(get_owner().player_id, value, false)

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
	if not BotManager.is_bot(owner.player_id):
		show_exp_gain_log_rpc.rpc_id(owner.player_id, amount)
	
	while experience >= get_exp_to_next_level() and level < max_level:
		experience -= get_exp_to_next_level()
		level += 1


@rpc("any_peer", "call_local", "reliable")
func show_exp_gain_log_rpc(amount: int):
	var text = "+%d EXP" % amount
	LogManager.add_scrolling_log(text, Color.GOLD)
