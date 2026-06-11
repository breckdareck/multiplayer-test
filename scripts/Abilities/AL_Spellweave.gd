extends Node

## Spellweave (staff active) — CHANNEL + STANCE-AUGMENT. After a brief
## channel, releases an AMPLIFIED version of the current stance's
## signature effect at the caster's facing direction. The exact effect
## depends on the active StaffElement stance:
##   - FIRE      → a cone of flame ahead of the caster: direct burst to
##                 every enemy in reach + 2 Burn stacks each (2026-06-10
##                 roster-audit rework — was a third fire ground-pool on
##                 top of Pyre Burst's and Immolate's splash; the burst
##                 wave gives FIRE a shape the stance didn't have)
##   - ICE       → applies a hard freeze (1.5s) to all enemies in a small
##                 area ahead, larger radius than Glacial Spike's single hit
##   - LIGHTNING → fires a chain blast that hops further with more bonus
##                 damage than the stance rider's baseline
##
## Engages the stance gauge — Spellweave is meaningfully different per
## stance, so a Staff build commits to its current element and gets a
## tailored amplified payoff. Mismatch behavior: in NO stance (shouldn't
## happen — stance always defaults to FIRE), falls back to FIRE.

## Amplified Fire-stance wave — a cone of flame ahead of the caster. Direct
## burst (no pool): every enemy in reach takes FIRE_WAVE_DAMAGE_PCT of the
## scale base and gains 2 Burn stacks via the stance rider.
const FIRE_WAVE_RADIUS: float = 150.0
const FIRE_WAVE_OFFSET: float = 120.0
const FIRE_WAVE_DAMAGE_PCT: float = 0.6
const FIRE_WAVE_BURN_STACKS: int = 2
const FIRE_WAVE_MAX_TARGETS: int = 4

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
	# Scale releases off dot_scaling_base (max_range x damage%) so they track
	# attributes + mastery + gear instead of raw MAGICATTACK (which fell behind).
	var combat = owner_node.get("combat_component")
	var scale_base: int = int(combat.dot_scaling_base(ability)) if combat != null and is_instance_valid(combat) and combat.has_method("dot_scaling_base") else int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	# Upgrade reads: Doubled Weave (T3) fires the release twice; Echoing Weave
	# (T3) refunds MP if the release connects with an enemy; Wide Weave (T3)
	# widens the release reach in EVERY stance (Fire pool / Ice freeze /
	# Lightning chain) — stance-agnostic so it works whatever element you hold.
	var double_release: bool = false
	var mp_refund: float = 0.0
	var reach_bonus: float = 0.0
	var damage_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		double_release = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_double_release") > 0.0
		mp_refund = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_mp_refund")
		reach_bonus = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_zone_radius")
		# Heavy Weave (T2): +damage to the amplified release (fire pool / lightning chain).
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(ability.ability_id, "bonus_damage_mult")
	scale_base = int(scale_base * (1.0 + maxf(0.0, damage_bonus)))

	# Tap-or-hold charge: an early-released wind-up publishes its charge
	# fraction (attack state meta, 0.5..1.0); the release's own damage bases
	# don't route through calculate_ability_damage, so scale them here. Full
	# wind-ups never set the meta (fraction 1.0).
	if owner_node.has_meta("channel_charge"):
		scale_base = maxi(1, int(scale_base * float(owner_node.get_meta("channel_charge"))))

	_release(owner_node, element, facing, scale_base, reach_bonus)

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
					_release(owner_node, element, facing, scale_base, reach_bonus)
		)


## Dispatch the stance-appropriate amplified release. Factored out so Doubled
## Weave can re-fire it without re-entering execute (no re-cast / re-cost).
## `reach_bonus` (Wide Weave T3) widens whichever stance effect fires.
func _release(owner_node: Node, element: int, facing: int, scale_base: int, reach_bonus: float = 0.0) -> void:
	match element:
		0:  # FIRE — cone of flame: burst + burn stacks
			_fire_wave(owner_node, facing, scale_base, reach_bonus)
		1:  # ICE — area freeze
			_ice_freeze(owner_node, facing, reach_bonus)
		2:  # LIGHTNING — extended chain blast
			_lightning_chain(owner_node, scale_base, reach_bonus)
		_:
			_fire_wave(owner_node, facing, scale_base, reach_bonus)


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


func _fire_wave(owner_node: Node, facing: int, scale_base: int, reach_bonus: float = 0.0) -> void:
	# Cone of flame ahead of the caster: a direct burst to every enemy in
	# reach + FIRE_WAVE_BURN_STACKS burn stacks each via the stance rider
	# (so the burn's per-tick scales off this release, same as any fire hit).
	# Burst shape on purpose — the FIRE stance already owns two ground DoTs
	# (Pyre Burst's pool, Immolate's splash); the wave is the missing verb.
	var center: Vector2 = owner_node.global_position + Vector2(FIRE_WAVE_OFFSET * float(facing), 0)
	var wave_radius: float = FIRE_WAVE_RADIUS + reach_bonus
	var r2: float = wave_radius * wave_radius
	var burst: int = maxi(1, roundi(scale_base * FIRE_WAVE_DAMAGE_PCT))
	var staff = owner_node.get("staff_element_component")
	var struck: int = 0
	for enemy in owner_node.get_tree().get_nodes_in_group("Enemies"):
		if struck >= FIRE_WAVE_MAX_TARGETS:
			break
		if not is_instance_valid(enemy) or not (enemy is EnemyBase):
			continue
		if (enemy.global_position - center).length_squared() > r2:
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		struck += 1
		var was_alive: bool = not hc.is_dead
		hc.take_damage(burst, owner_node, true, false, true)
		if was_alive and hc.is_dead:
			var ability_comp = owner_node.get("ability_component")
			if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
				ability_comp.dispatch_passive_event_on_kill(enemy)
			continue
		if staff != null and is_instance_valid(staff) and staff.has_method("apply_element_on_hit"):
			for _i in range(FIRE_WAVE_BURN_STACKS):
				staff.apply_element_on_hit(owner_node, enemy, burst)

	# Wave "juice" — a short fire band flash across the cone's reach.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "fire_ground", center, wave_radius * 1.6, 0.8)


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


func _lightning_chain(owner_node: Node, scale_base: int, reach_bonus: float = 0.0) -> void:
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

	var chain_dmg: int = maxi(1, roundi(scale_base * LIGHTNING_CHAIN_PCT))
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
