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
## Per tick per stack = this fraction of the ability's MAX hit (max_range × dmg%),
## via CombatComponent.dot_scaling_base — so the burn scales with mastery +
## attributes + ability level + gear like direct damage (project_dot_scaling_divergence).
## Was 0.12 × raw MAGICATTACK, which omitted the (primary×4+sec) multiplier.
const DAMAGE_PER_STACK_FRAC: float = 0.12

## Own meta key — independent of Immolate's "immolate_burn" and the rider's
## "staff_element_burn" so all three burns stack separately.
const BURN_META: String = "pyre_burst_burn"

## Fire-stance ground-pool (transformation locked in v1 design grilling
## 2026-05-31): a persistent fire patch at the explosion's epicenter that
## ticks damage on any enemy currently inside it. Uses the shared GroundZone
## helper from scripts/Gameplay/ground_zone.gd.
##
## Ground rectangle — fire pools on the floor, not in midair. Wide-x /
## short-y rect hugs the ground at the explosion impact point.
const POOL_RECT_SIZE: Vector2 = Vector2(180.0, 55.0)
const POOL_DURATION: float = 3.0
const POOL_TICK_INTERVAL: float = 1.0
## Pool tick = this fraction of the ability's MAX hit (same dot_scaling_base as the
## burn DOT). Stacks with the dedicated burn DOT applied per-enemy by the on_hit
## block above (independent meta keys).
const POOL_DAMAGE_FRAC: float = 0.10
const POOL_COLOR: Color = Color(0.95, 0.3, 0.1, 0.42)

## Per-cast dedupe: on_hit fires once per struck enemy, but the ground pool
## should spawn only ONCE per cast — at the first enemy hit's position
## (a reasonable proxy for the explosion's epicenter). Tracking the spawn
## frame on the owner lets us identify "same cast" without threading a cast
## ID through combat.gd: all hits from one Pyre Burst land in the same
## physics frame.
const POOL_FRAME_META: String = "pyre_burst_pool_spawned_frame"


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
	# Everburn (T3): the burn + fire pool ignite in ANY stance.
	if not _is_fire_active(_owner_node) and not _reaction_any_stance(_owner_node, _ability):
		return  # off-FIRE: direct AoE damage + generic rider handle the baseline

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	var combat = _owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and combat.has_method("dot_scaling_base") else maxi(1, magic_attack)
	var per_tick: int = maxi(1, roundi(dot_base * DAMAGE_PER_STACK_FRAC))

	# Fire-stance ground pool — spawn ONCE per cast at the first struck
	# enemy's position. The dedupe lives inside _try_spawn_fire_pool so this
	# fires for every on_hit call without spawning extra zones per enemy.
	# Placed BEFORE the burn-refresh early-return so a cast that hits an
	# already-burning enemy still drops its pool.
	_try_spawn_fire_pool(_owner_node, _target, dot_base)

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


## Fire-stance transformation: spawn a ground pool at the explosion epicenter
## ONCE per cast. on_hit fires per struck enemy, so we dedupe via a per-frame
## meta on the caster (all hits from one Pyre Burst land in the same physics
## frame). The first struck enemy's position is the spawn point — a reasonable
## proxy for the explosion's epicenter without threading the projectile's
## impact location through combat.gd.
func _try_spawn_fire_pool(owner_node: Node, first_target: Node, dot_base: int) -> void:
	var cur_frame: int = Engine.get_physics_frames()
	var last_spawn: int = int(owner_node.get_meta(POOL_FRAME_META, -1))
	if last_spawn == cur_frame:
		return  # already spawned this physics frame (same cast)
	owner_node.set_meta(POOL_FRAME_META, cur_frame)

	var pool_damage: int = maxi(1, roundi(dot_base * POOL_DAMAGE_FRAC))
	# load() rather than class_name reference for robustness against parse-order
	# issues (Godot 4 can intermittently fail to resolve class_name globals from
	# logic_scripts that are loaded lazily by ResourceManager).
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		first_target.global_position,
		POOL_RECT_SIZE,
		POOL_DURATION,
		POOL_TICK_INTERVAL,
		pool_damage,
		POOL_COLOR,
	)

	# Ground "juice" — a tiled fire band burning across the pool.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "fire_ground", first_target.global_position, POOL_RECT_SIZE.x, POOL_DURATION)


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
		if target.has_method("play_dot"):
			target.play_dot("burn")

		if was_alive and health_comp.is_dead:
			_credit_burn_kill(applier, target)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BURN_META)
		return

	target.set_meta(BURN_META, state)
	_schedule_burn_tick(target)


## Stance-breaker T3 ("reaction_any_stance"): true when the owned variant lets
## this ability's element reaction fire regardless of the active stance.
func _reaction_any_stance(owner_node: Node, ability: AbilityData) -> bool:
	var ability_comp = owner_node.get("ability_component")
	if ability_comp == null or ability == null or not ability_comp.has_method("get_ability_upgrade_magnitude"):
		return false
	return ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "reaction_any_stance") > 0.0
