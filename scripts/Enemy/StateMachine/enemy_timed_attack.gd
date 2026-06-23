extends EnemyAttackState
## Shared base for TIME-WINDOWED enemy attacks: a wind-up (telegraph), an active
## delivery window, then a recovery tail before returning to chase. Each attack node
## OWNS its own config (anim/cooldown + a reach CollisionShape2D and delivery specifics) and
## its own cooldown clock; chase polls can_start() to decide when to enter it.
## Concrete deliveries:
##   - EnemyProjectileAttack — fires a homing projectile when the window opens.
##   - EnemyHitboxAttack      — arms a damage hitbox + shows a breath plume.
##
## Authored as a scene state node under StateMachine; chase enters it via the poll
## (first attack-state child whose can_start is true, in child order).

@export_group("Timing")
## Wind-up seconds before the delivery window opens (the telegraph / cast read).
@export var windup: float = 0.45
## Seconds the delivery window stays open (a projectile fires once at the open;
## a breath stays live and damaging for this whole span).
@export var active: float = 0.0
## Recovery seconds held after the window closes before returning to chase.
@export var recover: float = 0.25

@export_group("Attack")
## Clip to play for this attack (stretched to windup+active+recover). "" = the
## subclass default (a projectile auto-picks a cast pose; a breath has no default).
@export var attack_anim: String = ""
## Seconds between uses of THIS attack. 0 = inherit enemy_data.attack_cooldown.
@export var cooldown: float = 0.0

var _elapsed: float = 0.0
var _active_open: bool = false
## Latches once the active window has opened this attack, so a zero-length window
## (a fire-once projectile, active = 0) can't re-trigger _active_start every frame.
var _active_started: bool = false
## This attack's own cooldown clock (msec); chase won't enter it until now >= this.
var _ready_at: int = 0


# --- Poll interface (chase calls these) -------------------------------------

## Can chase enter this attack right now? Off this attack's own cooldown AND the
## target is inside its reach shape. (Facing/reaction-delay is gated by chase.)
func can_start(enemy: EnemyBase, target: Node2D) -> bool:
	if not is_instance_valid(target):
		return false
	if Time.get_ticks_msec() < _ready_at:
		return false
	return in_reach(enemy, target)


## Subclass: is the target inside this attack's reach shape? Chase also polls this —
## cooldown aside — to decide when to stop closing in and hold to wind up / cool down.
func in_reach(_enemy: EnemyBase, _target: Node2D) -> bool:
	return false


## Resolved cooldown seconds — this node's export, else the enemy-wide default.
func _resolved_cooldown(enemy: EnemyBase) -> float:
	if cooldown > 0.0:
		return cooldown
	return enemy.enemy_data.attack_cooldown if enemy.enemy_data else 1.4


# --- Lifecycle --------------------------------------------------------------

func enter() -> void:
	super.enter()  # zeroes velocity
	allow_flip = false
	_elapsed = 0.0
	_active_open = false
	_active_started = false
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	if is_instance_valid(enemy.current_target):
		enemy.face_toward(enemy.current_target.global_position)
	play_clip_stretched(_clip_anim(enemy), windup + active + recover)
	_attack_enter(enemy)


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return attack_recover_state()
	if enemy.health_component == null or enemy.health_component.is_dead:
		return attack_recover_state()

	_elapsed += delta
	if not _active_started and _elapsed >= windup:
		_active_started = true
		_active_open = true
		_active_start(enemy)
	if _active_open:
		if _elapsed < windup + active:
			_active_tick(enemy)
		else:
			_active_open = false
			_active_end(enemy)

	if _elapsed >= windup + active + recover:
		return attack_recover_state()
	return null


func physics_update(delta: float) -> State:
	plant_physics(delta)
	return null


func exit() -> void:
	super.exit()
	allow_flip = true
	if animations != null:
		animations.speed_scale = 1.0
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	# Cleanup if we left mid-window (interrupted), so a delivery never leaks live.
	if _active_open:
		_active_open = false
		_active_end(enemy)
	# Arm THIS attack's own cooldown (boss enrage/phase applied by enemy_base).
	_ready_at = enemy.attack_cooldown_until(_resolved_cooldown(enemy))


# --- Delivery hooks (override in subclasses; all no-ops by default) ----------

## The animation clip to play for this attack (stretched to the full duration).
func _clip_anim(_enemy: EnemyBase) -> String:
	return attack_anim

## Called once on enter, after facing + clip start (e.g. show a breath plume).
func _attack_enter(_enemy: EnemyBase) -> void:
	pass

## Called once when the active window opens (e.g. fire a projectile / arm a hitbox).
func _active_start(_enemy: EnemyBase) -> void:
	pass

## Called every frame the window is open (e.g. damage bodies in the hitbox).
func _active_tick(_enemy: EnemyBase) -> void:
	pass

## Called once when the window closes (or on interrupt) — tear down the delivery.
func _active_end(_enemy: EnemyBase) -> void:
	pass
