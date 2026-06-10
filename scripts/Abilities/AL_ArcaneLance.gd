extends Node

## Arcane Lance — LIGHTNING-stance reaction. Arcane Lance is the staff's
## multi-pulse beam. On a normal hit the generic element rider (when LIGHTNING is
## active) already applies its baseline shock/chain. This logic_script ADDS a
## dedicated bonus chain-shock when the player's StaffElement signature is
## LIGHTNING: each landed hit jumps a follow-up bolt to up to 2 nearby same-map
## enemies for a fraction of the hit, reinforcing lightning's crowd-clear identity.
##
## REUSES StaffElementComponent's chain idea (a flat-% follow-up to nearby living
## enemies) with AL_Immolate's map-filtered _nearby_enemies helper (the "Enemies"
## group is GLOBAL across maps under the SubViewport-per-map architecture, so the
## search MUST be map-scoped or it would zap a coordinate-overlapping enemy on
## another map). DOT-style kills are credited via a copied _credit_kill helper so
## mastery XP + on_kill passives still fire when the bonus lands the killing blow.
##
## Off-LIGHTNING this does nothing.

## Each chain hop deals this fraction of the triggering hit's damage.
const CHAIN_DAMAGE_PCT: float = 0.4
## How many nearby enemies the bonus chain-shock licks per hit.
const CHAIN_MAX_TARGETS: int = 2
## px; same-map search radius for chain targets.
const CHAIN_RADIUS: float = 180.0


## Returns true if the player's StaffElement signature is currently LIGHTNING.
## Element.LIGHTNING == 2 in StaffElementComponent (stable enum). Safe on a
## missing component — the reaction simply doesn't apply.
func _is_lightning_active(owner_node: Node) -> bool:
	var sec = owner_node.get("staff_element_component")
	if sec == null or not is_instance_valid(sec) or not sec.has_method("get_current_element"):
		return false
	return sec.get_current_element() == 2


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return
	# Storm Lance (T3): the chain-shock fires in ANY stance.
	if not _is_lightning_active(_owner_node) and not _reaction_any_stance(_owner_node, _ability):
		return  # off-LIGHTNING: generic rider handles the baseline

	# Scale the chain off the triggering hit's damage so it stays proportional at
	# every level. We don't have the exact landed number here, so derive a
	# representative hit from MAGICATTACK (staves scale on StatType 13).
	var stats_comp = _owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)
	var combat = _owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and is_instance_valid(combat) and combat.has_method("dot_scaling_base") else maxi(1, magic_attack)
	var chain_dmg: int = maxi(1, roundi(dot_base * CHAIN_DAMAGE_PCT))

	for near in _nearby_enemies(_target, CHAIN_RADIUS, CHAIN_MAX_TARGETS):
		var nh = near.get("health_component")
		if nh == null or not is_instance_valid(nh) or nh.is_dead:
			continue
		var n_alive: bool = not nh.is_dead
		# Bonus shock bypasses enemy i-frames so it isn't swallowed by the
		# just-landed hit's invuln. Attributed to owner_node for aggro / XP.
		nh.take_damage(chain_dmg, _owner_node, true, false, true)
		if n_alive and nh.is_dead:
			_credit_kill(_owner_node, near)


## When the chain-shock lands the killing blow, the regular combat-kill pathway
## (combat.gd._execute_hit) never runs — so mastery XP and on_kill passive events
## don't fire. This credits the applier the same way a direct hit would. Mirrors
## AL_Immolate._credit_burn_kill / StaffElementComponent._credit_dot_kill.
func _credit_kill(applier, target: Node) -> void:
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


## Living enemies within `radius` of `origin`, ON THE SAME MAP, nearest-first,
## excluding `origin`. The "Enemies" group is GLOBAL across maps
## (SubViewport-per-map architecture), so we MUST map-filter — otherwise a
## coordinate overlap on another map would get zapped. Resolves `origin`'s map via
## MapManager.active_maps (the map whose scene_instance is its ancestor). Copied
## from AL_Immolate._nearby_enemies (self-contained — no CombatComponent dep).
func _nearby_enemies(origin: Node, radius: float, max_count: int) -> Array:
	var out: Array = []
	if not is_instance_valid(origin) or origin.get_tree() == null:
		return out
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


## Stance-breaker T3 ("reaction_any_stance"): true when the owned variant lets
## this ability's element reaction fire regardless of the active stance.
func _reaction_any_stance(owner_node: Node, ability: AbilityData) -> bool:
	var ability_comp = owner_node.get("ability_component")
	if ability_comp == null or ability == null or not ability_comp.has_method("get_ability_upgrade_magnitude"):
		return false
	return ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "reaction_any_stance") > 0.0
