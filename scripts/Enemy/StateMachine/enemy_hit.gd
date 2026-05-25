extends EnemyState
class_name EnemyHitState
## Brief stagger when the enemy takes damage. Plays the "hit" animation, freezes
## horizontal movement, then hands off to chase (if the enemy has a target) or
## idle.
##
## Runtime-injected by EnemyBase._ensure_hit_state(), so it carries no scene
## wiring and resolves siblings by name. Entered from EnemyBase.on_enemy_damaged
## only when the enemy's SpriteFrames actually contains a "hit" clip — slimes
## and other animation-less enemies never reach this state.

## Failsafe: if the hit animation never reports finished (missing clip, looping
## animation, missing AnimatedSprite2D on a dedicated server), bail out anyway.
const MAX_HIT_TIME: float = 0.6

var _animation_finished: bool = false
var _hit_time: float = 0.0


func enter() -> void:
	super.enter()
	# Stop the previous chase/patrol motion. CombatComponent.apply_knockback
	# runs *after* take_damage (and therefore after this enter() fires), so
	# any knockback impulse will overwrite this zero on the same frame.
	parent.velocity.x = 0
	_animation_finished = false
	_hit_time = 0.0
	if animations and not animations.animation_finished.is_connected(_on_hit_animation_finished):
		animations.animation_finished.connect(_on_hit_animation_finished)


func exit() -> void:
	if animations and animations.animation_finished.is_connected(_on_hit_animation_finished):
		animations.animation_finished.disconnect(_on_hit_animation_finished)


func _on_hit_animation_finished() -> void:
	_animation_finished = true


func process_frame(delta: float) -> State:
	_hit_time += delta
	if not (_animation_finished or _hit_time >= MAX_HIT_TIME):
		return null

	var enemy := parent as EnemyBase
	if enemy and enemy.is_valid_target(enemy.current_target):
		var chase := get_node_or_null("../chase")
		if chase:
			return chase
	return get_node_or_null("../idle")


func physics_update(delta: float) -> State:
	# Apply gravity and let any knockback velocity decay through friction —
	# zeroing velocity.x here would instantly cancel the impulse the player's
	# CombatComponent applies right after take_damage.
	parent.velocity.y += gravity * delta
	parent.velocity.x = move_toward(parent.velocity.x, 0.0, 400.0 * delta)
	parent.move_and_slide()
	return null
