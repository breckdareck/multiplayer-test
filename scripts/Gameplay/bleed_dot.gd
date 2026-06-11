class_name BleedDot
extends RefCounted

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## Shared server-authoritative bleed/poison DOT helper. Extracted from the proven
## AL_BarbedShot / AL_Hemorrhage meta-tracking pattern so any ability (Caltrops'
## Poisoned Spikes, Mark of the Hunt's Bleeding Mark, Death Mark's bleed variant)
## can apply a stacking damage-over-time without re-implementing the timer +
## stack + kill-credit machinery.
##
## Enemies don't yet have a full BuffComponent (deferred), so the DOT is tracked
## via a meta dictionary on the EnemyBase node. Each distinct ability passes its
## OWN `meta_key` so a sword bleed, a bow bleed and a poison stack/refresh
## independently rather than overwriting each other.
##
## All methods are static and server-side; the caller is responsible for the
## `multiplayer.is_server()` guard (every AL already guards at its entry point).

const TICK_INTERVAL: float = 1.0


## Apply (or refresh + stack) a bleed on `target`. `per_tick` is the absolute
## damage per stack per tick; `max_stacks` caps stacking; `duration` is refreshed
## on every re-application. `applier` is credited for ticks and DOT kills.
static func apply(target: Node, applier: Node, per_tick: int, max_stacks: int, duration: float, meta_key: String, dot_type: String = "bleed") -> void:
	if target == null or not is_instance_valid(target):
		return
	per_tick = maxi(1, per_tick)
	max_stacks = maxi(1, max_stacks)

	if target.has_meta(meta_key):
		var existing: Dictionary = target.get_meta(meta_key)
		existing["stacks"] = mini(max_stacks, int(existing.get("stacks", 1)) + 1)
		existing["remaining"] = duration
		existing["per_tick"] = per_tick  # refresh to the latest applier's damage
		existing["applier"] = applier
		existing["dot_type"] = dot_type
		target.set_meta(meta_key, existing)
		# Status-tag layer (ADR 0013): every application event registers +
		# runs escalation checks, refreshes included.
		EnemyStatus.register(target, dot_type, meta_key, applier)
		return

	target.set_meta(meta_key, {
		"stacks": 1,
		"remaining": duration,
		"per_tick": per_tick,
		"applier": applier,
		"dot_type": dot_type,  # "bleed" / "poison" — drives the enemy DoT visual
	})
	_schedule_tick(target, meta_key)
	EnemyStatus.register(target, dot_type, meta_key, applier)


static func _schedule_tick(target: Node, meta_key: String) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(TICK_INTERVAL).timeout.connect(
		func(): _on_tick(target, meta_key)
	)


static func _on_tick(target: Node, meta_key: String) -> void:
	if not is_instance_valid(target) or not target.has_meta(meta_key):
		return

	var state: Dictionary = target.get_meta(meta_key)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(meta_key)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# Bleed bypasses i-frames (the 1s tick would otherwise line up with the 1s
		# invuln from each hit and lose half its ticks). show_number=true so the
		# DOT is visible.
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)
		if was_alive and health_comp.is_dead:
			_credit_kill(applier, target)

	# Per-tick visual (blood spurt / green gas + tint), synced to all peers.
	if target.has_method("play_dot"):
		target.play_dot(str(state.get("dot_type", "bleed")))

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(meta_key)
		return
	target.set_meta(meta_key, state)
	_schedule_tick(target, meta_key)


## When a DOT tick downs an enemy, combat.gd._execute_hit never runs — so mastery
## XP and on-kill passives wouldn't fire. Mirror that crediting locally (same
## shape as AL_BarbedShot._credit_bleed_kill).
static func _credit_kill(applier, target: Node) -> void:
	if applier == null or not is_instance_valid(applier):
		return
	if target == null or not is_instance_valid(target):
		return

	var mastery_comp = applier.get("weapon_mastery_component")
	var combat_comp = applier.get("combat_component")
	if mastery_comp and combat_comp and "monster_level" in target and applier.level_component:
		var kill_xp: int = WeaponMasteryComponent.compute_kill_xp(
			target.monster_level,
			applier.level_component.level
		)
		var kill_disc: int = combat_comp._active_weapon_discipline()
		if kill_disc != -1:
			mastery_comp.grant_mastery_xp_server(kill_disc, kill_xp)
		var sec_disc: int = combat_comp._secondary_weapon_discipline()
		if sec_disc != -1 and sec_disc != kill_disc:
			mastery_comp.grant_mastery_xp_server(sec_disc, kill_xp)

	var ability_comp = applier.get("ability_component")
	if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
		ability_comp.dispatch_passive_event_on_kill(target)
