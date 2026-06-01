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

	# PR 6 upgrade reads — Wider Crack (T1) adds rect width; Lingering
	# Tremors (T2) adds duration.
	var width_bonus: float = 0.0
	var duration_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		width_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")

	var tick_damage: int = maxi(1, roundi(wpn_attack * BASE_TICK_DAMAGE_PCT * combo_mult))
	var duration: float = ZONE_DURATION + duration_bonus
	var rect_size: Vector2 = ZONE_RECT_SIZE + Vector2(width_bonus, 0.0)

	# Spawn at the caster's feet — the slam epicenter. Ground-rect shape so
	# the tremor reads as floor-bound rather than as a sphere of damage
	# above the ground.
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		owner_node.global_position,
		rect_size,
		duration,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
	)
