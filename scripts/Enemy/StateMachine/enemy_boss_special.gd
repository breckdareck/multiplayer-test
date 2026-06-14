extends EnemyState
## Generic boss special-attack EXECUTOR. It runs whatever BossAttackData the
## readiness gate (EnemyBase._boss_special_tick) picked — telegraph, windup,
## animation timing, the hit, optional dash, optional bespoke logic_script. Every
## boss attack (the Warlord's dash-slam, a future dragon's fire breath) is just a
## different BossAttackData; this state does not change per attack.
##
## Injected at runtime by EnemyBase._ensure_boss_special_state() — only for bosses
## — so it carries no scene wiring. The node exists on every peer (state-name sync);
## the windup/damage/dash advance on the server, the cosmetic anim + tint on all.

const _WINDUP_ANIMS: Array[String] = ["dash_attack", "slash_attack", "bomb_attack", "attack"]

var _attack: BossAttackData = null
var _elapsed: float = 0.0
var _fired: bool = false
var _center: Vector2 = Vector2.ZERO
var _dir: int = 1
var _hit_time: float = 1.0     # impact: damage + dash happen here
var _windup_time: float = 1.0  # HOLD freezes the pose until here, then the strike plays
# Dash phase. The dash + strike begin at windup_time (when the hold releases);
# damage lands later at hit_time.
var _dashing: bool = false
var _dash_started: bool = false
var _dash_elapsed: float = 0.0
var _dash_time: float = 0.18
var _dash_target_x: float = 0.0
var _dash_speed: float = 0.0
# Cosmetic.
var _flash_tween: Tween = null
# HOLD anim mode — driven deterministically per visual frame in _process (so the
# release lands on the exact frame the clock crosses windup_time, with no
# SceneTreeTimer jitter). Set up by _play_windup.
var _hold_drive: bool = false          # true while _process should drive HOLD frames
var _anim_elapsed: float = 0.0         # per-peer seconds since the windup started
var _hold_target_frame: int = 0        # the wind-up pose; frozen until windup_time
var _strike_last_frame: int = 0        # last clip frame (strike end)
var _hold_fps: float = 0.0
var _hold_frame_count: int = 0
# Bespoke logic.
var _logic: Object = null


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	_dashing = false
	_dash_started = false
	_dash_elapsed = 0.0
	_hold_drive = false
	_anim_elapsed = 0.0
	set_process(true)  # drives the HOLD animation frame-accurately on every peer
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	_attack = enemy.get_pending_special_attack()
	if _attack == null:
		# Remote clients: the server-only _pending_special_attack is null, so resolve
		# the windup from the attack index the server synced just before this state.
		_attack = enemy.get_client_special_attack()
	if _attack == null:
		return

	_hit_time = maxf(0.05, _attack.hit_time)
	# Hold/anticipation ends here; the strike animation then plays over the
	# remaining [windup_time, hit_time] gap before impact. Clamp <= hit_time.
	_windup_time = clampf(_attack.windup_time, 0.05, _hit_time)
	_dash_time = maxf(0.05, _attack.dash_time)

	# Lock facing toward the target (fallback: current facing).
	_dir = enemy.facing_direction
	if enemy.current_target != null and is_instance_valid(enemy.current_target):
		var dx: float = enemy.current_target.global_position.x - enemy.global_position.x
		if absf(dx) > 1.0:
			_dir = 1 if dx > 0.0 else -1
			enemy.face_direction(_dir)

	# Zone centre by shape: CIRCLE on the boss; RECT/CONE offset forward.
	if _attack.shape == BossAttackData.Shape.CIRCLE:
		_center = enemy.global_position
	else:
		_center = enemy.global_position + Vector2(_dir * _attack.reach * _attack.forward_offset_frac, 0.0)

	# Cosmetic windup — runs on every visual peer.
	_play_windup(enemy)
	_start_flash()

	# Authoritative telegraph + bespoke windup hook — server only.
	if multiplayer.is_server():
		enemy.broadcast_attack_telegraph(_attack, _center, _dir, _hit_time, Color(1.0, 0.2, 0.2, 0.5))
		# Juice: a heavy windup cue to go with the red telegraph — the dangerous tell.
		var wmap: String = enemy._get_map_id()
		if wmap != "":
			AudioManager.play_sfx_for_map(wmap, "res://assets/sounds/generated/sword_heavy.wav", enemy.global_position, 1.0)
		_spawn_logic()
		_call_logic("on_windup_start", [enemy, _attack])


## Per-peer, per-visual-frame HOLD animation driver — frame-accurate, no resume
## timer. 0 -> hold_frame during the wind-up, frozen on hold_frame until
## windup_time, then hold_frame+1 -> last stretched to land on hit_time.
func _process(delta: float) -> void:
	if not _hold_drive or animations == null:
		return
	_anim_elapsed += delta
	var f: int
	if _anim_elapsed < _windup_time:
		f = clampi(int(floor(_anim_elapsed * _hold_fps)), 0, _hold_target_frame)
	else:
		var nxt: int = mini(_hold_target_frame + 1, _strike_last_frame)
		var gap: float = _hit_time - _windup_time
		if gap <= 0.001:
			f = _strike_last_frame
		else:
			var sfrac: float = clampf((_anim_elapsed - _windup_time) / gap, 0.0, 1.0)
			f = clampi(nxt + int(floor(sfrac * float(_strike_last_frame - nxt))), nxt, _strike_last_frame)
	animations.frame = f
	animations.speed_scale = 0.0  # frame is set manually; no auto-advance


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return null
	if enemy.health_component == null or enemy.health_component.is_dead:
		return null
	if _attack == null:
		return _recover_state()

	_elapsed += delta

	# At windup_time the hold releases: the strike animation resumes (via the
	# per-peer resume timer) AND the dash begins — the boss lunges in.
	if not _dash_started and _attack.movement == BossAttackData.Movement.DASH and _elapsed >= _windup_time:
		_dash_started = true
		_dashing = true
		_dash_elapsed = 0.0
		var dist: float = _attack.dash_distance if _attack.dash_distance > 0.0 else _attack.reach
		_dash_speed = dist / _dash_time
		_dash_target_x = enemy.global_position.x + _dir * dist

	# Damage lands at hit_time (after the dash has carried the boss in).
	if not _fired and _elapsed >= _hit_time:
		_fired = true
		_resolve_hit(enemy)

	# Track the dash duration.
	if _dashing:
		_dash_elapsed += delta
		if _dash_elapsed >= _dash_time:
			_dashing = false

	# Recover once the hit has fired AND any dash has finished.
	var dash_done: bool = (_attack.movement != BossAttackData.Movement.DASH) or (_dash_started and not _dashing)
	if _fired and dash_done:
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	if parent == null:
		return null
	if _dashing:
		var reached: bool = (_dir > 0 and parent.global_position.x >= _dash_target_x) \
			or (_dir < 0 and parent.global_position.x <= _dash_target_x)
		parent.velocity.x = 0.0 if reached else _dir * _dash_speed
	else:
		# Commit: hold position through the windup.
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, 600.0 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	return null


func exit() -> void:
	super.exit()
	_stop_flash()
	_hold_drive = false
	set_process(false)
	if animations != null:
		animations.speed_scale = 1.0  # restore normal playback for the next state
	var enemy := parent as EnemyBase
	if enemy:
		_call_logic("on_recover", [enemy, _attack])
		enemy.arm_boss_special_cooldown()
	_free_logic()


## Apply the hit. A logic_script may take over (return true from on_hit) to do its
## own damage (fire spread, multi-hit); otherwise the built-in shape damage runs.
func _resolve_hit(enemy: EnemyBase) -> void:
	var handled = _call_logic("on_hit", [enemy, _attack, _center, _dir])
	if handled == true:
		return
	enemy.deal_boss_special_damage(_attack, _center, _dir)


# --- Animation --------------------------------------------------------------

func _play_windup(enemy: EnemyBase) -> void:
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy.enemy_data else null
	var anim: String = _attack.windup_anim
	if anim == "" or (sf != null and not sf.has_animation(anim)):
		anim = _first_available_anim(sf)
	if anim == "":
		return
	_play_animation(anim)
	if animations == null:
		return
	match _attack.anim_mode:
		BossAttackData.AnimMode.STRETCH:
			animations.speed_scale = _stretch_scale(sf, anim, _hit_time)
		BossAttackData.AnimMode.HOLD:
			var fc: int = sf.get_frame_count(anim) if sf != null else 0
			_hold_target_frame = _attack.hold_frame
			# A hold frame must leave STRIKE frames after it. Unset (-1) or at/past the
			# last frame defaults to a MID frame so there's always a strike to play.
			if _hold_target_frame < 0 or _hold_target_frame >= fc - 1:
				_hold_target_frame = clampi(int(fc / 2), 0, maxi(0, fc - 2))
			_strike_last_frame = maxi(0, fc - 1)
			_hold_fps = sf.get_animation_speed(anim) if sf != null else 0.0
			_hold_frame_count = fc
			if fc <= 1 or _hold_fps <= 0.0:
				animations.speed_scale = 1.0  # nothing to drive; just play
			else:
				# _process drives the frame each visual peer-frame: 0->hold during the
				# wind-up, hold until windup_time, then hold+1->last stretched to land on
				# hit_time. Frame-accurate; no resume-timer jitter.
				_hold_drive = true
				animations.frame = 0
				animations.speed_scale = 0.0
		BossAttackData.AnimMode.FREE:
			animations.speed_scale = 1.0


func _first_available_anim(sf: SpriteFrames) -> String:
	if sf == null:
		return ""
	for a in _WINDUP_ANIMS:
		if sf.has_animation(a):
			return a
	return ""


## speed_scale that makes `anim` finish in `target` seconds.
func _stretch_scale(sf: SpriteFrames, anim: String, target: float) -> float:
	if sf == null or target <= 0.0:
		return 1.0
	var frames: int = sf.get_frame_count(anim)
	var fps: float = sf.get_animation_speed(anim)
	if frames <= 0 or fps <= 0.0:
		return 1.0
	var native: float = float(frames) / fps
	return clampf(native / target, 0.05, 20.0)


# --- Red charge-up tint -----------------------------------------------------

func _start_flash() -> void:
	if animations == null:
		return
	_stop_flash()
	animations.modulate = Color.WHITE
	_flash_tween = animations.create_tween()
	_flash_tween.tween_property(animations, "modulate", Color(1.0, 0.35, 0.3, 1.0), _hit_time)


func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if animations != null:
		animations.modulate = Color.WHITE


# --- Bespoke logic_script (server only) -------------------------------------

func _spawn_logic() -> void:
	_logic = null
	if _attack != null and _attack.logic_script != null:
		_logic = _attack.logic_script.new()


func _call_logic(method: String, args: Array):
	if _logic != null and _logic.has_method(method):
		return _logic.callv(method, args)
	return null


func _free_logic() -> void:
	if is_instance_valid(_logic) and _logic is Node:
		(_logic as Node).free()
	_logic = null


# --- Recovery ---------------------------------------------------------------

func _recover_state() -> State:
	var enemy := parent as EnemyBase
	if enemy != null and enemy.is_valid_target(enemy.current_target):
		var chase := get_node_or_null("../chase")
		if chase:
			return chase
	var fallback := get_node_or_null("../patrol")
	if fallback == null:
		fallback = get_node_or_null("../idle")
	return fallback
