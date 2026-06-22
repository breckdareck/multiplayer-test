extends EnemyState
## Ranged projectile attack for a RANGED / MAGIC enemy (a caster / archer).
## Entered from chase once the target is in the attack zone (attack_range
## horizontally, ±1 tile vertically). Plays a cast pose, then fires a homing
## projectile at the target — the same projectile the player uses
## (scripts/Gameplay/projectile.gd), spawned server-side and mirrored to clients
## via EnemyBase.fire_projectile. No kiting: the caster stands still while casting
## (enemies have no pathfinding).
##
## Injected at runtime by EnemyBase._ensure_ranged_attack_state(), so it carries
## no scene wiring and resolves sibling states by name. The node exists on every
## peer (state-name sync); the cast pose plays on all, the projectile spawns on
## the server (which then broadcasts the client visuals).

## Cast-animation candidates, best first. MiniFolks casters slice the cast pose as
## "attack_2"; the spell-named clips cover other packs / future art.
const _CAST_ANIMS: Array[String] = ["spell", "cast", "attack_2", "attack_1", "attack"]
## Seconds into the cast that the projectile leaves (the wind-up read), and the
## tail held after it before recovering to chase.
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
	_play_cast(enemy)


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return _recover_state()
	if enemy.health_component == null or enemy.health_component.is_dead:
		return _recover_state()

	_elapsed += delta

	# Fire once, at the wind-up read. fire_projectile is server-guarded internally.
	if not _fired and _elapsed >= _FIRE_TIME:
		_fired = true
		if is_instance_valid(enemy.current_target):
			enemy.fire_projectile(enemy.current_target)

	if _fired and _elapsed >= _FIRE_TIME + _RECOVER_TAIL:
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	# Stand and cast — hold position (no kiting / repositioning AI).
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
		enemy.start_attack_cooldown()


# --- helpers ---------------------------------------------------------------

## Plays the cast clip, stretched to fill the wind-up so the pose reads with the
## shot. Prefers the first available cast clip in the SpriteFrames.
func _play_cast(enemy: EnemyBase) -> void:
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy.enemy_data else null
	var anim: String = _first_cast_anim(sf)
	if anim == "":
		return
	_play_animation(anim)
	if animations != null and sf != null:
		var frames: int = sf.get_frame_count(anim)
		var fps: float = sf.get_animation_speed(anim)
		if frames > 0 and fps > 0.0:
			var native: float = float(frames) / fps
			animations.speed_scale = clampf(native / (_FIRE_TIME + _RECOVER_TAIL), 0.05, 20.0)


func _first_cast_anim(sf: SpriteFrames) -> String:
	if sf == null:
		return ""
	for a in _CAST_ANIMS:
		if sf.has_animation(a):
			return a
	return ""


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
