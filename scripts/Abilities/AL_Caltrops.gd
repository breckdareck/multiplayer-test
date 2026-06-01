extends Node

## Caltrops — the Bow discipline's fire-and-forget ground-zone. Drops a patch
## of caltrops at the caster's feet for 5 seconds. Enemies inside take a small
## damage tick every second AND get briefly slowed each tick (so a fast-moving
## enemy can pass through but a stationary or pursuing one piles up the slow).
##
## Pure utility — momentum-neutral by design (no Momentum building or
## spending) so it functions as setup rather than a builder/spender. Pairs
## with kiting (Disengage → drop Caltrops → kite → enemies are slowed) and
## with the Hunt mark (slowed targets are easier to keep marked).
##
## Spawns via the shared `GroundZone.spawn_server` helper. The slow callback
## mirrors `StaffElementComponent._apply_slow` exactly — `movement_speed` is a
## plain EnemyBase field (read live by enemy_chase / enemy_patrol every
## physics frame), NOT a StatData, so we pin it directly and restore from a
## saved meta on a Timer. Re-application while already slowed is a no-op so
## repeat ticks don't compound or write back a wrong base on restore.

## Ground rectangle — caltrops literally scatter along the floor. Wide-x,
## short-y rect hugging the ground reads correctly (a scatter patch) where a
## circular zone would look like a sphere of spikes floating above the floor.
const ZONE_RECT_SIZE: Vector2 = Vector2(160.0, 50.0)
const ZONE_DURATION: float = 5.0
const ZONE_TICK_INTERVAL: float = 1.0
## Tick damage is 8% of WEAPONATTACK per second. maxi(1, ...) keeps it
## visible at low gear. Bow damages scale on WEAPONATTACK.
const TICK_DAMAGE_PCT: float = 0.08

const SLOW_PCT: float = 0.30
const SLOW_DURATION: float = 1.0
const SLOW_META: String = "caltrops_slow"

const ZONE_COLOR: Color = Color(0.55, 0.42, 0.18, 0.40)  # rusty brown


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)

	# PR 6 upgrade reads. bonus_damage_mult scales tick damage; bonus_zone_
	# duration adds seconds; bonus_zone_radius adds px to the rect width (x).
	var damage_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var width_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")

	var tick_damage: int = maxi(1, roundi(wpn_attack * TICK_DAMAGE_PCT * (1.0 + damage_bonus)))
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)

	# Spawn at the caster's feet — drop-the-trap-where-you-stand feel.
	# Ground-rect shape so the spikes scatter along the floor visibly.
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		owner_node.global_position,
		rect_size,
		duration,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
		Callable(self, "_apply_caltrops_slow")
	)


## Per-tick callback fired by the zone for each enemy currently inside.
## Mirrors StaffElementComponent._apply_slow's save/restore/meta/tint idiom.
func _apply_caltrops_slow(enemy: Node) -> void:
	if not (enemy is EnemyBase):
		return
	var e := enemy as EnemyBase
	# Already slowed by THIS effect — let the existing timer run out rather than
	# re-applying (which would re-save the already-reduced speed as "original"
	# and permanently slow them on restore).
	if e.has_meta(SLOW_META):
		return

	var original_speed: float = e.movement_speed
	e.movement_speed = original_speed * (1.0 - SLOW_PCT)
	e.set_meta(SLOW_META, original_speed)

	e.get_tree().create_timer(SLOW_DURATION).timeout.connect(
		func():
			if not is_instance_valid(e):
				return
			# Restore from the saved value rather than dividing back out — robust
			# against movement_speed having been reassigned elsewhere meanwhile.
			if e.has_meta(SLOW_META):
				e.movement_speed = e.get_meta(SLOW_META)
				e.remove_meta(SLOW_META)
	)
