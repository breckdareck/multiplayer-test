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
	var tick_damage: int = maxi(1, roundi(wpn_attack * BASE_TICK_DAMAGE_PCT * combo_mult))

	# Spawn at the caster's feet — the slam epicenter. Ground-rect shape so
	# the tremor reads as floor-bound rather than as a sphere of damage
	# above the ground.
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server_rect(
		owner_node,
		owner_node.global_position,
		ZONE_RECT_SIZE,
		ZONE_DURATION,
		ZONE_TICK_INTERVAL,
		tick_damage,
		ZONE_COLOR,
	)
