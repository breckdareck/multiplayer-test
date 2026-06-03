extends EnemyState
## Boss telegraphed special-attack state — a forward dash-slam. The boss faces the
## target, rears into a windup animation while flashing red, and broadcasts a
## RECTANGULAR ground telegraph that extends FORWARD from its centre (near edge at
## the boss, far edge a full reach ahead — reads correctly on the 2D platformer
## plane, unlike a circle). After special_telegraph_time it lands one authoritative
## AoE over that box and DASHES to the far end, then hands back to chase. Entered
## from EnemyBase._boss_special_tick() (the readiness gate); all of the special's
## BEHAVIOR lives here rather than in EnemyBase._process.
##
## Injected at runtime by EnemyBase._ensure_boss_special_state() — only for
## enemies whose EnemyData.is_boss is true — so it carries no scene wiring and
## locates its sibling states by name. The node is created on every peer (so the
## state-name sync lookup resolves on clients); the windup/damage only advance on
## the server, but the cosmetic windup (anim + red flash) plays on every peer.

## Windup-pose animations, best-first. The boss plays the first one its
## SpriteFrames actually has; falls back to whatever's already playing.
const _WINDUP_ANIMS: Array[String] = ["dash_attack", "slash_attack", "bomb_attack", "attack"]
## Vertical thickness of the slam band as a fraction of the horizontal reach,
## clamped — short enough that an airborne (dodged/jumped) player clears it.
const _BAND_HEIGHT_FACTOR: float = 0.55
const _BAND_HEIGHT_MIN: float = 48.0
const _BAND_HEIGHT_MAX: float = 110.0
## Duration of the forward dash that resolves the slam (boss lunges across the box).
const _DASH_TIME: float = 0.18

## Seconds elapsed since the windup began (server-driven).
var _elapsed: float = 0.0
## True once this windup has dealt its damage + started the dash, so it fires once.
var _fired: bool = false
## Snapshot of the slam centre + full rect size, taken on enter so the AoE lands
## where the telegraph was shown even if the boss is nudged mid-windup.
var _center: Vector2 = Vector2.ZERO
var _rect: Vector2 = Vector2(240.0, 64.0)
var _windup: float = 1.0
## Facing (-1/+1) locked at windup start: the box extends this way and the boss
## dashes this way.
var _dir: int = 1
## Full horizontal length of the slam box = the dash distance.
var _reach: float = 240.0
## Dash phase (after the window): boss lunges to the far end of the box.
var _dashing: bool = false
var _dash_elapsed: float = 0.0
var _dash_target_x: float = 0.0
## The red charge-up tint tween, killed + reset on exit.
var _flash_tween: Tween = null


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

	var radius: float = enemy.enemy_data.special_attack_radius if enemy.enemy_data else 120.0
	_windup = maxf(0.05, enemy.enemy_data.special_telegraph_time if enemy.enemy_data else 1.0)
	_reach = radius * 2.0
	# Horizontal slam band: full length forward, short vertical band.
	var band_h: float = clampf(radius * _BAND_HEIGHT_FACTOR, _BAND_HEIGHT_MIN, _BAND_HEIGHT_MAX)
	_rect = Vector2(_reach, band_h)

	# Lock facing toward the threatened target (fallback: current facing).
	_dir = enemy.facing_direction
	if enemy.current_target != null and is_instance_valid(enemy.current_target):
		var dx: float = enemy.current_target.global_position.x - enemy.global_position.x
		if absf(dx) > 1.0:
			_dir = 1 if dx > 0.0 else -1
			enemy.face_direction(_dir)

	# The box extends FORWARD from the boss: its near edge sits at the boss's
	# centre, its far edge a full reach ahead. So the centre is offset half the
	# length in the facing direction. The boss later dashes to that far edge.
	_center = enemy.global_position + Vector2(_dir * _reach * 0.5, 0.0)

	# Cosmetic windup — runs on every visual peer (enter() fires via state sync).
	_play_windup_anim(enemy)
	_start_flash()

	# Show the rectangular telegraph (server only; the broadcast also guards, but
	# gate here so the client-side enter() is an explicit no-op for it).
	if multiplayer.is_server():
		enemy.broadcast_telegraph_rect(_center, _rect, _windup, Color(1.0, 0.2, 0.2, 0.5))


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return null
	# A killing blow mid-windup: let the death/cleanup flow take over.
	if enemy.health_component == null or enemy.health_component.is_dead:
		return null

	# Windup: hold, then on completion deal the slam and START the forward dash.
	if not _fired:
		_elapsed += delta
		if _elapsed >= _windup:
			_fired = true
			enemy.deal_boss_special_damage(_center, _rect)
			_dashing = true
			_dash_elapsed = 0.0
			_dash_target_x = enemy.global_position.x + _dir * _reach
		return null

	# Dash phase: lunge across the box, then recover.
	_dash_elapsed += delta
	if _dash_elapsed >= _DASH_TIME:
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	if parent == null:
		return null
	if _dashing:
		# Lunge to the far end of the box over _DASH_TIME (the slam follow-through).
		var reached: bool = (_dir > 0 and parent.global_position.x >= _dash_target_x) \
			or (_dir < 0 and parent.global_position.x <= _dash_target_x)
		if reached:
			parent.velocity.x = 0.0
		else:
			parent.velocity.x = _dir * (_reach / _DASH_TIME)
	else:
		# Commit: hold position through the windup (the telegraph is the player's
		# tell; the special can't be walked off by the boss itself).
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, 600.0 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	return null


func exit() -> void:
	super.exit()
	_stop_flash()
	# Re-arm the cooldown whether the special completed or was interrupted (e.g. by
	# death/stagger), so an interrupted windup can't instantly re-telegraph.
	var enemy := parent as EnemyBase
	if enemy:
		enemy.arm_boss_special_cooldown()


## Plays the first windup-pose animation the boss's SpriteFrames has. Routed
## through EnemyState._play_animation so it respects the host/client visual gate.
func _play_windup_anim(enemy: EnemyBase) -> void:
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy.enemy_data else null
	if sf == null:
		return
	for a in _WINDUP_ANIMS:
		if sf.has_animation(a):
			_play_animation(a)
			return


## Ramps the boss's tint toward red over the windup so it visibly "charges up",
## intensifying as the slam approaches. Cosmetic, every peer; reset in _stop_flash.
func _start_flash() -> void:
	if animations == null:
		return
	_stop_flash()
	animations.modulate = Color.WHITE
	_flash_tween = animations.create_tween()
	_flash_tween.tween_property(animations, "modulate", Color(1.0, 0.35, 0.3, 1.0), _windup)


func _stop_flash() -> void:
	if _flash_tween != null and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash_tween = null
	if animations != null:
		animations.modulate = Color.WHITE


## Where to go once the special resolves: resume the chase if the target is still
## valid, otherwise fall back to patrol/idle.
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
