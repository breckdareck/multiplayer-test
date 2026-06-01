extends Node

## Smoke Bomb — the Dagger discipline's defensive ground-zone. Drops a smoke
## cloud at the caster's feet for 4 seconds. Enemies inside have their
## targeting on the caster briefly disrupted (lose aggro), and the cloud
## itself does NO damage — pure utility / disengage.
##
## Adds the missing "ground-zone" and "defensive utility" shape categories to
## dagger's kit. Pairs with Shadowmeld (drop the bomb → re-enter stealth
## while the enemy can't see you) and with Vendetta / Eviscerate (drag a
## marked target into the smoke, finish at leisure).
##
## Implementation: spawn a damage-less GroundZone whose per-tick callback
## marks each overlapping enemy with `smoke_bomb_blind` for a moment. The
## enemy AI's targeting code can read this meta to drop the player from its
## hostile list. v1 keeps the effect simple — a 1-second visibility break
## per tick — so the EnemyBase wiring is a single meta check rather than a
## full perception-system refactor.

const ZONE_RADIUS: float = 90.0
const ZONE_DURATION: float = 4.0
const ZONE_TICK_INTERVAL: float = 0.5  # half-second tick — keeps the blind fresh

const BLIND_DURATION: float = 0.75  # slightly longer than tick interval so it overlaps
const BLIND_META: String = "smoke_bomb_blind"

const ZONE_COLOR: Color = Color(0.25, 0.25, 0.30, 0.55)  # smoky grey


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	# Damage-less zone — pure utility. The callback handles the blind effect.
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		owner_node.global_position,
		ZONE_RADIUS,
		ZONE_DURATION,
		ZONE_TICK_INTERVAL,
		0,  # no direct damage — smoke is utility
		ZONE_COLOR,
		Callable(self, "_apply_blind")
	)


## Per-tick callback fired by the zone for each enemy currently inside.
## Tags the enemy with a short-lived "blind" meta. Enemy AI targeting code
## can check `enemy.has_meta(BLIND_META)` and drop the player from its
## aggro list while it's set.
func _apply_blind(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	# Refresh on every tick so a continually-blinded enemy keeps the tag fresh.
	enemy.set_meta(BLIND_META, true)
	enemy.get_tree().create_timer(BLIND_DURATION).timeout.connect(
		func():
			if not is_instance_valid(enemy):
				return
			if enemy.has_meta(BLIND_META):
				enemy.remove_meta(BLIND_META)
	)
