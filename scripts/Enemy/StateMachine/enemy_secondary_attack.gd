extends EnemyState
## Secondary attack on top of an enemy's primary (EnemyData.secondary_*). Entered
## from chase on the secondary cooldown when the target is within
## secondary_attack_range. Plays the secondary clip (secondary_attack_anim, e.g.
## "attack_2"/"spell"), then returns to chase. Two flavours:
##   - PROJECTILE (secondary_projectile_scene): fires a homing bolt at fire_time.
##   - BREATH (secondary_breath_sprite): shows the mouth plume for the whole attack
##     and arms a collision hitbox (secondary_hitbox_shape) during the active window,
##     damaging overlapping players once each via damage_on_overlap — the SAME
##     hitbox-driven model as the melee slash, so the breath's reach/shape is the
##     editor-authored CollisionShape2D, not distance math.
##
## Author this as a child of StateMachine in the enemy scene (named
## "secondary_attack") to tune its timing in the inspector; enemies that DON'T author
## it get one injected with these defaults by EnemyBase._ensure_secondary_attack_state().

@export_group("Projectile timing")
## Seconds into the attack the projectile fires (its cast point).
@export var fire_time: float = 0.45
## Recovery seconds after the projectile fires before returning to chase.
@export var recover_tail: float = 0.25

@export_group("Breath timing")
## Wind-up seconds before the fire hitbox goes live (the mouth opens / fire ignites).
## Short = the fire bites almost as soon as it's visible. Total breath = windup + active.
@export var breath_windup: float = 0.12
## Seconds the fire hitbox stays live and damaging (while the plume pours).
@export var breath_active: float = 0.55

var _elapsed: float = 0.0
var _fired: bool = false
var _hitbox_on: bool = false
## Bodies already struck this breath — each target is hit at most once.
var _hit_targets: Array[Node] = []


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	_hit_targets.clear()
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	if is_instance_valid(enemy.current_target):
		enemy.face_toward(enemy.current_target.global_position)
	_play_secondary(enemy)
	# Breath flavour: show the mouth plume for the whole attack (a cast, not an
	# impact; hidden again in exit), and arm the breath hitbox mirrored to facing.
	if enemy.secondary_is_breath():
		enemy.play_secondary_breath_vfx()
		var shape := _breath_shape(enemy)
		if shape:
			shape.position.x = absf(shape.position.x) * enemy.facing_direction
		_set_breath_hitbox(enemy, false)


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return _recover_state()
	if enemy.health_component == null or enemy.health_component.is_dead:
		return _recover_state()

	_elapsed += delta
	if enemy.secondary_is_breath():
		_update_breath_hitbox(enemy)
	elif not _fired and _elapsed >= fire_time:
		_fired = true
		if is_instance_valid(enemy.current_target):
			enemy.fire_secondary_projectile(enemy.current_target)

	if _elapsed >= _total_duration(enemy):
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
			_set_breath_hitbox(enemy, false)
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
			animations.speed_scale = clampf(native / _total_duration(enemy), 0.05, 20.0)


## Total length of the secondary, by flavour — breath uses its snappier window.
func _total_duration(enemy: EnemyBase) -> float:
	if enemy.secondary_is_breath():
		return breath_windup + breath_active
	return fire_time + recover_tail


## The breath's damage CollisionShape2D (EnemyData.secondary_hitbox_shape), or null.
func _breath_shape(enemy: EnemyBase) -> CollisionShape2D:
	if enemy.enemy_data == null or enemy.enemy_data.secondary_hitbox_shape.is_empty():
		return null
	return enemy.get_node_or_null(enemy.enemy_data.secondary_hitbox_shape) as CollisionShape2D


## Arms the breath hitbox during the active window and damages every valid target
## caught inside it (once each) — the slash's model, applied to the breath shape.
func _update_breath_hitbox(enemy: EnemyBase) -> void:
	var active: bool = _elapsed >= breath_windup and _elapsed < breath_windup + breath_active
	if active != _hitbox_on:
		_set_breath_hitbox(enemy, active)
	if not _hitbox_on:
		return
	var hitbox: Area2D = enemy.attack_hitbox
	if hitbox == null or not hitbox.monitoring:
		return
	for body in hitbox.get_overlapping_bodies():
		if body in _hit_targets:
			continue
		if not enemy.is_valid_target(body):
			continue
		_hit_targets.append(body)
		enemy.damage_on_overlap(body)


func _set_breath_hitbox(enemy: EnemyBase, on: bool) -> void:
	_hitbox_on = on
	var shape := _breath_shape(enemy)
	if shape:
		shape.disabled = not on
	if enemy.attack_hitbox:
		enemy.attack_hitbox.monitoring = on


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
