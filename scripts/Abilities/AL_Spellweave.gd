extends Node

## Spellweave (staff active) — CHANNEL + STANCE-AUGMENT. After a brief
## channel, releases an AMPLIFIED version of the current stance's
## signature effect at the caster's facing direction. The exact effect
## depends on the active StaffElement stance:
##   - FIRE      → spawns a larger / longer-duration version of the Pyre
##                 Burst-style ground pool ahead of the caster
##   - ICE       → applies a hard freeze (1.5s) to all enemies in a small
##                 area ahead, larger radius than Glacial Spike's single hit
##   - LIGHTNING → fires a chain blast that hops further with more bonus
##                 damage than the stance rider's baseline
##
## Engages the stance gauge — Spellweave is meaningfully different per
## stance, so a Staff build commits to its current element and gets a
## tailored amplified payoff. Mismatch behavior: in NO stance (shouldn't
## happen — stance always defaults to FIRE), falls back to FIRE.

## Amplified Fire-stance pool — ground rectangle matching Pyre Burst's pool
## shape, but larger and longer-lived per the Spellweave amplification rule.
const FIRE_POOL_RECT_SIZE: Vector2 = Vector2(220.0, 65.0)
const FIRE_POOL_DURATION: float = 5.0
const FIRE_POOL_TICK: float = 1.0
const FIRE_POOL_DAMAGE_PCT: float = 0.15
const FIRE_POOL_COLOR: Color = Color(0.95, 0.3, 0.1, 0.42)

const ICE_FREEZE_RADIUS: float = 110.0
const ICE_FREEZE_DURATION: float = 1.5
const ICE_FREEZE_META: String = "spellweave_freeze"
const ICE_SPAWN_OFFSET: float = 120.0

const LIGHTNING_CHAIN_HOPS: int = 6
const LIGHTNING_CHAIN_RADIUS: float = 220.0
const LIGHTNING_CHAIN_PCT: float = 0.60


func execute(owner_node: Node, ability: AbilityData, level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var sec = owner_node.get("staff_element_component")
	var element: int = 0  # default FIRE
	if sec != null and is_instance_valid(sec) and sec.has_method("get_current_element"):
		element = int(sec.get_current_element())

	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	# Upgrade reads: Doubled Weave (T3) fires the release twice; Echoing Weave
	# (T3) refunds MP if the release connects with an enemy; Wide Weave (T3)
	# widens the release reach in EVERY stance (Fire pool / Ice freeze /
	# Lightning chain) — stance-agnostic so it works whatever element you hold.
	var double_release: bool = false
	var mp_refund: float = 0.0
	var reach_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		double_release = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_double_release") > 0.0
		mp_refund = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_mp_refund")
		reach_bonus = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_zone_radius")

	_release(owner_node, element, facing, magic_attack, reach_bonus)

	# Echoing Weave: refund a fraction of the spell's MP cost if any enemy was in
	# reach of the release (approximated by proximity to the release area).
	if mp_refund > 0.0 and level_stats != null and _enemy_in_reach(owner_node, facing):
		var mana_comp = owner_node.get("mana_component")
		if mana_comp != null and is_instance_valid(mana_comp):
			var refund: int = int(float(level_stats.mana_cost) * mp_refund)
			if mana_comp.has_method("regain_mana"):
				mana_comp.regain_mana(refund, owner_node)
			elif "current_mana" in mana_comp:
				mana_comp.current_mana += refund

	# Doubled Weave: a second amplified release ~0.5s later.
	if double_release:
		owner_node.get_tree().create_timer(0.5).timeout.connect(
			func():
				if is_instance_valid(owner_node):
					_release(owner_node, element, facing, magic_attack, reach_bonus)
		)


## Dispatch the stance-appropriate amplified release. Factored out so Doubled
## Weave can re-fire it without re-entering execute (no re-cast / re-cost).
## `reach_bonus` (Wide Weave T3) widens whichever stance effect fires.
func _release(owner_node: Node, element: int, facing: int, magic_attack: int, reach_bonus: float = 0.0) -> void:
	match element:
		0:  # FIRE — spawn an amplified Pyre Burst-style pool
			_fire_pool(owner_node, facing, magic_attack, reach_bonus)
		1:  # ICE — area freeze
			_ice_freeze(owner_node, facing, reach_bonus)
		2:  # LIGHTNING — extended chain blast
			_lightning_chain(owner_node, magic_attack, reach_bonus)
		_:
			_fire_pool(owner_node, facing, magic_attack, reach_bonus)


## True if any living enemy is within a generous reach of the release area —
## the refund condition for Echoing Weave.
func _enemy_in_reach(owner_node: Node, facing: int) -> bool:
	var center: Vector2 = owner_node.global_position + Vector2(140.0 * float(facing), 0)
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if not (enemy is EnemyBase) or not is_instance_valid(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		if enemy.global_position.distance_to(center) <= 240.0:
			return true
	return false


func _fire_pool(owner_node: Node, facing: int, magic_attack: int, reach_bonus: float = 0.0) -> void:
	var spawn_pos: Vector2 = owner_node.global_position + Vector2(140.0 * float(facing), 0)
	var tick_damage: int = maxi(1, roundi(magic_attack * FIRE_POOL_DAMAGE_PCT))
	# Wide Weave widens the pool: full reach_bonus on width, a third on height.
	var rect_size: Vector2 = FIRE_POOL_RECT_SIZE + Vector2(reach_bonus, reach_bonus * 0.3)
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		spawn_pos,
		rect_size,
		FIRE_POOL_DURATION,
		FIRE_POOL_TICK,
		tick_damage,
		FIRE_POOL_COLOR,
	)

	# Ground "juice" — a tiled fire band across the amplified Fire-stance pool.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "fire_ground", spawn_pos, rect_size.x, FIRE_POOL_DURATION)


func _ice_freeze(owner_node: Node, facing: int, reach_bonus: float = 0.0) -> void:
	var center: Vector2 = owner_node.global_position + Vector2(ICE_SPAWN_OFFSET * float(facing), 0)
	# Wide Weave widens the freeze radius.
	var freeze_radius: float = ICE_FREEZE_RADIUS + reach_bonus
	var r2: float = freeze_radius * freeze_radius
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		if not (enemy is EnemyBase):
			continue
		var e := enemy as EnemyBase
		if (e.global_position - center).length_squared() > r2:
			continue
		var hc = e.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		if e.has_meta(ICE_FREEZE_META):
			continue
		var original_speed: float = e.movement_speed
		e.movement_speed = 0.0
		e.set_meta(ICE_FREEZE_META, original_speed)
		if e.animated_sprite and is_instance_valid(e.animated_sprite):
			e.animated_sprite.modulate = Color(0.4, 0.6, 1.0, 1.0)
		e.get_tree().create_timer(ICE_FREEZE_DURATION).timeout.connect(
			func():
				if not is_instance_valid(e):
					return
				if e.has_meta(ICE_FREEZE_META):
					e.movement_speed = e.get_meta(ICE_FREEZE_META)
					e.remove_meta(ICE_FREEZE_META)
				if e.animated_sprite and is_instance_valid(e.animated_sprite):
					e.animated_sprite.modulate = Color.WHITE
		)


func _lightning_chain(owner_node: Node, magic_attack: int, reach_bonus: float = 0.0) -> void:
	# Find the nearest enemy as the initial target, then chain.
	# Wide Weave extends the per-hop reach so the chain travels further.
	var chain_radius: float = LIGHTNING_CHAIN_RADIUS + reach_bonus
	var origin: Vector2 = owner_node.global_position
	var first_target: Node = null
	var best_dist: float = INF
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var d: float = enemy.global_position.distance_to(origin)
		if d < best_dist:
			best_dist = d
			first_target = enemy
	if first_target == null:
		return

	var chain_dmg: int = maxi(1, roundi(magic_attack * LIGHTNING_CHAIN_PCT))
	var visited: Dictionary = {first_target.get_instance_id(): true}
	var current: Node = first_target
	for hop in range(LIGHTNING_CHAIN_HOPS):
		var hc = current.get("health_component")
		if hc != null and is_instance_valid(hc) and not hc.is_dead:
			hc.take_damage(chain_dmg, owner_node, true, false, true)
		# Next hop
		var next_enemy: Node = null
		var best: float = chain_radius
		for e2 in owner_node.get_tree().get_nodes_in_group("Enemies"):
			if not is_instance_valid(e2) or visited.has(e2.get_instance_id()):
				continue
			var hc2 = e2.get("health_component")
			if hc2 == null or not is_instance_valid(hc2) or hc2.is_dead:
				continue
			var d: float = e2.global_position.distance_to(current.global_position)
			if d <= best:
				best = d
				next_enemy = e2
		if next_enemy == null:
			break
		visited[next_enemy.get_instance_id()] = true
		current = next_enemy
