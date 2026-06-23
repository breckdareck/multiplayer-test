extends EnemyState
## Pursues the enemy's current_target along the ground. An enemy with an attack
## state stops in its attack zone and hands off to it (melee slash, or the ranged
## cast for a RANGED / MAGIC enemy — get_attack_state_node picks); an enemy with
## no attack keeps charging so its body hitbox rams the target.
##
## When an attacker is engaged but CAN'T hit — the target is on a ledge above or
## below it, outside the ±1-tile attack band — it doesn't freeze in place: it
## paces left and right in the area like a patrol enemy. It also plays the idle
## clip while holding still (winding up / waiting out cooldown) rather than
## running on the spot.
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
## How long (seconds) the enemy commits to a wander heading before re-rolling,
## when it's engaged but can't reach the target.
const WANDER_TIME_MIN: float = 0.8
const WANDER_TIME_MAX: float = 2.0
## Drop the target once it gets this many times the detection radius away. A small
## (>1) hysteresis margin past the detection range so chase doesn't flip-flop at the
## boundary, while still giving up shortly after the player leaves aggro range.
const LOSE_TARGET_FACTOR: float = 1.2
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
## Heading + countdown for the "engaged but can't reach" wander (see _wander_step).
var _wander_dir: int = 1
var _wander_timer: float = 0.0
## Rate-limits wander turns so a short platform can't flip the enemy every frame.
var _wander_flip_cd: float = 0.0
const WANDER_FLIP_COOLDOWN: float = 0.5

# --- Leaper (ribbon-pig) run + hop-over-obstacle ---------------------------
## Upward impulse when a leaper hops a wall/step in its path (px/s). At the
## default 980 gravity this clears ~1-2 tiles — enough to land on a step one up
## without stopping its run.
const HOP_FORCE: float = 260.0
## Minimum seconds between a leaper's "hop UP to the overhead player" leaps — so it
## can't spam-match the player. Climbing a wall/step in its path is NOT gated by
## this (that's free); only the no-wall up-hop is.
const LEAP_JUMP_COOLDOWN: float = 2.5
## Horizontal distance (px) under a higher target within which the leaper hops up
## to follow it onto a ledge (when there's no solid step to bump first).
const LEAP_UP_RANGE: float = 30.0
## Reaction delay before the leaper hops UP after a target rises overhead — gives
## the player a window to jump over / past it instead of being matched instantly.
const LEAP_UP_REACTION: float = 0.5
var _jump_cd: float = 0.0
## How long the target has been above-and-overhead (resets when it isn't).
var _up_react_timer: float = 0.0


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

	# Blocker: when the player is in threatening (attack) range and the guard is off
	# cooldown, raise the frontal guard instead of this attack cycle.
	if enemy.enemy_data != null and enemy.enemy_data.is_blocker and enemy.can_block() and enemy.target_in_attack_zone(target):
		var block_state := get_node_or_null("../block")
		if block_state:
			return block_state as State

	# Secondary attack: on its own cooldown, when the target is within reach. For a
	# breath that reach is the damage hitbox's own bounds (so it never fires out of
	# range); for a projectile it's secondary_attack_range / ±1 tile.
	if enemy.has_secondary_attack() and enemy.can_use_secondary():
		var reach := enemy.secondary_trigger_reach()
		var sdx := absf(target.global_position.x - parent.global_position.x)
		var sdy := absf(target.global_position.y - parent.global_position.y)
		if sdx <= reach.x and sdy <= reach.y:
			var sec := get_node_or_null("../secondary_attack")
			if sec:
				return sec as State

	# In the attack zone and armed: attack, but only once the enemy has actually
	# turned to face the target (so the reaction delay is respected) and the
	# attack is off cooldown. The zone is attack_range horizontally AND ±1 tile
	# vertically, so a ranged enemy won't fire at a target several platforms away.
	if enemy.has_attack_state() and enemy.can_attack() and enemy.target_in_attack_zone(target):
		var dx := target.global_position.x - parent.global_position.x
		if signf(dx) == float(_move_dir) or absf(dx) < 8.0:
			var atk := enemy.get_attack_state_node()
			if atk:
				return atk as State
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

	var chase_speed: float = enemy.movement_speed * CHASE_SPEED_MULTIPLIER

	var has_atk := enemy.has_attack_state()
	var in_zone := has_atk and enemy.target_in_attack_zone(target)
	var is_leaper: bool = enemy.enemy_data != null and enemy.enemy_data.is_leaper

	# Pick the direction (0 = hold) and speed to move this frame.
	var step_dir := 0
	var step_speed := chase_speed
	if in_zone:
		# In range and able to hit — hold still to wind up / wait out cooldown.
		_backoff_timer = 0.0
		enemy.face_direction(_move_dir)
	elif is_leaper:
		# Ribbon pig: keep running straight at the target, hopping any step/wall in
		# the way — never paces away, never stops short. (Runs after in_zone so a
		# leaper that DOES carry an attack still holds to swing.)
		step_dir = _leaper_charge(enemy, target, delta)
	elif has_atk and not enemy.target_vertically_reachable(target):
		# The target is on a ledge above/below, outside the ±1-tile band — the
		# enemy can't reach it (no pathfinding). Closing the horizontal gap is
		# pointless, so pace the area left and right like a patrol enemy instead
		# of either freezing or thrashing across the attack-range boundary.
		step_dir = _wander_step(enemy, delta)
		step_speed = enemy.movement_speed
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
		parent.velocity.x = step_dir * step_speed

	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	# Play the walk clip while moving, idle while holding — so an enemy waiting in
	# range (or out of cooldown) stops "running on the spot".
	_apply_locomotion_anim(step_dir != 0)
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


## Pace heading for an engaged-but-can't-reach enemy: walk a direction, reverse at
## walls/ledges, and re-roll occasionally — patrol-style milling. Direction changes
## are rate-limited (WANDER_FLIP_COOLDOWN) so a short platform can't flip the enemy
## every frame (the "spaz" bug); when its path is blocked but a flip is still on
## cooldown, or both sides are blocked, it holds (returns 0 → idle).
## Returns the step direction (-1 / +1), or 0 to hold.
func _wander_step(enemy: EnemyBase, delta: float) -> int:
	_wander_flip_cd = maxf(0.0, _wander_flip_cd - delta)
	_wander_timer -= delta

	if _is_blocked(_wander_dir):
		# Hit a wall/ledge. Only reverse if we haven't just flipped AND the other
		# way is actually open — otherwise hold instead of jittering.
		if _wander_flip_cd > 0.0 or _is_blocked(-_wander_dir):
			return 0
		_wander_dir = -_wander_dir
		_wander_flip_cd = WANDER_FLIP_COOLDOWN
		_wander_timer = randf_range(WANDER_TIME_MIN, WANDER_TIME_MAX)
	elif _wander_timer <= 0.0:
		# Open path — occasionally re-roll heading for natural milling (but never
		# turn into a blocked side).
		var roll := 1 if randf() < 0.5 else -1
		if not _is_blocked(roll):
			_wander_dir = roll
		_wander_timer = randf_range(WANDER_TIME_MIN, WANDER_TIME_MAX)

	enemy.face_direction(_wander_dir)
	return _wander_dir


## Leaper charge: run flat-out toward the target and hop a wall/step that's in the
## way (so it climbs one tile up and keeps coming), never pacing or stopping short.
## Returns the step direction (-1 / +1), or 0 only to avoid running off a cliff
## that doesn't lead to the target. The actual hop is an upward impulse here; the
## horizontal run velocity is applied by the caller from the returned direction.
func _leaper_charge(enemy: EnemyBase, target: Node2D, delta: float) -> int:
	_jump_cd = maxf(0.0, _jump_cd - delta)
	enemy.face_direction(_move_dir)

	# Mid-hop: keep the horizontal run so it carries up and over / onto the ledge.
	if not parent.is_on_floor():
		return _move_dir

	# Climbing a wall/step blocking the charge is FREE — no cooldown, so the leaper
	# can always get up a platform in its path. The is_on_floor gate above means
	# this fires once per landing (not every frame), so a wall it can't clear just
	# produces a repeated hop rather than a vibration.
	if parent.is_on_wall():
		parent.velocity.y = -HOP_FORCE
		return _move_dir

	# Track how long the target has been overhead, so the up-hop can wait out a
	# reaction delay (resets the moment it isn't, so a quick jump-over doesn't count).
	var to_x: float = target.global_position.x - parent.global_position.x
	var dy: float = target.global_position.y - parent.global_position.y  # < 0 = above
	var target_overhead: bool = dy < -12.0 and absf(to_x) <= LEAP_UP_RANGE
	if target_overhead:
		_up_react_timer += delta
	else:
		_up_react_timer = 0.0

	# Hopping UP to a player who's overhead with no wall to climb (a floating ledge)
	# IS rate-limited + reaction-delayed, so the leaper can't spam-match the player.
	if _up_react_timer >= LEAP_UP_REACTION and _jump_cd <= 0.0:
		parent.velocity.y = -HOP_FORCE
		_jump_cd = LEAP_JUMP_COOLDOWN
		return _move_dir

	# A cliff ahead that doesn't drop toward the target — don't run off it; hold the
	# edge (still facing the target) rather than dive into a pit.
	if _ledge_ahead(_move_dir) and not _target_below(target):
		return 0

	return _move_dir


## True when the target is clearly below this enemy (so dropping off a ledge toward
## it is following the player down, not diving into a pit).
func _target_below(target: Node2D) -> bool:
	return target.global_position.y - parent.global_position.y > EnemyBase.ATTACK_VERTICAL_REACH


## Switches between the walk ("patrol") and "idle" clips so a stationary enemy
## isn't stuck running on the spot. Only re-plays on an actual change.
func _apply_locomotion_anim(moving: bool) -> void:
	if animations == null or animations.sprite_frames == null:
		return
	# Moving uses this chase node's authored animation_name (default "patrol"); when
	# paused-in-place (aggroed but can't reach) it drops to "idle".
	var move_anim := animation_name if animation_name != "" else "patrol"
	var desired := move_anim if moving else "idle"
	if animations.animation != desired and animations.sprite_frames.has_animation(desired):
		animations.play(desired)


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
