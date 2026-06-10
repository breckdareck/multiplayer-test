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
## Zone tick = this fraction of the ability's MAX hit (max_range × dmg%), via
## CombatComponent.dot_scaling_base — so the field scales with attributes +
## mastery + ability level + gear like direct damage (project_dot_scaling_divergence).
## Was 0.08 × raw WEAPONATTACK, which omitted the (primary×4+sec) multiplier.
const TICK_DAMAGE_FRAC: float = 0.08

const SLOW_PCT: float = 0.30
const SLOW_DURATION: float = 1.0
const SLOW_META: String = "caltrops_slow"

## Poisoned Spikes (T3) bleed — fraction of the ability's MAX hit per tick per
## stack (via dot_scaling_base), stacking up to MAX while inside the field.
const POISON_TICK_FRAC: float = 0.05
const POISON_MAX_STACKS: int = 5
const POISON_DURATION: float = 3.0
const POISON_META: String = "caltrops_poison"

const ZONE_COLOR: Color = Color(0.55, 0.42, 0.18, 0.40)  # rusty brown

# Per-cast upgrade state, read in execute() (where _ability + stats resolve) and
# consumed by the per-tick slow/poison callback (which only receives the enemy).
# The zone holds this AL instance alive via the bound Callable, so members persist
# for the zone's lifetime.
var _slow_pct: float = SLOW_PCT
var _poison_per_tick: int = 0  # 0 = Poisoned Spikes not owned this cast
var _poison_applier: Node = null


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
	var slow_bonus: float = 0.0
	var bleed_applies: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		# Piercing Spikes (T3) deepens the slow; Poisoned Spikes (T3) adds a bleed.
		slow_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_slow_pct")
		bleed_applies = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_bleed_applies")

	var combat = owner_node.get("combat_component")
	var dot_base: int = combat.dot_scaling_base(_ability) if combat != null and combat.has_method("dot_scaling_base") else maxi(1, wpn_attack)

	_slow_pct = clampf(SLOW_PCT + slow_bonus, 0.0, 0.95)
	if bleed_applies > 0.0:
		_poison_per_tick = maxi(1, roundi(dot_base * POISON_TICK_FRAC))
		_poison_applier = owner_node
	else:
		_poison_per_tick = 0
		_poison_applier = null

	var tick_damage: int = maxi(1, roundi(dot_base * TICK_DAMAGE_FRAC * (1.0 + damage_bonus)))
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

	# Ground "juice" — a tiled spike strip scattered across the caltrops patch.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "earth_ground", owner_node.global_position, rect_size.x, duration)


## Per-tick callback fired by the zone for each enemy currently inside.
## Mirrors StaffElementComponent._apply_slow's save/restore/meta/tint idiom.
func _apply_caltrops_slow(enemy: Node) -> void:
	if not (enemy is EnemyBase):
		return
	var e := enemy as EnemyBase

	# Poisoned Spikes (T3): stack a bleed each tick the enemy is inside the field.
	if _poison_per_tick > 0:
		BleedDot.apply(e, _poison_applier, _poison_per_tick, POISON_MAX_STACKS, POISON_DURATION, POISON_META, "poison")

	# Already slowed by THIS effect — let the existing timer run out rather than
	# re-applying (which would re-save the already-reduced speed as "original"
	# and permanently slow them on restore).
	if e.has_meta(SLOW_META):
		return

	var original_speed: float = e.movement_speed
	e.movement_speed = original_speed * (1.0 - _slow_pct)
	e.set_meta(SLOW_META, original_speed)
	EnemyStatus.register(e, EnemyStatus.TAG_CHILL, SLOW_META, null)

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
