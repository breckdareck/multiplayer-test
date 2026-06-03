extends EnemyState
## Boss telegraphed special-attack state. The boss roots in place, rears into a
## windup animation while flashing red, broadcasts a growing RECTANGULAR ground
## telegraph to every peer (a horizontal slam band — reads correctly on the 2D
## platformer plane, unlike a circle), winds up for special_telegraph_time, then
## lands one authoritative AoE before handing back to chase. Entered from
## EnemyBase._boss_special_tick() (the readiness gate); all of the special's
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

## Seconds elapsed since the windup began (server-driven).
var _elapsed: float = 0.0
## True once this windup has dealt its damage, so a single entry fires once.
var _fired: bool = false
## Snapshot of the slam centre + full rect size, taken on enter so the AoE lands
## where the telegraph was shown even if the boss is nudged mid-windup.
var _center: Vector2 = Vector2.ZERO
var _rect: Vector2 = Vector2(240.0, 64.0)
var _windup: float = 1.0
## The red charge-up tint tween, killed + reset on exit.
var _flash_tween: Tween = null


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	var enemy := parent as EnemyBase
	if enemy == null:
		return

	var radius: float = enemy.enemy_data.special_attack_radius if enemy.enemy_data else 120.0
	_center = enemy.global_position
	_windup = maxf(0.05, enemy.enemy_data.special_telegraph_time if enemy.enemy_data else 1.0)
	# Horizontal slam band: full width = reach to each side, short vertical band.
	var band_h: float = clampf(radius * _BAND_HEIGHT_FACTOR, _BAND_HEIGHT_MIN, _BAND_HEIGHT_MAX)
	_rect = Vector2(radius * 2.0, band_h)

	# Face the threatened target so the windup reads as deliberate.
	if enemy.current_target != null and is_instance_valid(enemy.current_target):
		var dx: float = enemy.current_target.global_position.x - enemy.global_position.x
		if absf(dx) > 1.0:
			enemy.face_direction(1 if dx > 0.0 else -1)

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

	_elapsed += delta
	if not _fired and _elapsed >= _windup:
		_fired = true
		enemy.deal_boss_special_damage(_center, _rect)
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	# Commit: hold position through the windup (the telegraph is the player's tell;
	# the special can't be walked off by the boss itself).
	if parent == null:
		return null
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
