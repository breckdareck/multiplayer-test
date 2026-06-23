extends EnemyAttackState
## Melee attack: a frame-windowed swing. The AttackHitbox area is live only during
## the contact frames of the attack animation and is mirrored to the enemy's facing,
## so the hit lands when the swing visually connects — the same hitbox-driven model
## the player's CombatComponent uses (and the breath's EnemyHitboxAttack reuses the
## shared arm/damage helpers). Authored as the "melee_attack" state node per enemy.

@export var melee_hitbox_shape: CollisionShape2D

## Animation-frame window (inclusive) during which the hitbox deals damage — author
## per enemy to match its attack clip timing (default tuned for an 8-frame swing:
## 0-3 wind-up, 4-7 the swing-through where the weapon connects).
@export var HIT_FRAME_START: int = 4
@export var HIT_FRAME_END: int = 7
## Seconds between swings. 0 = inherit enemy_data.attack_cooldown.
@export var cooldown: float = 0.0

var _hitbox_active: bool = false
## Bodies already struck this swing — each target is hit at most once.
var _hit_targets: Array[Node] = []
## This attack's own cooldown clock (msec); chase won't enter it until now >= this.
var _ready_at: int = 0


## Poll predicate for chase: off this swing's cooldown AND the target is inside the
## swing reach. Facing is gated by chase.
func can_start(enemy: EnemyBase, target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	if Time.get_ticks_msec() < _ready_at:
		return false
	return in_reach(enemy, target)


## Reach = the swing hitbox you author and SEE in the editor (WYSIWYG) — the enemy
## swings when the target enters its visible swing zone. Chase also polls this
## (cooldown aside) to decide when to stop closing and hold. Unset shape = fall back
## to the enemy-wide attack_range box.
func in_reach(enemy: EnemyBase, target: Node2D) -> bool:
	if melee_hitbox_shape != null and melee_hitbox_shape.shape != null:
		return target_in_reach_shape(enemy, target, melee_hitbox_shape)
	return enemy.target_in_attack_zone(target)


func enter() -> void:
	super.enter() # plays the slash animation, zeroes velocity, resets the timer
	_hit_targets.clear()

	var enemy := parent as EnemyBase
	if enemy:
		# Face the target, then mirror the hitbox shape to that side (the same
		# trick CombatComponent.turn_on_hitbox uses for the player).
		if is_instance_valid(enemy.current_target):
			enemy.face_toward(enemy.current_target.global_position)
		if melee_hitbox_shape:
			melee_hitbox_shape.position.x = absf(melee_hitbox_shape.position.x) * enemy.facing_direction

	# Start the swing with the hitbox off — it only arms on the contact frames.
	_set_hitbox_enabled(false)


func physics_update(delta: float) -> State:
	_update_hitbox()
	return super.physics_update(delta)


func exit() -> void:
	_set_hitbox_enabled(false)
	var enemy := parent as EnemyBase
	if enemy:
		# Arm this swing's own cooldown (boss enrage/phase applied by enemy_base).
		var cd: float = cooldown if cooldown > 0.0 else (enemy.enemy_data.attack_cooldown if enemy.enemy_data else 1.4)
		_ready_at = enemy.attack_cooldown_until(cd)
	super.exit()


## Arms the hitbox during the contact frames of the swing and damages every
## valid target caught inside it (once each).
func _update_hitbox() -> void:
	var enemy := parent as EnemyBase
	if enemy == null:
		return

	var frame := _current_attack_frame(enemy)
	var should_be_active := frame >= HIT_FRAME_START and frame <= HIT_FRAME_END
	if should_be_active != _hitbox_active:
		_set_hitbox_enabled(should_be_active)

	if not _hitbox_active:
		return
	# Shared hitbox-delivery helper (also used by the breath hitbox attack).
	damage_overlapping(enemy, _hit_targets)


func _set_hitbox_enabled(on: bool) -> void:
	_hitbox_active = on
	arm_attack_hitbox(melee_hitbox_shape, on)


func _current_attack_frame(enemy: EnemyBase) -> int:
	if enemy.animated_sprite and is_instance_valid(enemy.animated_sprite):
		return enemy.animated_sprite.frame
	# No sprite to read (headless edge case) — treat the swing as in-window so
	# the hit still lands.
	return HIT_FRAME_START
