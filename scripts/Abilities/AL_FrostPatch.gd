extends Node

## Frost Patch — the Staff discipline's Ice-flavored ground-zone. A persistent
## patch of frost at the caster's feet for 4 seconds. Enemies inside take a
## small magic-damage tick every second AND get briefly chilled (50% movement
## slow), so a pack walking through Frost Patch piles up the slow as long as
## they stay.
##
## Pairs with Glacial Spike's hard freeze (Frost Patch softens entry into a
## kite zone, then Glacial Spike locks the spotlight target in place). Also
## with Stormcall — the Lightning channel keeps enemies clustered while
## Frost Patch chills them. Distinct from the stance Ice rider's slow:
## - Stance rider: 40% slow for 2.5s, applied once on any staff hit
## - Frost Patch:  50% slow refreshed every tick, in the zone area
##
## Damage scales on MAGICATTACK (StatType 13) — mages don't use WEAPONATTACK.
## Slow callback mirrors `StaffElementComponent._apply_slow`.

## Ground rectangle — a frost patch hugs the floor where mages drop it,
## not a sphere of cold radiating above the ground.
const ZONE_RECT_SIZE: Vector2 = Vector2(180.0, 50.0)
const ZONE_DURATION: float = 4.0
const ZONE_TICK_INTERVAL: float = 1.0
## Tick damage = 8% of MAGICATTACK per second. Keeps the zone a sustain-
## chill, not a burst — players who burn Mana Surge or Spellweave for burst
## get more than they'd get from Frost Patch's ticks alone.
const TICK_DAMAGE_PCT: float = 0.08

const SLOW_PCT: float = 0.50
const SLOW_DURATION: float = 1.25  # slightly longer than tick interval so it overlaps
const SLOW_META: String = "frost_patch_chill"

const ZONE_COLOR: Color = Color(0.55, 0.80, 1.0, 0.40)  # icy blue


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats_comp.stats[Constants.StatType.MAGICATTACK].total_value)

	# PR 6 upgrade reads — Deep Frost (T2) adds damage; Wider Frost (T1)
	# adds rect width; Lingering Frost (T3) adds duration.
	var damage_bonus: float = 0.0
	var width_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		damage_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_mult")
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")

	var tick_damage: int = maxi(1, roundi(magic_attack * TICK_DAMAGE_PCT * (1.0 + damage_bonus)))
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		owner_node.global_position,
		rect_size,
		duration,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
		Callable(self, "_apply_chill")
	)


## Per-tick callback: applies / refreshes a movement-speed reduction on
## enemies in the patch. Same save/restore/meta idiom as the stance Ice
## rider but with its OWN meta key — Frost Patch's chill stacks
## independently of `staff_element_chill` rather than clobbering its saved
## base speed.
func _apply_chill(enemy: Node) -> void:
	if not (enemy is EnemyBase):
		return
	var e := enemy as EnemyBase
	# Already chilled by THIS effect — let the existing timer run out rather
	# than re-applying, which would re-save the (already-reduced) speed and
	# permanently slow them on restore. A subsequent tick that finds them
	# still in the zone after the timer expires will re-chill cleanly.
	if e.has_meta(SLOW_META):
		return

	var original_speed: float = e.movement_speed
	e.movement_speed = original_speed * (1.0 - SLOW_PCT)
	e.set_meta(SLOW_META, original_speed)

	e.get_tree().create_timer(SLOW_DURATION).timeout.connect(
		func():
			if not is_instance_valid(e):
				return
			if e.has_meta(SLOW_META):
				e.movement_speed = e.get_meta(SLOW_META)
				e.remove_meta(SLOW_META)
	)
