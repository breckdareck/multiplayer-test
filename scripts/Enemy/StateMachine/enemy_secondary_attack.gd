extends EnemyState
## Secondary attack for an enemy that carries a second projectile/spell on top of
## its primary (EnemyData.secondary_*). Entered from chase on the secondary
## cooldown when the target is within secondary_attack_range. Plays the configured
## secondary clip (secondary_attack_anim, e.g. "attack_2"/"spell") and fires the
## secondary projectile, then returns to chase. Mirrors enemy_ranged_attack but on
## the secondary scene/anim/cooldown.
##
## Injected at runtime by EnemyBase._ensure_secondary_attack_state(); server-only.

const _FIRE_TIME: float = 0.45
const _RECOVER_TAIL: float = 0.25

var _elapsed: float = 0.0
var _fired: bool = false


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	if is_instance_valid(enemy.current_target):
		enemy.face_toward(enemy.current_target.global_position)
	_play_secondary(enemy)
	# Breath flavour: show the mouth plume NOW so the fire is out for the whole attack
	# (a cast, not an impact); hidden again in exit(). Projectile fires at _FIRE_TIME.
	if enemy.secondary_is_breath():
		enemy.play_secondary_breath_vfx()


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return _recover_state()
	if enemy.health_component == null or enemy.health_component.is_dead:
		return _recover_state()

	_elapsed += delta
	if not _fired and _elapsed >= _FIRE_TIME:
		_fired = true
		if is_instance_valid(enemy.current_target):
			if enemy.secondary_is_breath():
				enemy.apply_secondary_breath_damage()
			else:
				enemy.fire_secondary_projectile(enemy.current_target)

	if _fired and _elapsed >= _FIRE_TIME + _RECOVER_TAIL:
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	if parent != null:
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, 600.0 * delta)
		parent.velocity.y += gravity * delta
		parent.move_and_slide()
	return null


func exit() -> void:
	super.exit()
	allow_flip = true
	if animations != null:
		animations.speed_scale = 1.0
	var enemy := parent as EnemyBase
	if enemy:
		if enemy.secondary_is_breath():
			enemy.stop_secondary_breath_vfx()
		enemy.start_secondary_cooldown()


# --- helpers ---------------------------------------------------------------

func _play_secondary(enemy: EnemyBase) -> void:
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy.enemy_data else null
	var anim: String = enemy.enemy_data.secondary_attack_anim if enemy.enemy_data else ""
	if sf == null or anim == "" or not sf.has_animation(anim):
		return
	_play_animation(anim)
	if animations != null:
		var frames: int = sf.get_frame_count(anim)
		var fps: float = sf.get_animation_speed(anim)
		if frames > 0 and fps > 0.0:
			var native: float = float(frames) / fps
			animations.speed_scale = clampf(native / (_FIRE_TIME + _RECOVER_TAIL), 0.05, 20.0)


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
