extends Node

var _music_player: AudioStreamPlayer = AudioStreamPlayer.new()
var _current_song_path: String = ""

func _ready():
	add_child(_music_player)
	_music_player.bus = "Music"

func play_song(path: String):
	if path.is_empty():
		return
	# Skip if already playing this track
	if path == _current_song_path and _music_player.playing:
		return
	_current_song_path = path
	var song: AudioStream = ResourceLoader.load(path)
	_music_player.stream = song
	_music_player.play()

func stop_song():
	_music_player.stop()
	_current_song_path = ""

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

# Plays a NON-positional SFX locally (UI clicks, death sting, etc.).
# play_sfx uses an AudioStreamPlayer2D, which attenuates with distance from the
# camera — at (0,0) it's inaudible anywhere in a real map. UI sounds must not
# be positional, so they get a plain AudioStreamPlayer.
func play_ui_sfx(sfx_path: String, volume_db: float = 0.0):
	var sfx_stream: AudioStream = ResourceLoader.load(sfx_path)
	if not sfx_stream:
		push_warning("AudioManager: UI SFX not found at path: %s" % sfx_path)
		return
	var sfx_player := AudioStreamPlayer.new()
	sfx_player.stream = sfx_stream
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

# Server-only: plays an SFX for every real player on a given map, so positional
# SFX (jumps, hits) aren't heard by players on other maps.
func play_sfx_for_map(map_id: String, sfx_path: String, global_position: Vector2 = Vector2.ZERO, volume_db: float = 0.0):
	if not multiplayer.is_server():
		return
	MapManager.broadcast_to_map(map_id, func(peer_id): play_sfx_rpc.rpc_id(peer_id, sfx_path, global_position, volume_db))

# Server-only: plays a NON-positional UI sfx on a single peer's client (denial
# buzzers, quest-objective ticks, …). Owner-only feedback — unlike play_sfx_for_map
# it never reaches bystanders. Skips bot peers (no client) and the invalid/0 peer.
func play_ui_sfx_for_peer(peer_id: int, sfx_path: String, volume_db: float = 0.0):
	if not multiplayer.is_server():
		return
	if peer_id <= 0 or BotManager.is_bot(peer_id):
		return
	play_ui_sfx_rpc.rpc_id(peer_id, sfx_path, volume_db)

# Server -> one client. Plays the UI sfx locally on the target. call_local so a
# host-owner (peer 1) hears it too. Mirrors play_sfx_rpc's annotation.
@rpc("any_peer", "call_local", "reliable")
func play_ui_sfx_rpc(sfx_path: String, volume_db: float = 0.0):
	play_ui_sfx(sfx_path, volume_db)
