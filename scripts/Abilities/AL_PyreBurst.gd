extends Node

## Pyre Burst — FIRE-stance reaction. Pyre Burst is the staff's AoE fireball: it
## erupts on impact and hits up to several enemies. On a normal hit the generic
## element rider (when FIRE is active) handles whatever baseline burn the stance
## provides. This logic_script ADDS a dedicated burn DOT to EACH struck enemy when
## the player's StaffElement signature is FIRE — the payoff for committing to the
## fire stance while throwing a fire AoE.
##
## REUSES AL_Immolate's exact meta-tracked stacking-DOT pattern (enemies carry no
## full BuffComponent), but with its OWN meta key "pyre_burst_burn" so it stacks
## INDEPENDENTLY of an Immolate burn, a staff-element-rider burn, a bow bleed, or a
## sword bleed rather than overwriting them.
##
## Pyre Burst is AoE/multi-target, so combat.gd fires on_hit once per enemy hit —
## each enemy gets its own burn instance. Off-FIRE this does nothing (the spell's
## direct damage + the generic rider already handle the baseline).

const MAX_STACKS: int = 2
const TICK_INTERVAL: float = 1.0
const DURATION_SECONDS: float = 4.0
## 12% of MAGICATTACK per tick per stack. maxi(1, ...) keeps it visible at low gear.
const DAMAGE_PER_STACK_PCT: float = 0.12

## Own meta key — independent of Immolate's "immolate_burn" and the rider's
## "staff_element_burn" so all three burns stack separately.
const BURN_META: String = "pyre_burst_burn"


## Returns true if the player's StaffElement signature is currently FIRE.
## Element.FIRE == 0 in StaffElementComponent (stable enum). Safe on a missing
## component — the reaction simply doesn't apply.
func _is_fire_active(owner_node: Node) -> bool:
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return false
	return sec.get_current_element() == 0


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return
	if not _is_fire_active(_owner_node):
		return  # off-FIRE: direct AoE damage + generic rider handle the baseline

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	var per_tick: int = maxi(1, roundi(magic_attack * DAMAGE_PER_STACK_PCT))

	if _target.has_meta(BURN_META):
		# Existing pyre burn — add a stack (capped) and refresh duration.
		var existing: Dictionary = _target.get_meta(BURN_META)
		existing["stacks"] = mini(MAX_STACKS, int(existing.get("stacks", 1)) + 1)
		existing["remaining"] = DURATION_SECONDS
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		existing["applier"] = _owner_node
		_target.set_meta(BURN_META, existing)
		return

	# Fresh burn — set up state and start the tick timer.
	var fresh: Dictionary = {
		"stacks": 1,
		"remaining": DURATION_SECONDS,
		"per_tick": per_tick,
		"applier": _owner_node,
	}
	_target.set_meta(BURN_META, fresh)
	_schedule_burn_tick(_target)


## When a burn tick downs an enemy, the regular combat-kill pathway
## (combat.gd._execute_hit) never runs — so mastery XP and on_kill passive
## events don't fire. This mirrors that logic locally for burn kills, crediting
## the applier the same way a direct hit would. Copied from
## AL_Immolate._credit_burn_kill.
func _credit_burn_kill(applier, target: Node) -> void:
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


func _schedule_burn_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	target.get_tree().create_timer(TICK_INTERVAL).timeout.connect(
		func():
			_on_burn_tick(target)
	)


func _on_burn_tick(target: Node) -> void:
	if not is_instance_valid(target):
		return
	if not target.has_meta(BURN_META):
		return

	var state: Dictionary = target.get_meta(BURN_META)
	var health_comp = target.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp) or health_comp.is_dead:
		target.remove_meta(BURN_META)
		return

	var damage: int = int(state.get("per_tick", 1)) * int(state.get("stacks", 1))
	if damage > 0:
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# Burn bypasses enemy i-frames (otherwise the 1s tick lines up with the
		# 1s invuln from each hit and half the ticks get absorbed).
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)

		if was_alive and health_comp.is_dead:
			_credit_burn_kill(applier, target)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BURN_META)
		return

	target.set_meta(BURN_META, state)
	_schedule_burn_tick(target)
