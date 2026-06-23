extends EnemyState
class_name EnemyAttackState

@export var return_state: EnemyState

## Failsafe: if the attack animation never reports finished (missing or looping
## animation), bail out anyway so the enemy can't get stuck mid-swing.
const MAX_ATTACK_TIME: float = 1.5

var attack_finished: bool = false
var _attack_time: float = 0.0

func enter() -> void:
	super.enter()
	# Most attacks will stop the enemy's movement.
	parent.velocity = Vector2.ZERO
	attack_finished = false
	_attack_time = 0.0
	if not animations.animation_finished.is_connected(_on_attack_animation_finished):
		animations.animation_finished.connect(_on_attack_animation_finished)

func _on_attack_animation_finished():
	attack_finished = true


func process_frame(delta: float) -> State:
	_attack_time += delta
	# Wait for the attack animation to finish (or the failsafe to trip).
	if not (attack_finished or _attack_time >= MAX_ATTACK_TIME):
		return null
	# Keep fighting if the target is still alive and in play; otherwise fall
	# back to the configured return state (idle/patrol).
	var enemy := parent as EnemyBase
	if enemy and enemy.is_valid_target(enemy.current_target):
		var chase := get_node_or_null("../chase")
		if chase:
			return chase
	return return_state


func physics_update(delta: float) -> State:
	# Apply gravity but prevent horizontal movement during the attack.
	parent.velocity.y += gravity * delta
	parent.velocity.x = 0
	parent.move_and_slide()
	return null


# --- Shared helpers reused by the timed-attack subclasses (and any attack state).
# These centralise the three things every attack state used to copy-paste.

## Return-to-play after an attack: chase if the target is still valid, else fall
## back to patrol/idle. (Resolves siblings by name so injected states work too.)
func attack_recover_state() -> State:
	var enemy := parent as EnemyBase
	if enemy != null and enemy.is_valid_target(enemy.current_target):
		var chase := get_node_or_null("../chase")
		if chase:
			return chase
	var fallback := get_node_or_null("../patrol")
	if fallback == null:
		fallback = get_node_or_null("../idle")
	return fallback


## "Plant" physics for an attack that holds position: damp horizontal velocity,
## apply gravity, slide. Enemies have no kiting/repositioning AI.
func plant_physics(delta: float) -> void:
	if parent == null:
		return
	parent.velocity.x = move_toward(parent.velocity.x, 0.0, 600.0 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()


## Plays `anim` time-stretched to fill `total` seconds, so a clip authored at any
## fps reads in sync with the attack's wind-up/active window.
func play_clip_stretched(anim: String, total: float) -> void:
	if anim == "" or animations == null:
		return
	var enemy := parent as EnemyBase
	var sf: SpriteFrames = enemy.enemy_data.sprite_frames if enemy and enemy.enemy_data else null
	if sf == null or not sf.has_animation(anim):
		return
	_play_animation(anim)
	var frames: int = sf.get_frame_count(anim)
	var fps: float = sf.get_animation_speed(anim)
	if frames > 0 and fps > 0.0 and total > 0.0:
		var native: float = float(frames) / fps
		animations.speed_scale = clampf(native / total, 0.05, 20.0)
