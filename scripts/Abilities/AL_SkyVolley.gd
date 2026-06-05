extends Node

## Sky Volley (bow active) — CHANNEL + GROUND-ZONE. Channels a sustained
## arrow rain over a target area (spawned at the caster's facing direction
## a short distance ahead). Damage ticks every 0.5s on enemies inside for
## the channel duration. Builds Momentum per second held (capped) so it
## doubles as a long-range builder.
##
## Distinct from Skyfall (instant AoE burst) and Hailstorm (instant
## multi-shot): Sky Volley is sustained pressure over time. Pairs with
## Mark of the Hunt (mark the volley target, the area pressure keeps it
## locked + the next Snipe gets auto-crit).
##
## Implementation: cast spawns a GroundZone with a short tick interval
## (0.5s) and 3-second duration. Per-tick callback builds 1 Momentum
## per enemy hit (capped at +1/sec via the second-counter meta). The
## "channel" feel comes from the ability's cast_time keeping the player
## animation-locked while the zone runs.

## Ground rectangle — arrows rain DOWN onto the floor, so the strike area is
## a strip of ground, not a sphere of arrows in midair.
const ZONE_RECT_SIZE: Vector2 = Vector2(240.0, 60.0)
const ZONE_DURATION: float = 3.0
const ZONE_TICK_INTERVAL: float = 0.5
const ZONE_SPAWN_OFFSET: float = 130.0  ## px ahead of caster in facing direction

## Tick damage = 9% of WEAPONATTACK per tick (× ~6 ticks over 3s = ~54%
## sustained per enemy who stays in). Keeps Sky Volley competitive with
## Hailstorm without overshadowing Snipe's burst.
const TICK_DAMAGE_PCT: float = 0.09

## Momentum gain per tick — capped at +1 per second so a tick-rate of 0.5s
## doesn't accidentally double the build rate.
const MOMENTUM_PER_TICK: int = 1
const MOMENTUM_TICK_META: String = "sky_volley_last_momentum_ms"

const ZONE_COLOR: Color = Color(0.85, 0.78, 0.55, 0.42)  ## sandy gold

## Marking Volley (T3) — whether this cast tags enemies inside with Hunter's
## Mark. Set per cast in execute(); read by the per-tick callback (the zone keeps
## this AL instance alive via the bound Callable).
var _applies_mark: bool = false


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)

	# PR 6 upgrade reads — Heavy Volley (T2) adds damage; Wide Volley (T3)
	# adds rect width; Sustained Volley (T1) adds duration.
	var damage_bonus: float = 0.0
	var width_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var tick_rate_bonus: float = 0.0
	_applies_mark = false
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "channel_time_extension")
		# Rapid Volley (T3) shortens the tick interval; Marking Volley (T3) tags
		# enemies inside with Hunter's Mark.
		tick_rate_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_tick_rate")
		_applies_mark = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_marks_applied") > 0.0

	var tick_damage: int = maxi(1, roundi(wpn_attack * TICK_DAMAGE_PCT * (1.0 + damage_bonus)))
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)
	var tick_interval: float = ZONE_TICK_INTERVAL * clampf(1.0 - tick_rate_bonus, 0.1, 1.0)

	# Spawn the rain area ahead of the caster in their facing direction.
	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1
	var spawn_pos: Vector2 = owner_node.global_position + Vector2(ZONE_SPAWN_OFFSET * float(facing), 0)

	# Reset the momentum-rate-limit meta for this cast.
	owner_node.set_meta(MOMENTUM_TICK_META, 0)

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		spawn_pos,
		rect_size,
		duration,
		tick_interval,
		tick_damage,
		ZONE_COLOR,
		Callable(self, "_build_momentum").bind(owner_node),
	)

	# Ground "juice" — a tiled dust/impact strip kicked up where arrows rain down.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "dust_ground", spawn_pos, rect_size.x, duration)


## Per-tick callback — builds Momentum on the caster, rate-limited to once
## per second even when the tick interval is faster. The `enemy` arg is
## received but unused; we only care that SOMETHING was hit (so the cast
## is connecting), then we build on the caster.
func _build_momentum(owner_node: Node, _enemy: Node) -> void:
	if not is_instance_valid(owner_node):
		return

	# Marking Volley (T3): tag each enemy hit with a short Hunter's Mark so the
	# next momentum-spender (Snipe / Sundering Arrow) auto-crits it.
	if _applies_mark and is_instance_valid(_enemy) and _enemy is EnemyBase:
		# Matches AL_MarkOfTheHunt.MARK_META / MARK_DURATION (8s).
		var expire_at_ms: int = Time.get_ticks_msec() + 8000
		_enemy.set_meta("hunters_mark_remaining", expire_at_ms)

	# Rate limit: at most 1 momentum build per second of held channel.
	var now: int = Time.get_ticks_msec()
	var last: int = int(owner_node.get_meta(MOMENTUM_TICK_META, 0))
	if now - last < 1000:
		return
	owner_node.set_meta(MOMENTUM_TICK_META, now)

	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("add_momentum"):
		return
	bm.add_momentum(MOMENTUM_PER_TICK)
