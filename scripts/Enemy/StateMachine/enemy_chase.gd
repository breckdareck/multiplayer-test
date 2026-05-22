extends EnemyState
## Pursues the enemy's current_target along the ground. An enemy with a melee
## attack state stops in range and hands off to the slash-attack state; an
## enemy with no attack keeps charging so its body hitbox rams the target.
##
## The enemy never jumps or walks off ledges, so it stays on its own platform.
## When a wall or cliff edge blocks the way to the target, it paces back the
## other direction for a moment and then returns, instead of freezing against
## the obstacle. It also reacts with a short, randomized delay before turning
## to face a target that crossed to its other side.
##
## Injected at runtime by EnemyBase._ensure_chase_state(), so it carries no
## scene wiring and locates its sibling states by name.

const CHASE_SPEED_MULTIPLIER: float = 1.5
## Drop the target once it gets this many times the detection radius away.
const LOSE_TARGET_FACTOR: float = 1.6
## Give up if the chase carries the enemy this far from where it began.
const LEASH_RADIUS: float = 480.0
## Range of the randomized reaction delay before the enemy turns to face a
## target that moved to its other side.
const TURN_DELAY_MIN: float = 0.35
const TURN_DELAY_MAX: float = 0.6
## How long the enemy paces away from a blocking obstacle before heading back.
const BACKOFF_TIME_MIN: float = 0.6
const BACKOFF_TIME_MAX: float = 1.1

## The horizontal direction (-1 / +1) the enemy wants to head to reach the
## target.
var _move_dir: int = 1
## How long the target has been on the side opposite _move_dir.
var _turn_timer: float = 0.0
## Reaction delay for the current pending turn (re-rolled after each turn).
var _turn_delay: float = 0.45
## The target the committed heading was last computed against — used to snap
## instantly onto a brand-new target while lagging on a familiar one.
var _last_target: Node2D = null
## While > 0 the enemy is pacing away from an obstacle it can't get past.
var _backoff_timer: float = 0.0
## The direction (-1 / +1) of the current pace-away maneuver.
var _backoff_dir: int = 1


func enter() -> void:
	super.enter()
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	enemy.leash_anchor = enemy.global_position
	# _move_dir and _last_target persist on this node between state changes;
	# _update_move_dir() snaps onto a genuinely new target and lags when
	# re-orienting toward the same one. The reaction/backoff state resets here.
	_turn_timer = 0.0
	_turn_delay = randf_range(TURN_DELAY_MIN, TURN_DELAY_MAX)
	_backoff_timer = 0.0


func process_frame(_delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return _give_up()

	var target: Node2D = enemy.current_target
	if not enemy.is_valid_target(target):
		return _give_up()

	var dist := parent.global_position.distance_to(target.global_position)
	var detect: float = enemy.enemy_data.detection_radius if enemy.enemy_data else 160.0
	if dist > detect * LOSE_TARGET_FACTOR:
		return _give_up()
	if parent.global_position.distance_to(enemy.leash_anchor) > LEASH_RADIUS:
		return _give_up()

	# In range and armed: swing, but only once the enemy has actually turned
	# to face the target (so the reaction delay is respected) and the attack
	# is off cooldown.
	var atk_range: float = enemy.enemy_data.attack_range if enemy.enemy_data else 36.0
	if dist <= atk_range and enemy.has_attack_state() and enemy.can_attack():
		var dx := target.global_position.x - parent.global_position.x
		if signf(dx) == float(_move_dir) or absf(dx) < 8.0:
			var slash := get_node_or_null("../slash_attack")
			if slash:
				return slash
	return null


func physics_update(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		parent.velocity.y += gravity * delta
		parent.move_and_slide()
		return null

	var target: Node2D = enemy.current_target
	if not enemy.is_valid_target(target):
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, 250.0 * delta)
		parent.velocity.y += gravity * delta
		parent.move_and_slide()
		return null

	_update_move_dir(target, delta)

	var dist := parent.global_position.distance_to(target.global_position)
	var atk_range: float = enemy.enemy_data.attack_range if enemy.enemy_data else 36.0
	var speed: float = enemy.movement_speed * CHASE_SPEED_MULTIPLIER

	# Pick the direction to actually move this frame (0 = hold position).
	var step_dir := 0
	if dist <= atk_range and enemy.has_attack_state():
		# In melee range — hold still to wind up the attack.
		_backoff_timer = 0.0
		enemy.face_direction(_move_dir)
	elif _backoff_timer > 0.0:
		# Pacing away from an obstacle; cut it short if this way is blocked too.
		_backoff_timer -= delta
		if _is_blocked(_backoff_dir):
			_backoff_timer = 0.0
			enemy.face_direction(_move_dir)
		else:
			step_dir = _backoff_dir
			enemy.face_direction(_backoff_dir)
	elif _is_blocked(_move_dir):
		# Can't reach the target this way. Pace back the other direction —
		# unless that side is blocked too (wedged), in which case just hold.
		if _is_blocked(-_move_dir):
			enemy.face_direction(_move_dir)
		else:
			_backoff_dir = -_move_dir
			_backoff_timer = randf_range(BACKOFF_TIME_MIN, BACKOFF_TIME_MAX)
			step_dir = _backoff_dir
			enemy.face_direction(_backoff_dir)
	else:
		step_dir = _move_dir
		enemy.face_direction(_move_dir)

	if step_dir == 0:
		parent.velocity.x = move_toward(parent.velocity.x, 0.0, 400.0 * delta)
	else:
		parent.velocity.x = step_dir * speed

	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	return null


## Steers _move_dir toward the target. It snaps instantly when the target is
## new (a fresh aggro or a retarget), but when the same target moves to the
## enemy's other side it holds the old heading until the target has been
## across long enough — a MapleStory-style reaction delay.
func _update_move_dir(target: Node2D, delta: float) -> void:
	if target != _last_target:
		_last_target = target
		var d := _dir_to(target)
		if d != 0:
			_move_dir = d
		_turn_timer = 0.0
		return

	var desired := _dir_to(target)
	if desired == 0 or desired == _move_dir:
		_turn_timer = 0.0
		return

	_turn_timer += delta
	if _turn_timer >= _turn_delay:
		_move_dir = desired
		_turn_timer = 0.0
		_turn_delay = randf_range(TURN_DELAY_MIN, TURN_DELAY_MAX)


func _dir_to(target: Node2D) -> int:
	var dx := target.global_position.x - parent.global_position.x
	if absf(dx) < 1.0:
		return 0
	return 1 if dx > 0.0 else -1


## True when the enemy can't travel in direction `dir`: either there is a cliff
## edge just ahead, or it is pressed against a wall on that side.
func _is_blocked(dir: int) -> bool:
	if dir == 0:
		return false
	if _ledge_ahead(dir):
		return true
	if parent.is_on_wall():
		var wall_normal_x := parent.get_wall_normal().x
		# A wall is "ahead" when its surface normal opposes our travel.
		if not is_zero_approx(wall_normal_x) and signf(wall_normal_x) != float(dir):
			return true
	return false


## True when there is no ground within reach just ahead of the enemy — used to
## stop it at a cliff edge instead of walking off to chase a target below.
func _ledge_ahead(dir: int) -> bool:
	var forward := Vector2(dir * 12.0, 0.0)
	var forward_transform := parent.global_transform.translated(forward)
	return not parent.test_move(forward_transform, Vector2(0.0, 16.0))


func _give_up() -> State:
	var enemy := parent as EnemyBase
	if enemy:
		enemy.current_target = null
	var fallback := get_node_or_null("../patrol")
	if fallback == null:
		fallback = get_node_or_null("../idle")
	return fallback
