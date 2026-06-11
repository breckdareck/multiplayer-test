extends Node

## Hailstorm (bow active) — RAIN-OF-ARROWS STRIP. A storm of arrows hammers a
## ground strip ahead of the archer: multi-hit damage to up to max_targets
## enemies inside the hitbox, visualized by the tiled "arrow_ground" ground
## VFX raining across the strike area.
##
## 2026-06-10 rework: was is_projectile (one slow projectile per enemy already
## inside the box) — arrows were barely visible and the per-impact damage path
## made the Momentum build unreliable. Now a plain hitbox multi-hit: damage
## resolves through the standard _execute_hit path (which builds +2 Momentum
## per struck target for Hailstorm — see combat.gd's momentum block) and the
## volley reads as a volley via the ground FX.
##
## on_hit delegates to the shared weaken hook so Suppressing Fire (T3,
## "bonus_weaken_on_hit") keeps working — this AL replaced AL_WeakenOnHit in
## the logic_script slot.

## Matches A_Hailstorm's hitbox: 160x46 rect centered 80px ahead.
const STRIP_FORWARD_OFFSET: float = 80.0
const STRIP_WIDTH: float = 160.0
## Short flash — the volley lands inside the 0.4s cast window.
const VFX_DURATION: float = 0.8

const _WEAKEN_HOOK := preload("res://scripts/Abilities/AL_WeakenOnHit.gd")


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return
	var facing: int = int(owner_node.facing_direction) if "facing_direction" in owner_node else 1
	if facing == 0:
		facing = 1
	# Volley "juice" — tiled arrows raining across the strike strip.
	var center: Vector2 = owner_node.global_position + Vector2(STRIP_FORWARD_OFFSET * float(facing), 0)
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "arrow_ground", center, STRIP_WIDTH, VFX_DURATION)


func on_hit(owner_node: Node, target: Node, ability: AbilityData) -> void:
	# Suppressing Fire (T3): struck enemies deal less damage. The shared hook
	# no-ops unless the upgrade is owned.
	_WEAKEN_HOOK.new().on_hit(owner_node, target, ability)
