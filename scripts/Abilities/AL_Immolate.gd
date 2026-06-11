extends Node

const EnemyStatus := preload("res://scripts/Gameplay/enemy_status.gd")

## Immolate — the Staff discipline's single-target burn-setter (projectile). The
## bolt's on_hit ignites the target with a stacking burn DOT. Each stack ticks a
## fraction of the applier's MAGICATTACK per second. This is the mage analogue of
## the bow's Barbed Shot / sword's Hemorrhage.
##
## Like Barbed Shot, the DOT is implemented via direct meta-tracking on the
## EnemyBase node (enemies don't yet carry a full BuffComponent) with its OWN
## meta key, so a mage burn, a bow bleed, and a sword bleed all stack/refresh
## independently rather than overwriting each other.
##
## Burn scales on MAGICATTACK (StatType 13) — mages don't use WEAPONATTACK.

const MAX_STACKS: int = 3
const TICK_INTERVAL: float = 1.0
const DURATION_SECONDS: float = 6.0
## Per tick per stack = this fraction of the ability's MAX hit (max_range × dmg%),
## via CombatComponent.dot_scaling_base — so the burn scales with mastery +
## attributes + ability level + gear like direct damage (project_dot_scaling_divergence).
## Lower than the bleeds' fraction because Immolate's Fire reaction multiplies
## per_tick (fire_mult) and adds stacks. Was 0.18 × raw MAGICATTACK.
const DAMAGE_PER_STACK_FRAC: float = 0.10

const BURN_META: String = "immolate_burn"

## FIRE-STANCE REACTION (signature synergy). When the player's StaffElement
## signature is on FIRE while Immolate hits, the burn IGNITES — it ramps faster,
## hits harder, builds higher, and its ticks SPLASH to nearby enemies. This is the
## payoff for committing to the fire stance, and fixes the old feel where the fire
## rider's burn and Immolate's burn were two separate weak DOTs that never reacted.
const FIRE_STACKS_PER_HIT: int = 2       ## 2 stacks/hit under Fire (vs 1) — ramps fast
const FIRE_POTENCY_MULT: float = 1.5     ## +50% per-tick damage under Fire
const FIRE_BONUS_MAX_STACKS: int = 2     ## burn builds 2 stacks higher under Fire
const FIRE_SPLASH_PCT: float = 0.5       ## splash tick = 50% of the main tick damage
const FIRE_SPLASH_RADIUS: float = 140.0  ## px; same map only
const FIRE_SPLASH_MAX_TARGETS: int = 3   ## nearby enemies the splash licks each tick


## Returns true if the player is currently in the FIRE element stance (StaffElement
## signature). Safe on a missing component — the reaction simply doesn't apply.
func _is_fire_active(owner_node: Node) -> bool:
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return false
	# Element.FIRE == 0 in StaffElementComponent (stable enum).
	return sec.get_current_element() == 0


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return

	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	# Immolate upgrade reads (mirrors the Barbed Shot / Hemorrhage tree):
	#  burn_potency_bonus   -> +% per-tick damage
	#  burn_max_stack_bonus -> +max stacks
	#  burn_duration_bonus  -> +seconds
	var potency_bonus: float = 0.0
	var stack_bonus: int = 0
	var duration_bonus: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		potency_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "burn_potency_bonus")
		stack_bonus = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "burn_max_stack_bonus"))
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "burn_duration_bonus")

	# FIRE-stance reaction: ramp harder/faster/higher and flag the burn to splash.
	var fire: bool = _is_fire_active(_owner_node)
	var fire_mult: float = FIRE_POTENCY_MULT if fire else 1.0
	var stacks_added: int = FIRE_STACKS_PER_HIT if fire else 1
	var combat = _owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and combat.has_method("dot_scaling_base") else maxi(1, magic_attack)
	var per_tick: int = maxi(1, roundi(dot_base * DAMAGE_PER_STACK_FRAC * (1.0 + potency_bonus) * fire_mult))
	var max_stacks: int = MAX_STACKS + stack_bonus + (FIRE_BONUS_MAX_STACKS if fire else 0)
	var duration: float = DURATION_SECONDS + duration_bonus

	if _target.has_meta(BURN_META):
		# Existing burn — add stacks (capped) and refresh duration. Under Fire this
		# adds 2 stacks per hit, so the burn ramps to its (raised) cap fast.
		var existing: Dictionary = _target.get_meta(BURN_META)
		existing["stacks"] = mini(max_stacks, int(existing.get("stacks", 1)) + stacks_added)
		existing["remaining"] = duration
		existing["per_tick"] = per_tick  # refresh to latest applier's damage
		existing["fire"] = fire          # latest application sets the splash flag
		_target.set_meta(BURN_META, existing)
		EnemyStatus.register(_target, EnemyStatus.TAG_BURN, BURN_META, _owner_node)
		return

	# Fresh burn — set up state and start the tick timer.
	var fresh: Dictionary = {
		"stacks": mini(max_stacks, stacks_added),
		"remaining": duration,
		"per_tick": per_tick,
		"applier": _owner_node,
		"fire": fire,
	}
	_target.set_meta(BURN_META, fresh)
	_schedule_burn_tick(_target)
	EnemyStatus.register(_target, EnemyStatus.TAG_BURN, BURN_META, _owner_node)


## When a burn tick downs an enemy, the regular combat-kill pathway
## (combat.gd._execute_hit) never runs — so mastery XP and on_kill passive
## events don't fire. This mirrors that logic locally for burn kills,
## crediting the applier the same way a direct hit would. Copied from
## AL_BarbedShot._credit_bleed_kill.
func _credit_burn_kill(applier, target: Node) -> void:
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


## Living enemies within `radius` of `origin`, ON THE SAME MAP, nearest-first,
## excluding `origin`. Used by the FIRE-stance splash. The "Enemies" group is GLOBAL
## across maps (SubViewport-per-map architecture), so we MUST map-filter — otherwise
## a coordinate overlap on another map would get burned. We resolve `origin`'s map
## via MapManager.active_maps (the map whose scene_instance is its ancestor) and
## keep only enemies under that same map. Self-contained (no CombatComponent dep —
## the burn tick can outlive the attacker).
func _nearby_enemies(origin: Node, radius: float, max_count: int) -> Array:
	var out: Array = []
	if not is_instance_valid(origin) or origin.get_tree() == null:
		return out
	# Resolve the origin enemy's map node.
	var origin_map: Node = null
	for map_id in MapManager.active_maps.keys():
		var inst = MapManager.active_maps[map_id].get("scene_instance")
		if is_instance_valid(inst) and inst.is_ancestor_of(origin):
			origin_map = inst
			break
	var origin_pos: Vector2 = origin.global_position
	for enemy in origin.get_tree().get_nodes_in_group("Enemies"):
		if enemy == origin or not is_instance_valid(enemy):
			continue
		if origin_map != null and not origin_map.is_ancestor_of(enemy):
			continue  # different map — skip (global group)
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		if enemy.global_position.distance_to(origin_pos) > radius:
			continue
		out.append(enemy)
	out.sort_custom(func(a, b):
		return a.global_position.distance_to(origin_pos) < b.global_position.distance_to(origin_pos)
	)
	if out.size() > max_count:
		return out.slice(0, max_count)
	return out


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
		# Attribute the burn back to the original applier so enemy aggro,
		# damage-by-player tallies, and any source-dependent UI fire correctly.
		# The applier may have despawned — fall back to null.
		var applier = state.get("applier", null)
		if not is_instance_valid(applier):
			applier = null
		# Burn bypasses enemy i-frames (otherwise the 1s tick lines up with the
		# 1s invuln from each hit and half the ticks get absorbed).
		# show_number=true so the DOT is visible.
		var was_alive: bool = not health_comp.is_dead
		health_comp.take_damage(damage, applier, true, false, true)
		if target.has_method("play_dot"):
			target.play_dot("burn")

		# If the burn tick downed the enemy, fire the same kill events
		# combat.gd._execute_hit fires for normal hit kills.
		if was_alive and health_comp.is_dead:
			_credit_burn_kill(applier, target)

		# FIRE-stance splash: a fire-enhanced burn licks nearby enemies each tick
		# for a fraction of the main tick. This is the "splash AoE fire" reaction —
		# under the fire stance a single Immolate spreads pressure to the pack.
		if bool(state.get("fire", false)):
			var splash: int = maxi(1, roundi(damage * FIRE_SPLASH_PCT))
			for near in _nearby_enemies(target, FIRE_SPLASH_RADIUS, FIRE_SPLASH_MAX_TARGETS):
				var nh = near.get("health_component")
				if nh == null or not is_instance_valid(nh) or nh.is_dead:
					continue
				var n_alive: bool = not nh.is_dead
				nh.take_damage(splash, applier, true, false, true)
				if n_alive and nh.is_dead:
					_credit_burn_kill(applier, near)

	state["remaining"] = float(state.get("remaining", 0.0)) - TICK_INTERVAL
	if state["remaining"] <= 0.0:
		target.remove_meta(BURN_META)
		return

	target.set_meta(BURN_META, state)
	# Schedule next tick.
	_schedule_burn_tick(target)
