extends Node

## Arcane Familiar (staff active) — SUMMON. Summons a mini arcane wisp at the
## caster's side for 12 seconds. The wisp auto-fires Arcane Bolt-style
## projectiles at nearby enemies on a fixed cadence.
##
## Staff analog to dagger's Shadow Partner (`AL_ShadowPartner.gd`). Adds the
## summon shape category to staff. Pairs with sustained channels
## (Stormcall + Familiar = a lot of incoming damage per second from one
## position) and with Mana Surge (familiar's bolts can consume / extend
## marks too).
##
## Implementation: a simple node spawned under the caster's map with a
## tick Timer that fires at INTERVAL. On each tick, find the nearest
## enemy within RANGE of the familiar and apply damage as if the caster
## had hit it. The familiar carries no AI / pathing — it just hovers
## at the caster's last known position and shoots from there.
##
## A full Arcane-Bolt-projectile spawn is deferred to v2 — for v1 the
## familiar applies instant-hit damage (no travel time) at FIRE_RATE.

const DURATION_SECONDS: float = 12.0
const FIRE_RATE: float = 0.8           ## seconds between bolts
const BOLT_RANGE: float = 280.0
## Bolt damage = 22% of MAGICATTACK per shot.
const BOLT_DAMAGE_PCT: float = 0.22


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return
	if not "player_id" in owner_node:
		return

	# Cache the caster's map so the familiar's tick stays scoped to the
	# same map as the caster. Bots / disconnects naturally clean up via the
	# duration timer + the networked_entities group sweep.
	var map_id: String = MapManager.get_player_map(owner_node.player_id)
	if map_id == "":
		return
	var map_inst = MapManager.active_maps[map_id].get("scene_instance")
	if not is_instance_valid(map_inst):
		return

	# Upgrade reads: Lasting (+duration), Quick (+fire rate), Twin (+familiar),
	# Chaining (bolts hit an extra nearby enemy).
	var duration: float = DURATION_SECONDS
	var fire_rate: float = FIRE_RATE
	var extra_count: int = 0
	var chain: int = 0
	var damage_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration += ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_summon_duration")
		var fr_bonus: float = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_fire_rate")
		fire_rate = FIRE_RATE / (1.0 + maxf(0.0, fr_bonus))
		extra_count = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_summon_count"))
		chain = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_chain_targets"))
		# Heavy Familiar (T3): +damage to the wisp's bolts.
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")

	# Cache the dot_scaling_base anchor (max_range x damage%) on each familiar so its
	# bolts scale with attributes + mastery + gear, not raw MAGICATTACK.
	var combat = owner_node.get("combat_component")
	var dot_base: int = int(combat.dot_scaling_base(_ability) * (1.0 + maxf(0.0, damage_bonus))) if combat != null and is_instance_valid(combat) and combat.has_method("dot_scaling_base") else 0

	for i in range(1 + extra_count):
		var offset := Vector2(40.0, -20.0) if i == 0 else Vector2(-40.0, -20.0 - 10.0 * i)
		_spawn_familiar(owner_node, map_inst, offset, duration, fire_rate, chain, dot_base)


## Spawn one familiar with the resolved duration / fire rate / chain count.
func _spawn_familiar(owner_node: Node, map_inst: Node, offset: Vector2, duration: float, fire_rate: float, chain: int, dot_base: int = 0) -> void:
	var familiar := Node2D.new()
	familiar.name = "ArcaneFamiliar"
	familiar.global_position = owner_node.global_position + offset
	familiar.add_to_group("networked_entities")
	familiar.set_meta("chain_targets", chain)
	familiar.set_meta("dot_base", dot_base)
	map_inst.add_child(familiar)

	var fire_timer := Timer.new()
	fire_timer.wait_time = maxf(0.1, fire_rate)
	fire_timer.autostart = true
	fire_timer.timeout.connect(_on_familiar_tick.bind(familiar, owner_node))
	familiar.add_child(fire_timer)

	# Self-destruct after the (possibly extended) duration.
	familiar.get_tree().create_timer(duration).timeout.connect(
		func():
			if is_instance_valid(familiar):
				familiar.queue_free()
	)


## Per-tick fire: find the nearest living enemy on the same map within
## BOLT_RANGE of the familiar's position; apply BOLT_DAMAGE_PCT × MAGICATTACK
## to it. Server-only — fires from inside a Timer connected on the server.
func _on_familiar_tick(familiar: Node2D, caster: Node) -> void:
	if not is_instance_valid(familiar) or not is_instance_valid(caster):
		return
	# Caster could have died / despawned mid-summon — let the familiar finish
	# its duration but use null as the damage source for kill credit (no
	# applier means no XP / on_kill, which is acceptable for an orphan
	# familiar).
	var stats = caster.get("stats_component") if is_instance_valid(caster) else null
	if stats == null or not stats.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats.stats[Constants.StatType.MAGICATTACK].total_value)
	var cached_base: int = int(familiar.get_meta("dot_base", 0))
	var scale_base: int = cached_base if cached_base > 0 else magic_attack
	var damage: int = maxi(1, roundi(scale_base * BOLT_DAMAGE_PCT))

	# Gather living enemies on the same map within range, nearest first. Chaining
	# Familiar (T3) lets each bolt strike 1 + chain_targets enemies.
	var familiar_pos: Vector2 = familiar.global_position
	var map_root: Node = familiar.get_parent()
	var candidates: Array = []
	for enemy in familiar.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		if map_root != null and not map_root.is_ancestor_of(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var d: float = enemy.global_position.distance_to(familiar_pos)
		if d <= BOLT_RANGE:
			candidates.append({"e": enemy, "d": d})
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a, b): return a.d < b.d)

	var hits: int = 1 + int(familiar.get_meta("chain_targets", 0))
	var applier = caster if is_instance_valid(caster) else null
	for i in range(mini(hits, candidates.size())):
		var hc2 = candidates[i].e.get("health_component")
		if hc2 != null and is_instance_valid(hc2):
			hc2.take_damage(damage, applier, true, false, true)
