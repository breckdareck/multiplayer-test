extends Node

## Earthsplitter — the Sword discipline's combo-spender ground-zone. A heavy
## ground slam at the caster's feet that consumes ALL combo points to create
## a tremor zone for 4 seconds. The zone ticks damage every second on any
## enemy currently inside; tick damage scales with the number of combo
## points consumed (0 combo = baseline tick, 3 combo = +200% per-tick).
##
## Third spender option after Crescent Cleave (AoE burst, +100%/point) and
## Sundering Blow (single-target burst, +200%/point):
##   - Crescent Cleave: burst AoE on impact, gone in one frame
##   - Sundering Blow:  burst single-target, gone in one frame
##   - Earthsplitter:   sustained AoE zone, damage spread over 4 seconds
##
## Pairs with kiting (cast Earthsplitter, retreat behind it, drag enemies
## through it) and with Banner of the Vanguard (defensive aura over the
## offensive zone for a frontline stand).
##
## Uses the shared `GroundZone.spawn_server` helper. Combo is consumed via
## the SwordComboComponent's existing spend API to keep accounting consistent
## with Crescent Cleave / Sundering Blow.

## Ground rectangle (wide x, short y) — the tremor hugs the floor and hits
## enemies standing on it without rising above their hitboxes. v1 redesign:
## the original circle visualized as a sphere of damage above the floor,
## which read wrong for an earth-tremor; rectangle hugs the ground.
const ZONE_RECT_SIZE: Vector2 = Vector2(220.0, 60.0)
const ZONE_DURATION: float = 4.0
const ZONE_TICK_INTERVAL: float = 1.0

## Base tick damage = 15% of WEAPONATTACK. Combo amplification piles on top:
## +75% per combo point spent (so 3 combo = +225% = ~5x base tick). Mirrors
## Crescent Cleave's +100%/point but lower per-point because it ticks 4
## times. Net at 3-combo: 4 ticks × (1 + 2.25) × 15% = 195% of WEAPONATTACK
## over 4s — between Crescent Cleave (burst 300%) and Sundering Blow (burst
## 600% but ST only).
const BASE_TICK_DAMAGE_PCT: float = 0.15
const COMBO_AMP_PER_POINT: float = 0.75

const ZONE_COLOR: Color = Color(0.55, 0.30, 0.18, 0.42)  # earth-brown


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	var stats_comp = owner_node.get("stats_component")
	if stats_comp == null or not stats_comp.stats.has(Constants.StatType.WEAPONATTACK):
		return
	var wpn_attack: int = int(stats_comp.stats[Constants.StatType.WEAPONATTACK].total_value)

	# Consume combo via the SwordComboComponent's existing spend API. Same path
	# Crescent Cleave / Sundering Blow take so combo accounting stays canonical.
	# `spend_combo()` returns the count it actually consumed.
	var combo_consumed: int = 0
	var combo_comp = owner_node.get("sword_combo_component")
	if combo_comp != null and is_instance_valid(combo_comp) and combo_comp.has_method("spend_combo"):
		combo_consumed = int(combo_comp.spend_combo())

	# Combo amplification — multiplicative on the base tick.
	var combo_mult: float = 1.0 + (float(combo_consumed) * COMBO_AMP_PER_POINT)

	# Fold the same amplification into the INITIAL IMPACT hit (the ability's
	# active_behavior hitbox, scaled by damage_percent). combat resets this in
	# end_ability_attack so it never bleeds into the next cast. Mirrors how
	# Crescent Cleave / Sundering Blow scale their burst.
	var combat = owner_node.get("combat_component")
	if combat and is_instance_valid(combat):
		combat.pending_ability_damage_multiplier = combo_mult

	# PR 6 upgrade reads — Wider Crack (T1) adds rect width; Lingering Tremors
	# (T2) adds duration. T3 variants (mutually exclusive): Fissure Network
	# (split into two zones), Aftershock (delayed bonus pulse), Cataclysm
	# (collapse the zone into one big burst).
	var width_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var zone_split: float = 0.0
	var aftershock: float = 0.0
	var burst: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")
		zone_split = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_split")
		aftershock = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_aftershock_mult")
		burst = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_burst_mult")

	var tick_damage: int = maxi(1, roundi(wpn_attack * BASE_TICK_DAMAGE_PCT * combo_mult))
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)
	var gz = load("res://scripts/Gameplay/ground_zone.gd")
	var origin: Vector2 = owner_node.global_position

	# Ground "juice" — a tiled earth-spike strip filling the tremor zone on
	# every peer, living for the zone's duration. Fired at the slam epicenter
	# regardless of which T3 branch runs below (all slam at `origin`).
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "earth_ground", origin, rect_size.x, duration)

	# Cataclysm (T3): collapse the whole zone duration into one big impact —
	# a single short-lived, high-damage tick instead of a sustained zone.
	if burst > 0.0:
		var ticks: int = maxi(1, int(round(duration / ZONE_TICK_INTERVAL)))
		var burst_damage: int = maxi(1, roundi(float(tick_damage) * float(ticks) * (1.0 + burst)))
		gz.spawn_server_rect(owner_node, origin, rect_size, ZONE_TICK_INTERVAL + 0.15,
			ZONE_TICK_INTERVAL, burst_damage, ZONE_COLOR)
		return

	# Fissure Network (T3): split into two narrower zones, one ahead and one
	# behind the caster, instead of a single zone at the feet.
	if zone_split > 0.0:
		var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
		if facing == 0:
			facing = 1
		var split_size: Vector2 = Vector2(rect_size.x * 0.6, rect_size.y)
		var offset: float = rect_size.x * 0.3
		gz.spawn_server_rect(owner_node, origin + Vector2(offset * facing, 0), split_size,
			duration, ZONE_TICK_INTERVAL, tick_damage, ZONE_COLOR)
		gz.spawn_server_rect(owner_node, origin - Vector2(offset * facing, 0), split_size,
			duration, ZONE_TICK_INTERVAL, tick_damage, ZONE_COLOR)
		return

	# Spawn at the caster's feet — the slam epicenter. Ground-rect shape so
	# the tremor reads as floor-bound rather than as a sphere of damage
	# above the ground.
	gz.spawn_server_rect(
		owner_node,
		origin,
		rect_size,
		duration,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
	)

	# Aftershock (T3): a delayed bonus pulse 1.5s after the slam — a second
	# short-lived high-damage zone at the epicenter.
	if aftershock > 0.0:
		var after_damage: int = maxi(1, roundi(float(tick_damage) * (1.0 + aftershock)))
		owner_node.get_tree().create_timer(1.5).timeout.connect(
			func():
				if is_instance_valid(owner_node):
					gz.spawn_server_rect(owner_node, origin, rect_size,
						ZONE_TICK_INTERVAL + 0.15, ZONE_TICK_INTERVAL, after_damage, ZONE_COLOR)
		)
