extends Node

## Smoke Bomb — the Dagger discipline's defensive ground-zone. Drops a smoke
## cloud at the caster's feet for 4 seconds. Allies inside become invisible
## to enemy AI (their `is_invisible` meta is set — the same meta Shadowmeld
## uses), so any enemy currently targeting them drops aggro.
##
## Adds the missing "ground-zone" and "defensive utility" shape categories
## to dagger's kit. Pairs with Shadowmeld (drop bomb → keep re-stealthing
## while the cloud hides you) and with Vendetta / Eviscerate (drag a marked
## target into the smoke, finish at leisure).
##
## Circular shape (vs the rectangular ground-floor zones used by other ground
## abilities) because smoke billows VOLUMETRICALLY — a sphere of cover reads
## correctly here where a flat rect would not (per
## [[feedback_ground_zones_are_floor_rectangles]]).
##
## Implementation: spawns a damage-less GroundZone whose ALLY tick callback
## refreshes `is_invisible = true` on each ally inside. A short-lived
## per-ally timer clears the meta after BLIND_DURATION; the next tick
## re-applies it if they're still in the zone. The clear path defers to
## the Shadowmeld component — if the ally is still actively stealthed via
## Shadowmeld, we leave is_invisible alone so we don't strip their cover.

const ZONE_RADIUS: float = 90.0
const ZONE_DURATION: float = 4.0
const ZONE_TICK_INTERVAL: float = 0.5  ## half-second tick — keeps the hidden meta fresh

const BLIND_DURATION: float = 0.75  ## slightly longer than tick interval so it overlaps
## Our own marker meta — distinct from `is_invisible` so the clear-on-timer
## path can identify whether WE set is_invisible (vs Shadowmeld doing it)
## and only clear in the former case.
const SMOKE_OWNS_INVISIBLE_META: String = "smoke_bomb_owns_invisible"

const ZONE_COLOR: Color = Color(0.25, 0.25, 0.30, 0.55)  # smoky grey


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	# Damage-less zone — pure utility. We pass NO enemy tick callback (the
	# enemy AI's existing aggro logic reads is_invisible on the player, so we
	# don't need to touch enemies directly) and an ALLY tick callback that
	# refreshes hidden-state on the caster and any party members inside.
	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		owner_node.global_position,
		ZONE_RADIUS,
		ZONE_DURATION,
		ZONE_TICK_INTERVAL,
		0,
		ZONE_COLOR,
		Callable(),  # no enemy callback
		Callable(self, "_apply_hidden")
	)


## Per-tick callback fired by the zone for each ALLY currently inside.
## Sets the same `is_invisible` meta Shadowmeld + EnemyBase already respect,
## so enemies targeting this ally drop aggro the next time their target
## search runs. Refreshed each tick to handle continuous occupancy.
func _apply_hidden(ally: Node) -> void:
	if not is_instance_valid(ally):
		return

	# Set both metas: is_invisible drives the actual AI behavior, and the
	# owns-invisible marker lets the clear-on-timer below identify that WE
	# set it (so we don't accidentally clear a parallel Shadowmeld stealth).
	ally.set_meta("is_invisible", true)
	ally.set_meta(SMOKE_OWNS_INVISIBLE_META, true)

	ally.get_tree().create_timer(BLIND_DURATION).timeout.connect(
		func():
			if not is_instance_valid(ally):
				return
			# Only clear if our marker is still set (a re-tick within the
			# BLIND_DURATION window may have already passed; in that case
			# THIS timer was the one that started it and the next one is
			# pending). Use the marker to determine ownership.
			if not ally.has_meta(SMOKE_OWNS_INVISIBLE_META):
				return
			ally.remove_meta(SMOKE_OWNS_INVISIBLE_META)
			# Coexistence guard — if Shadowmeld is actively stealthed on
			# this ally, leave is_invisible alone (Shadowmeld owns it).
			# Otherwise clear so enemies can re-acquire the ally after
			# they leave the smoke.
			var sm = ally.get("shadowmeld_component")
			var still_stealthed: bool = false
			if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
				still_stealthed = sm.is_stealthed()
			if not still_stealthed:
				ally.set_meta("is_invisible", false)
	)
