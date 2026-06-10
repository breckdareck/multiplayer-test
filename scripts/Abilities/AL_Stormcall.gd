extends Node

## Stormcall (staff active) — CHANNEL + GROUND-ZONE (Lightning-themed).
## Channels a sustained storm in a target area; random lightning strikes
## any enemy currently inside every 0.5 seconds for the channel duration.
## Damage scales on MAGICATTACK. Pairs naturally with Lightning stance
## (the stance chain rider triggers on each strike for crowd burst).
##
## Distinct from the Pyre Burst Fire-stance pool and from Frost Patch:
##   - Pyre Burst pool: post-cast aftermath, no channel
##   - Frost Patch: utility chill, low-damage zone
##   - Stormcall: sustained heavy-damage channel, the staff's biggest
##     AoE-DoT output
##
## Uses the shared GroundZone helper. The "channel" feel comes from the
## ability's cast_time keeping the player rooted while the zone runs.
## Tick rate is fast (0.5s) so each enemy gets ~6 ticks across the channel.

## Ground rectangle — lightning STRIKES the floor and the ground around the
## impact arcs; the shape that reads correctly is a wide strip of ground, not
## a sphere of storm above it.
const ZONE_RECT_SIZE: Vector2 = Vector2(220.0, 60.0)
const ZONE_DURATION: float = 3.0
const ZONE_TICK_INTERVAL: float = 0.5
const ZONE_SPAWN_OFFSET: float = 140.0  ## px ahead of caster in facing direction

## Tick damage = 11% of MAGICATTACK per tick. With 6 ticks across 3s that's
## ~66% sustained per enemy who stays the full duration — comparable to
## the Pyre Burst pool's ceiling but with a different cast profile.
const TICK_DAMAGE_PCT: float = 0.14

const ZONE_COLOR: Color = Color(0.55, 0.55, 1.0, 0.38)  ## lightning blue-purple
## Chaining Storm (T3): each strike arcs to nearby enemies within this radius.
const CHAIN_RADIUS: float = 160.0

# Per-cast chain state (Chaining Storm T3), read by the per-tick callback. The
# zone holds this AL instance alive via the bound Callable.
var _chain_targets: int = 0
var _chain_damage: int = 0


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	# PR 6 upgrade reads — Heavy Storm (T2) adds damage; Wide Storm (T3)
	# adds rect width; Sustained Storm (T1) adds channel duration.
	var damage_bonus: float = 0.0
	var width_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var tick_rate_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "channel_time_extension")
		_chain_targets = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_chain_targets"))
		tick_rate_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_tick_rate")

	# Scale ticks off dot_scaling_base (max_range x damage%) so the storm tracks
	# attributes + mastery + gear instead of raw MAGICATTACK (which fell behind at
	# endgame). Same anchor the bleeds/Caltrops use. _chain_damage inherits this.
	var combat = owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and is_instance_valid(combat) and combat.has_method("dot_scaling_base") else maxi(1, magic_attack)
	var tick_damage: int = maxi(1, roundi(dot_base * TICK_DAMAGE_PCT * (1.0 + damage_bonus)))
	# Rapid Storm (T3): the storm strikes more often (shorter interval) with
	# lighter per-strike hits — a snappier, modestly higher sustained DPS that
	# catches transient enemies, distinct from Wide (area) / Chaining (spread).
	var tick_interval: float = ZONE_TICK_INTERVAL
	if tick_rate_bonus > 0.0:
		tick_interval = maxf(0.15, ZONE_TICK_INTERVAL * (1.0 - tick_rate_bonus))
		tick_damage = maxi(1, roundi(tick_damage * 0.7))
	_chain_damage = tick_damage
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)

	# Spawn the storm area ahead of the caster.
	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1
	var spawn_pos: Vector2 = owner_node.global_position + Vector2(ZONE_SPAWN_OFFSET * float(facing), 0)

	# Chaining Storm (T3) adds a per-enemy callback that arcs to nearby enemies.
	var chain_cb := Callable(self, "_chain_strike").bind(owner_node) if _chain_targets > 0 else Callable()

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		spawn_pos,
		rect_size,
		duration,
		tick_interval,
		tick_damage,
		ZONE_COLOR,
		chain_cb,
	)

	# Ground "juice" — a tiled crackling-lightning strip across the storm area.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "lightning_ground", spawn_pos, rect_size.x, duration)


## Per-tick callback for each enemy struck inside the storm: arc to the nearest
## OTHER living enemies within CHAIN_RADIUS, dealing the same tick damage.
func _chain_strike(struck: Node, owner_node: Node) -> void:
	if _chain_targets <= 0 or not is_instance_valid(struck):
		return
	var origin: Vector2 = struck.global_position
	var candidates: Array = []
	for e in struck.get_tree().get_nodes_in_group("Enemies"):
		if e == struck or not (e is EnemyBase) or not is_instance_valid(e):
			continue
		var hc = e.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var d: float = origin.distance_to(e.global_position)
		if d <= CHAIN_RADIUS:
			candidates.append({"e": e, "d": d})
	candidates.sort_custom(func(a, b): return a.d < b.d)
	var applier = owner_node if is_instance_valid(owner_node) else null
	for i in range(mini(_chain_targets, candidates.size())):
		var hc2 = candidates[i].e.get("health_component")
		if hc2 != null and is_instance_valid(hc2):
			hc2.take_damage(_chain_damage, applier, true, false, true)
