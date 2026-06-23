extends EnemyAttackState
## Shared base for TIME-WINDOWED enemy attacks: a wind-up (telegraph), an active
## delivery window, then a recovery tail before returning to chase. Subclasses plug
## in the delivery via the _active_* / _clip_anim hooks; the lifecycle, timing,
## clip-stretch, plant-physics, recover and cooldown are owned here once.
##
## Replaces the copy-pasted timing/recover/physics that used to live in each of
## enemy_ranged_attack and enemy_secondary_attack. Concrete deliveries:
##   - EnemyProjectileAttack — fires a homing projectile when the window opens.
##   - EnemyHitboxAttack      — arms a damage hitbox + shows a breath plume.
##
## Authored as a scene state node OR injected by EnemyBase; runs on every peer
## (enter/exit replicate; the server-only delivery happens in process_frame).

## Which EnemyData fields + cooldown this attack draws on: PRIMARY = the ranged_* /
## main attack cooldown; SECONDARY = the secondary_* fields / secondary cooldown.
enum Config { PRIMARY, SECONDARY }
@export var config: Config = Config.PRIMARY

@export_group("Timing")
## Wind-up seconds before the delivery window opens (the telegraph / cast read).
@export var windup: float = 0.45
## Seconds the delivery window stays open (a projectile fires once at the open;
## a breath stays live and damaging for this whole span).
@export var active: float = 0.0
## Recovery seconds held after the window closes before returning to chase.
@export var recover: float = 0.25

var _elapsed: float = 0.0
var _active_open: bool = false


func enter() -> void:
	super.enter()  # zeroes velocity
	allow_flip = false
	_elapsed = 0.0
	_active_open = false
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
	if not _active_open and _elapsed >= windup:
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
	if config == Config.SECONDARY:
		enemy.start_secondary_cooldown()
	else:
		enemy.start_attack_cooldown()


# --- Delivery hooks (override in subclasses; all no-ops by default) ----------

## The animation clip to play for this attack (stretched to the full duration).
func _clip_anim(_enemy: EnemyBase) -> String:
	return ""

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
