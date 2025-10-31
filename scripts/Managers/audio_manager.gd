extends Node

var _music_player: AudioStreamPlayer = AudioStreamPlayer.new()

func _ready():
	add_child(_music_player)
	_music_player.bus = "Music"

func play_song(path: String):
	var song: AudioStream = ResourceLoader.load(path)
	_music_player.stream = song
	_music_player.play()

# Plays an SFX locally.
func play_sfx(sfx_path: String, global_position: Vector2 = Vector2.ZERO, volume_db: float = 0.0):
	var sfx_stream: AudioStream = ResourceLoader.load(sfx_path)
	if not sfx_stream:
		push_warning("AudioManager: SFX not found at path: %s" % sfx_path)
		return

	var sfx_player = AudioStreamPlayer2D.new()
	sfx_player.stream = sfx_stream
	sfx_player.global_position = global_position
	sfx_player.volume_db = volume_db
	sfx_player.bus = "SFX"
	add_child(sfx_player)
	sfx_player.play()
	await sfx_player.finished
	sfx_player.queue_free()

# RPC to play an SFX on all clients. Called by the server.
@rpc("any_peer", "call_local", "reliable")
func play_sfx_rpc(sfx_path: String, global_position: Vector2 = Vector2.ZERO, volume_db: float = 0.0):
	# This function will be executed on all peers (server and clients)
	# when called by the server using rpc_id(0, "play_sfx_rpc", ...)
	play_sfx(sfx_path, global_position, volume_db)
