extends EnemyState
class_name EnemyAttackState

@export var return_state: EnemyState

## Damage axis for THIS attack. INHERIT = the enemy-wide enemy_data.is_magic_attacker
## (back-compat default). Set PHYSICAL for a melee swing / arrow (WEAPONATTACK vs the
## target's DEFENSE) or MAGIC for a spell / elemental breath (MAGICATTACK vs MAGICDEFENSE),
## so one enemy can carry both a weapon attack and a spell that scale off different stats.
enum DamageAxis { INHERIT, PHYSICAL, MAGIC }
@export var damage_axis: DamageAxis = DamageAxis.INHERIT


## Resolves this attack's damage axis to a concrete bool (INHERIT defers to the enemy's
## is_magic_attacker). Passed to enemy.damage_on_overlap so the hit scales/mitigates on
## the right stat pair.
func is_magic_damage(enemy: EnemyBase) -> bool:
	match damage_axis:
		DamageAxis.PHYSICAL:
			return false
		DamageAxis.MAGIC:
			return true
		_:
			return enemy != null and enemy.enemy_data != null and enemy.enemy_data.is_magic_attacker

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


## Enables/disables one attack hitbox `shape` and the shared AttackHitbox area's
## monitoring together. Used by every hitbox-delivery attack (melee slash, breath).
func arm_attack_hitbox(shape: CollisionShape2D, on: bool) -> void:
	if shape:
		shape.disabled = not on
	var enemy := parent as EnemyBase
	if enemy and enemy.attack_hitbox:
		enemy.attack_hitbox.monitoring = on


## Damages every valid body overlapping the AttackHitbox, once each — appends struck
## bodies to `hit_targets` so a single swing/breath can't multi-hit one target.
func damage_overlapping(enemy: EnemyBase, hit_targets: Array) -> void:
	var hitbox: Area2D = enemy.attack_hitbox if enemy else null
	if hitbox == null or not hitbox.monitoring:
		return
	var magic := is_magic_damage(enemy)
	for body in hitbox.get_overlapping_bodies():
		if body in hit_targets:
			continue
		if not enemy.is_valid_target(body):
			continue
		hit_targets.append(body)
		enemy.damage_on_overlap(body, magic)


## Half-extents (rx, ry) of a CollisionShape2D, measured from the enemy origin with the
## shape's local offset taken SYMMETRICALLY (abs) — so the reach box is centred on the
## enemy and the check is facing-agnostic (the hitbox is mirrored to facing on enter,
## but reach is polled before that). Rectangle / Circle / Capsule supported; ZERO for
## an unset/odd shape.
static func shape_reach_extents(cs: CollisionShape2D) -> Vector2:
	if cs == null or cs.shape == null:
		return Vector2.ZERO
	var s: Shape2D = cs.shape
	var half := Vector2.ZERO
	if s is RectangleShape2D:
		half = (s as RectangleShape2D).size * 0.5
	elif s is CircleShape2D:
		var r: float = (s as CircleShape2D).radius
		half = Vector2(r, r)
	elif s is CapsuleShape2D:
		var c := s as CapsuleShape2D
		half = Vector2(c.radius, c.height * 0.5)
	else:
		return Vector2.ZERO
	return Vector2(absf(cs.position.x) + half.x, absf(cs.position.y) + half.y)


## True when `target` is within this attack's reach shape — an editor-authored
## CollisionShape2D you can SEE, instead of a blind number. WYSIWYG: the box drawn in
## the editor IS the range chase commits the attack at. Facing-agnostic (abs offset).
static func target_in_reach_shape(enemy: EnemyBase, target: Node2D, cs: CollisionShape2D) -> bool:
	if enemy == null or not is_instance_valid(target):
		return false
	var ext := shape_reach_extents(cs)
	if ext == Vector2.ZERO:
		return false
	return absf(target.global_position.x - enemy.global_position.x) <= ext.x \
		and absf(target.global_position.y - enemy.global_position.y) <= ext.y


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
