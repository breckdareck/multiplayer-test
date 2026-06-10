extends Node

## Envenom — the Dagger discipline's single-target poison-setter. A coated-blade
## strike whose on_hit applies (or refreshes and stacks) a poison DOT on the
## target. Each stack ticks 20% of the applier's WEAPONATTACK per second for
## 6 seconds. Max 3 stacks.
##
## This is the dagger analogue of the bow's Barbed Shot / sword's Hemorrhage and
## is a near-copy of AL_BarbedShot — but it uses its OWN meta key
## (`envenom_poison`) so a dagger poison stacks/refreshes independently of any
## sword bleed or bow bleed already on the same enemy rather than overwriting it.
##
## Enemies don't yet have a full BuffComponent (deferred), so the DOT is tracked
## via direct meta on the EnemyBase node, exactly like Hemorrhage/Barbed Shot.

const MAX_STACKS: int = 3
const TICK_INTERVAL: float = 1.0
const DURATION_SECONDS: float = 6.0
## Per tick per stack = this fraction of the ability's MAX hit (max_range × dmg%),
## via CombatComponent.dot_scaling_base — so poison scales with attributes +
## mastery + ability level + gear like direct damage (project_dot_scaling_divergence).
## Lower than the bleeds' fraction because poison runs more stacks for longer (and
## Vendetta consumes them for burst). Was 0.20 × raw WEAPONATTACK.
const DAMAGE_PER_STACK_FRAC: float = 0.06

const POISON_META: String = "envenom_poison"

## Stealth-modified behavior (v1 design grilling 2026-05-31, medium fix for
## dagger's binary-stealth failure mode): when cast in Shadowmeld stealth,
## Envenom applies 2 Poison stacks per hit instead of 1. Ramps the
## Toxicology synergy faster and makes "what should I cast WHILE in stealth"
## a real decision rather than just "swing once for the ambush ×2."
const STEALTH_STACKS_PER_HIT: int = 2


## Returns true if the dagger user is currently in Shadowmeld stealth.
## Safe on a missing component — the modifier simply doesn't apply.
func _is_stealthed(owner_node: Node) -> bool:
	var sm = owner_node.get("shadowmeld_component")
	if sm == null or not is_instance_valid(sm) or not sm.has_method("is_stealthed"):
		return false
	return sm.is_stealthed()


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)

	# Envenom upgrade reads (mirrors the Hemorrhage / Barbed Shot trees):
	#  poison_potency_bonus   → +% per-tick damage
	#  poison_max_stack_bonus → +max stacks
	#  poison_duration_bonus  → +seconds
	var potency_bonus: float = 0.0
	var stack_bonus: int = 0
	var duration_bonus: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		potency_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "poison_potency_bonus")
		stack_bonus = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "poison_max_stack_bonus"))
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "poison_duration_bonus")

	var combat = _owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and combat.has_method("dot_scaling_base") else maxi(1, wpn_attack)
	var per_tick: int = maxi(1, roundi(dot_base * DAMAGE_PER_STACK_FRAC * (1.0 + potency_bonus)))
	var max_stacks: int = MAX_STACKS + stack_bonus
	var duration: float = DURATION_SECONDS + duration_bonus

	# Stealth-modified: in Shadowmeld, apply 2 stacks per hit instead of 1.
	var stacks_added: int = STEALTH_STACKS_PER_HIT if _is_stealthed(_owner_node) else 1

	if _target.has_meta(POISON_META):
		# Existing poison — increment stack count (capped) and refresh duration.
		var existing: Dictionary = _target.get_meta(POISON_META)
		existing["stacks"] = mini(max_stacks, int(existing.get("stacks", 1)) + stacks_added)
		existing["remaining"] = duration
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		_target.set_meta(POISON_META, existing)
		EnemyStatus.register(_target, EnemyStatus.TAG_POISON, POISON_META, _owner_node)
		return

	# Fresh poison — set up state and start the tick timer.
	var fresh: Dictionary = {
		"stacks": mini(max_stacks, stacks_added),
		"remaining": duration,
		"per_tick": per_tick,
		"applier": _owner_node,
	}
	_target.set_meta(POISON_META, fresh)
	_schedule_poison_tick(_target)
	EnemyStatus.register(_target, EnemyStatus.TAG_POISON, POISON_META, _owner_node)


## When a poison tick downs an enemy, the regular combat-kill pathway
## (combat.gd._execute_hit) never runs — so mastery XP and on_kill passive
## events don't fire. This mirrors that logic locally for poison kills,
## crediting the applier the same way a direct hit would.
func _credit_poison_kill(applier, target: Node) -> void:
	if applier == null or not is_instance_valid(applier):
		return
	if target == null or not is_instance_valid(target):
		return

	# Mastery XP — credit both equipped weapons per the same rule
	# combat.gd uses for at-the-moment-of-kill XP.
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

	# On-kill passives (Bloodthirst etc.).
	var ability_comp = applier.get("ability_component")
	if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
		ability_comp.dispatch_passive_event_on_kill(target)


func _schedule_poison_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(TICK_INTERVAL).timeout.connect(
		func():
			_on_poison_tick(target)
	)


func _on_poison_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(POISON_META):
		return

	var state: Dictionary = target.get_meta(POISON_META)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(POISON_META)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		# Attribute the poison back to the original applier so enemy aggro,
		# damage-by-player tallies, and any source-dependent UI fire correctly.
		# The applier may have despawned — fall back to null.
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# Poison bypasses enemy i-frames (otherwise the 1s tick lines up with
		# the 1s invuln from each hit and half the ticks get absorbed).
		# show_number=true so the DOT is visible.
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)
		if target.has_method("play_dot"):
			target.play_dot("poison")

		# If the poison tick downed the enemy, fire the same kill events
		# combat.gd._execute_hit fires for normal hit kills.
		if was_alive and health_comp.is_dead:
			_credit_poison_kill(applier, target)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(POISON_META)
		return

	target.set_meta(POISON_META, state)
	# Schedule next tick.
	_schedule_poison_tick(target)
