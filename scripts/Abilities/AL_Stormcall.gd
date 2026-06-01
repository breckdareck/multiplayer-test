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

const ZONE_RADIUS: float = 100.0
const ZONE_DURATION: float = 3.0
const ZONE_TICK_INTERVAL: float = 0.5
const ZONE_SPAWN_OFFSET: float = 140.0  ## px ahead of caster in facing direction

## Tick damage = 11% of MAGICATTACK per tick. With 6 ticks across 3s that's
## ~66% sustained per enemy who stays the full duration — comparable to
## the Pyre Burst pool's ceiling but with a different cast profile.
const TICK_DAMAGE_PCT: float = 0.11

const ZONE_COLOR: Color = Color(0.55, 0.55, 1.0, 0.38)  ## lightning blue-purple


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)
	var tick_damage: int = maxi(1, roundi(magic_attack * TICK_DAMAGE_PCT))

	# Spawn the storm area ahead of the caster.
	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1
	var spawn_pos: Vector2 = owner_node.global_position + Vector2(ZONE_SPAWN_OFFSET * float(facing), 0)

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		spawn_pos,
		ZONE_RADIUS,
		ZONE_DURATION,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
	)
