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
var _hit_time: float = 1.0
# Dash phase.
var _dashing: bool = false
var _dash_elapsed: float = 0.0
var _dash_time: float = 0.18
var _dash_target_x: float = 0.0
var _dash_speed: float = 0.0
# Cosmetic.
var _flash_tween: Tween = null
# HOLD anim mode.
var _hold_target_frame: int = 0
# Bespoke logic.
var _logic: Object = null


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	_dashing = false
	_dash_elapsed = 0.0
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	_attack = enemy.get_pending_special_attack()
	if _attack == null:
		return

	_hit_time = maxf(0.05, _attack.hit_time)
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
		_spawn_logic()
		_call_logic("on_windup_start", [enemy, _attack])


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return null
	if enemy.health_component == null or enemy.health_component.is_dead:
		return null
	if _attack == null:
		return _recover_state()

	# Windup → hit.
	if not _fired:
		_elapsed += delta
		if _elapsed >= _hit_time:
			_fired = true
			_resolve_hit(enemy)
			if _attack.movement == BossAttackData.Movement.DASH:
				var dist: float = _attack.dash_distance if _attack.dash_distance > 0.0 else _attack.reach
				_dashing = true
				_dash_elapsed = 0.0
				_dash_speed = dist / _dash_time
				_dash_target_x = enemy.global_position.x + _dir * dist
			else:
				return _recover_state()
		return null

	# Dash phase.
	_dash_elapsed += delta
	if _dash_elapsed >= _dash_time:
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
	if animations != null:
		animations.speed_scale = 1.0  # undo a HOLD freeze if we left mid-windup
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
			if fc <= 1:
				animations.speed_scale = 1.0
			else:
				# Jump to the hold pose and FREEZE it for the whole windup; at the hit,
				# resume to play hold_frame -> end (the strike). Deterministic — no
				# frame_changed race, holds regardless of clip fps / windup length.
				animations.frame = _hold_target_frame
				animations.speed_scale = 0.0
				get_tree().create_timer(_hit_time).timeout.connect(_resume_from_hold)
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


func _resume_from_hold() -> void:
	# Out of the hold at the hit: resume native playback from the frozen hold frame,
	# so the remaining frames (the strike) play. Don't call play() — that would reset
	# to frame 0.
	if animations != null:
		animations.speed_scale = 1.0


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
