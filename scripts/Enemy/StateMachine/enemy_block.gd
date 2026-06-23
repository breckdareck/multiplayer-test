extends EnemyAttackState
## Frontal guard for a blocker enemy (ADR-0018). Entered from chase, on the block
## cooldown, when the target is in attack range. While guarding, EnemyBase reports
## `_guarding` true, so frontal hits are heavily reduced and the flinch is
## suppressed. Counterplay: wait it out, strike the moment it drops, or hit it from
## behind (a flank ignores the guard).
##
## Animation: the `block` clip is driven by hand rather than just played through —
## it raises to the guard pose (frames 0..GUARD_FRAME), HOLDS there for the whole
## guard, and only plays the impact frames (REACT_START..REACT_END) when a frontal
## hit actually lands, then snaps back to the hold. Normal locomotion resumes once
## the guard ends. (Server-driven via process_frame, so the host sees it; remote
## clients see the clip play once from enter — an accepted limitation.)
##
## Authored as a scene node under the enemy's StateMachine (presence = the enemy is a
## blocker); chase polls its `can_start`. Server-driven.

## How long the guard stays up.
const BLOCK_DURATION: float = 3.0
## Block-clip frame layout (8-frame clip): 0..GUARD_FRAME = raise, hold on
## GUARD_FRAME, REACT_START..REACT_END = the on-hit impact.
const GUARD_FRAME: int = 2
const REACT_START: int = 3
const REACT_END: int = 6
## Frames/sec for the raise + impact (matches the clip's authored speed).
const ANIM_FPS: float = 10.0

enum Phase { RAISE, HOLD, REACT }

var _elapsed: float = 0.0
var _phase: int = Phase.RAISE
## Time accumulator within the current RAISE / REACT sweep.
var _anim_t: float = 0.0


## Poll predicate for chase: raise the guard when off the block cooldown and the
## target is in the attack box. Authored BEFORE melee_attack in the StateMachine so
## a guard preempts a swing (child order = poll priority).
func can_start(enemy: EnemyBase, target: Node2D) -> bool:
	return is_instance_valid(target) and enemy.can_block() and enemy.target_in_attack_zone(target)


func enter() -> void:
	super.enter()  # selects the "block" clip
	allow_flip = false
	_elapsed = 0.0
	_phase = Phase.RAISE
	_anim_t = 0.0
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	if is_instance_valid(enemy.current_target):
		enemy.face_toward(enemy.current_target.global_position)
	enemy.set_guarding(true)
	enemy.consume_block_react()  # drop any stale request
	# Take manual control of the clip — we set frames ourselves below.
	if animations != null:
		animations.speed_scale = 0.0
		animations.frame = 0


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return attack_recover_state()
	if enemy.health_component == null or enemy.health_component.is_dead:
		return attack_recover_state()

	_elapsed += delta

	# A frontal hit during the guard kicks off the impact frames (unless one is
	# already playing — leave it pending so it replays right after).
	if _phase != Phase.REACT and enemy.consume_block_react():
		_phase = Phase.REACT
		_anim_t = 0.0

	match _phase:
		Phase.RAISE:
			_anim_t += delta
			var f: int = int(floor(_anim_t * ANIM_FPS))
			if f >= GUARD_FRAME:
				f = GUARD_FRAME
				_phase = Phase.HOLD
			_set_frame(f)
		Phase.HOLD:
			_set_frame(GUARD_FRAME)
		Phase.REACT:
			_anim_t += delta
			var rf: int = REACT_START + int(floor(_anim_t * ANIM_FPS))
			if rf >= REACT_END:
				rf = REACT_END
				_phase = Phase.HOLD  # back to the guard hold next frame
			_set_frame(rf)

	if _elapsed >= BLOCK_DURATION:
		return attack_recover_state()
	return null


func physics_update(delta: float) -> State:
	# Plant and guard — hold position behind the shield.
	plant_physics(delta)
	return null


func exit() -> void:
	super.exit()
	allow_flip = true
	if animations != null:
		animations.speed_scale = 1.0  # restore normal playback for the next state
	var enemy := parent as EnemyBase
	if enemy:
		enemy.set_guarding(false)
		enemy.start_block_cooldown()


func _set_frame(f: int) -> void:
	if animations != null and animations.frame != f:
		animations.frame = f
