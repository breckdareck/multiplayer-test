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

## How long after the LAST refresh tick is_invisible stays set before the
## clear-timer is allowed to drop it. Must be > ZONE_TICK_INTERVAL so
## consecutive ticks always overlap (no flicker while continuously inside);
## the buffer past tick_interval determines how long after the player walks
## OUT of the cloud the cover persists. 1.0s = 0.5s linger after leaving.
const HIDDEN_LINGER_SEC: float = 1.0

## Our marker meta — distinct from `is_invisible` so the clear path can
## identify whether WE set is_invisible (vs Shadowmeld doing it) and only
## clear in that case.
const SMOKE_OWNS_INVISIBLE_META: String = "smoke_bomb_owns_invisible"
## Absolute server-clock timestamp (ms) of "when is_invisible should expire
## if no further tick refreshes it." Each tick updates this; the clear
## timers only fire if the meta has not been refreshed since they were
## scheduled (their fire time >= the stored timestamp).
const SMOKE_EXPIRE_AT_META: String = "smoke_bomb_expire_at_ms"

## T3 upgrade metas:
##   - smoke_choke_*: on enemies inside the cloud. health.gd checks both and
##     scales incoming-from-this-enemy damage down by smoke_choke_pct while
##     the expiry is in the future. Refreshed every enemy tick + lingers 2s
##     after the enemy leaves so Choking Smoke's "for 2s after leaving"
##     promise holds.
##   - smoke_exit_crit_until_ms: on the ally who left the cloud. combat.gd
##     forces is_crit on the FIRST player attack while the timestamp is in
##     the future, then clears the meta (one-shot, mirrors MarkOfTheHunt
##     consume_mark).
const SMOKE_CHOKE_EXPIRE_META: String = "smoke_choke_expire_at_ms"
const SMOKE_CHOKE_PCT_META: String = "smoke_choke_pct"
const SMOKE_CHOKE_LINGER_SEC: float = 2.0  ## "for 2s after leaving" per description
const SMOKE_EXIT_CRIT_UNTIL_META: String = "smoke_exit_crit_until_ms"

## Per-cast config populated by execute() from PR 6 upgrade reads. The
## logic_script instance is constructed via `.new()` once per cast and held
## alive by the Callable references inside the GroundZone, so these instance
## vars persist for the cast's lifetime.
var _enemy_debuff_pct: float = 0.0
var _ally_heal_per_tick: int = 0
var _exit_crit_window_sec: float = 0.0

const ZONE_COLOR: Color = Color(0.25, 0.25, 0.30, 0.55)  # smoky grey


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	# Upgrade reads: each PR 6 upgrade tree the AbilityComponent owns can add
	# magnitude to a known effect_key on this ability. Smoke Bomb supports:
	#   bonus_zone_duration            → +seconds to ZONE_DURATION (Lasting Smoke T1)
	#   bonus_zone_radius              → +pixels to ZONE_RADIUS    (Wider Smoke T2)
	#   bonus_enemy_damage_debuff      → enemies in cloud deal LESS damage  (Choking Smoke T3)
	#   bonus_ally_heal_per_tick       → allies in cloud regen HP each tick (Restorative Smoke T3)
	#   bonus_exit_crit_window_sec     → guaranteed crit on next attack after leaving (Shadow Smoke T3)
	# Reads default to 0.0 when no matching upgrade is owned, so the base
	# numbers above are the floor — upgrades only ever ADD.
	var duration_bonus: float = 0.0
	var radius_bonus: float = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")
		radius_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		# Store T3 magnitudes on this instance — the GroundZone holds Callables
		# pointing at this instance for its tick callbacks, so the script
		# stays alive for the cast's duration and these values stay readable.
		_enemy_debuff_pct = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_enemy_damage_debuff")
		_ally_heal_per_tick = int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_ally_heal_per_tick"))
		_exit_crit_window_sec = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_exit_crit_window_sec")

	var duration: float = ZONE_DURATION + duration_bonus
	var radius: float = ZONE_RADIUS + radius_bonus

	# Enemy callback only registered when Choking Smoke is owned — saves the
	# per-tick Enemies-group iteration on a base Smoke Bomb where no debuff
	# would be applied.
	var enemy_cb: Callable = Callable()
	if _enemy_debuff_pct > 0.0:
		enemy_cb = Callable(self, "_apply_enemy_choke")

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		owner_node.global_position,
		radius,
		duration,
		ZONE_TICK_INTERVAL,
		0,
		ZONE_COLOR,
		enemy_cb,
		Callable(self, "_apply_hidden")
	)


## Per-tick callback fired by the zone for each ALLY currently inside.
## Sets the same `is_invisible` meta Shadowmeld + EnemyBase already respect,
## so enemies targeting this ally drop aggro the next time their target
## search runs.
##
## ANTI-FLICKER: each tick fires while the ally is inside the cloud, and
## every tick schedules a NEW clear-timer for HIDDEN_LINGER_SEC later. If
## these timers were unconditional clearers, the first one to fire would
## strip is_invisible even though later ticks have refreshed it — producing
## a continuous on/off flicker every ~0.25s. The fix: store an absolute
## expire_at_ms timestamp on the ally; each tick pushes it forward. Each
## clear-timer's body checks whether the timestamp is still in the future
## (still being refreshed by ongoing ticks) before clearing. Only the timer
## that fires AFTER the last refresh actually drops is_invisible.
func _apply_hidden(ally: Node) -> void:
	if not is_instance_valid(ally):
		return

	# Refresh: bump the expire timestamp forward to "now + linger". Set
	# is_invisible and our owner marker. is_invisible may already be true
	# (continuously inside the cloud, or a parallel Shadowmeld setter);
	# either way setting it to true is idempotent.
	ally.set_meta("is_invisible", true)
	ally.set_meta(SMOKE_OWNS_INVISIBLE_META, true)
	var expire_at: int = Time.get_ticks_msec() + int(HIDDEN_LINGER_SEC * 1000.0)
	ally.set_meta(SMOKE_EXPIRE_AT_META, expire_at)

	# Restorative Smoke (T3) — per-tick heal while inside. Direct HealthComponent
	# heal; safe to call every tick because heal clamps at max_health.
	if _ally_heal_per_tick > 0:
		var hc = ally.get("health_component")
		if hc != null and is_instance_valid(hc) and not hc.is_dead:
			if hc.has_method("heal_damage"):
				hc.heal_damage(_ally_heal_per_tick)
			elif "current_health" in hc and "max_health" in hc:
				hc.current_health = mini(int(hc.max_health), int(hc.current_health) + _ally_heal_per_tick)

	# Schedule a clear-attempt timer for HIDDEN_LINGER_SEC. The timer's body
	# is guarded — only fires the clear when no subsequent tick has bumped
	# the timestamp past it. Multiple overlapping timers (one per tick) all
	# read the same shared expire timestamp; only the one whose fire time
	# is at-or-past the latest timestamp actually drops is_invisible.
	ally.get_tree().create_timer(HIDDEN_LINGER_SEC).timeout.connect(
		func():
			if not is_instance_valid(ally):
				return
			if not ally.has_meta(SMOKE_EXPIRE_AT_META):
				return  # another clear already ran
			var stored_expire: int = int(ally.get_meta(SMOKE_EXPIRE_AT_META))
			# If a later tick has pushed the timestamp into the future, a
			# fresher timer will handle the eventual clear — skip.
			if Time.get_ticks_msec() < stored_expire:
				return
			# No refresh has happened in HIDDEN_LINGER_SEC. Safe to clear.
			ally.remove_meta(SMOKE_EXPIRE_AT_META)
			ally.remove_meta(SMOKE_OWNS_INVISIBLE_META)
			# Coexistence guard — if Shadowmeld is actively stealthed on
			# this ally, leave is_invisible alone (Shadowmeld owns it).
			# Otherwise clear so enemies can re-acquire the ally.
			var sm = ally.get("shadowmeld_component")
			var still_stealthed: bool = false
			if sm != null and is_instance_valid(sm) and sm.has_method("is_stealthed"):
				still_stealthed = sm.is_stealthed()
			if not still_stealthed:
				ally.set_meta("is_invisible", false)
			# Shadow Smoke (T3) — leaving the cloud grants a guaranteed-crit
			# window on the next attack. Read from the per-cast instance var
			# captured in execute(); a one-shot meta combat.gd consumes on
			# the first crit hit (mirrors MarkOfTheHunt.consume_mark).
			if _exit_crit_window_sec > 0.0:
				var crit_until: int = Time.get_ticks_msec() + int(_exit_crit_window_sec * 1000.0)
				ally.set_meta(SMOKE_EXIT_CRIT_UNTIL_META, crit_until)
	)


## Per-tick callback for enemies inside the cloud. Choking Smoke (T3):
## stamps each enemy with a debuff window. health.gd's take_damage path
## reads the meta when the enemy attacks a player and scales the outgoing
## damage by (1 - smoke_choke_pct).
##
## Refreshed every tick while the enemy is inside, with a SMOKE_CHOKE_LINGER_SEC
## linger past the tick interval — so the description's "for 2s after
## leaving" promise holds via the same expire-timestamp pattern that
## stops _apply_hidden from flickering (see
## [[feedback_refresh_effects_use_expire_timestamp]]).
func _apply_enemy_choke(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if _enemy_debuff_pct <= 0.0:
		return
	var expire_at: int = Time.get_ticks_msec() + int(SMOKE_CHOKE_LINGER_SEC * 1000.0)
	enemy.set_meta(SMOKE_CHOKE_EXPIRE_META, expire_at)
	enemy.set_meta(SMOKE_CHOKE_PCT_META, _enemy_debuff_pct)
