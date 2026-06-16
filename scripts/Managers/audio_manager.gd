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

#region #################### Pitch jitter (anti-robotic-repetition) ####################
# A small randomized pitch_scale per play so constantly-repeated one-shots (swings,
# hits, footsteps, dings) stop sounding machine-gun identical. Rolled LOCALLY on each
# peer — pitch is cosmetic and is never networked (play_sfx_rpc broadcasts only the
# path; each client varies independently, which is correct and cheaper than syncing).
#
# Godot note: pitch_scale resamples, so it also changes the clip's DURATION — but the
# `finished` signal still fires at the resampled end, so the await/queue_free pattern
# below is unaffected. Floors are kept > 0.

## Default band (±5%) — freshens repeats without ever reading as a "wrong note".
## Applied to everything not listed in the two sets below.
const PITCH_DEFAULT := Vector2(0.95, 1.05)
## Heavy band — wider and biased DOWNWARD (weightier, never tinny/chipmunk on
## up-pitch) for the spammy percussive transients that fire constantly in a fight.
const PITCH_HEAVY := Vector2(0.88, 1.06)

## Sounds whose EXACT tuning carries meaning — a tuned achievement chime, a melodic
## fanfare, a dramatic minor sting. Retuning these run-to-run makes a milestone/death
## feel wrong, and they fire rarely so there's no repetition to fix. Never pitched.
## Matched on the bare filename so EventJuice- and play_sfx_for_map-routed plays of
## these (e.g. level_up.mp3 via level.gd, mastery_ding via event_juice.gd) are skipped.
const NO_PITCH_SFX := {
	"mastery_ding.wav": true,
	"quest_fanfare.wav": true,
	"death_sting.wav": true,
	"level_up.mp3": true,
}

## Spammy percussive one-shots (basic swings, hit/crit impacts, mob death poofs,
## footsteps/landings, fast dagger stabs, dashes) — pure noise/sweep transients with
## no tonal identity, so a clearly audible shift is safe and de-robotizes the spam.
const HEAVY_PITCH_SFX := {
	"attack_sword.wav": true, "attack_bow.wav": true, "attack_staff.wav": true,
	"attack_dagger.wav": true, "hit_impact.wav": true, "hit_crit.wav": true,
	"enemy_death.wav": true, "land_soft.wav": true, "dagger_stab.wav": true,
	"dash_whoosh.wav": true, "sword_slash.wav": true, "sword_heavy.wav": true,
	"jump.wav": true, "player_hit.wav": true,
}

## The pitch_scale to use for a given sfx path. Identity cues return 1.0 (no shift);
## heavy transients get the wide downward-biased band; everything else gets ±5%.
func random_pitch_for(sfx_path: String) -> float:
	var file := sfx_path.get_file()
	if NO_PITCH_SFX.has(file):
		return 1.0
	if HEAVY_PITCH_SFX.has(file):
		# hit_crit keeps a shallower floor so a low-rolled crit isn't mistaken for a
		# normal hit (players read crit by brightness).
		var lo: float = 0.94 if file == "hit_crit.wav" else PITCH_HEAVY.x
		return randf_range(lo, PITCH_HEAVY.y)
	return randf_range(PITCH_DEFAULT.x, PITCH_DEFAULT.y)

#endregion


# Plays an SFX locally.
func play_sfx(sfx_path: String, global_position: Vector2 = Vector2.ZERO, volume_db: float = 0.0):
	var sfx_stream: AudioStream = ResourceLoader.load(sfx_path)
	if not sfx_stream:
		push_warning("AudioManager: SFX not found at path: %s" % sfx_path)
		return

	var sfx_player = AudioStreamPlayer2D.new()
	sfx_player.stream = sfx_stream
	sfx_player.volume_db = volume_db
	sfx_player.bus = "SFX"
	sfx_player.pitch_scale = random_pitch_for(sfx_path)
	# Parent the emitter INTO the local visible map, not into AudioManager.
	# Maps each run in their own SubViewport / World2D and the player's Camera2D
	# (the only audio listener) lives there. An AudioStreamPlayer2D added to this
	# autoload sits in the root viewport instead — which has no camera, so its
	# listener falls back to world origin (0,0). With max_distance defaulting to
	# 2000px, that silences any SFX emitted far from origin (e.g. Deep Woods,
	# authored out at x ≈ -1900 to -3300). Hosting it in the current map puts it
	# in the same world as the player's camera, so distance is measured from the
	# listener and SFX are audible on every map regardless of authoring origin.
	var host: Node = MapManager.get_current_visible_map()
	if not is_instance_valid(host):
		host = self  # no map loaded yet (login/menu) — fall back to the autoload
	host.add_child(sfx_player)
	# global_position must be set AFTER reparenting — it resolves against the new
	# parent's transform (the map root, authored at its own origin).
	sfx_player.global_position = global_position
	sfx_player.play()
	await sfx_player.finished
	if is_instance_valid(sfx_player):
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
	# UI sounds are never in the HEAVY set, so this resolves to ±5% (or 1.0 for the
	# excluded identity cues like death_sting that route through play_ui_sfx).
	sfx_player.pitch_scale = random_pitch_for(sfx_path)
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
