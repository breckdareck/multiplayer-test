extends EnemyState
## Boss telegraphed special-attack state. The boss roots in place, broadcasts a
## growing telegraph ring to every peer (incl. the host), winds up for
## special_telegraph_time, then lands one authoritative AoE before handing back
## to chase. Entered from EnemyBase._boss_special_tick() (the readiness gate);
## all of the special's BEHAVIOR lives here rather than in EnemyBase._process.
##
## Injected at runtime by EnemyBase._ensure_boss_special_state() — only for
## enemies whose EnemyData.is_boss is true — so it carries no scene wiring and
## locates its sibling states by name. The node is created on every peer (so the
## state-name sync lookup resolves on clients), but the windup/damage only ever
## advances on the server, where StateMachine.process_frame runs.

## Seconds elapsed since the windup began (server-driven).
var _elapsed: float = 0.0
## True once this windup has dealt its damage, so a single entry fires once.
var _fired: bool = false
## Snapshot of where the telegraph was placed + how big, taken on enter so the
## AoE lands where the ring was shown even if the boss is nudged mid-windup.
var _center: Vector2 = Vector2.ZERO
var _radius: float = 120.0
var _windup: float = 1.0


func enter() -> void:
	super.enter()
	allow_flip = false
	_elapsed = 0.0
	_fired = false
	var enemy := parent as EnemyBase
	if enemy == null:
		return
	_center = enemy.global_position
	_radius = enemy.enemy_data.special_attack_radius if enemy.enemy_data else 120.0
	_windup = maxf(0.05, enemy.enemy_data.special_telegraph_time if enemy.enemy_data else 1.0)

	# Turn to face the threatened target so the windup reads as deliberate.
	if enemy.current_target != null and is_instance_valid(enemy.current_target):
		var dx: float = enemy.current_target.global_position.x - enemy.global_position.x
		if absf(dx) > 1.0:
			enemy.face_direction(1 if dx > 0.0 else -1)

	# Show the telegraph (server only; the downstream broadcast also guards, but
	# gate here so client-side enter() — which fires via the state-name sync — is
	# an explicit no-op).
	if multiplayer.is_server():
		enemy.broadcast_telegraph_ring(_center, _radius, _windup, Color(1.0, 0.2, 0.2, 0.55))


func process_frame(delta: float) -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return null
	# A killing blow mid-windup: let the death/cleanup flow take over.
	if enemy.health_component == null or enemy.health_component.is_dead:
		return null

	_elapsed += delta
	if not _fired and _elapsed >= _windup:
		_fired = true
		enemy.deal_boss_special_damage(_center, _radius)
		return _recover_state()
	return null


func physics_update(delta: float) -> State:
	# Commit: hold position through the windup (the telegraph is the player's tell;
	# the special can't be walked off by the boss itself).
	if parent == null:
		return null
	parent.velocity.x = move_toward(parent.velocity.x, 0.0, 600.0 * delta)
	parent.velocity.y += gravity * delta
	parent.move_and_slide()
	return null


func exit() -> void:
	super.exit()
	# Re-arm the cooldown whether the special completed or was interrupted, so an
	# interrupted windup doesn't let the boss immediately re-telegraph.
	var enemy := parent as EnemyBase
	if enemy:
		enemy.arm_boss_special_cooldown()


## Where to go once the special resolves: resume the chase if the target is still
## valid, otherwise fall back to patrol/idle.
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
