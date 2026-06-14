extends Node

## Smoke Bomb — the Dagger discipline's defensive ground-zone. Drops a smoke
## cloud at the caster's feet for 4 seconds. Allies inside gain +Evasion —
## a per-hit % chance to dodge any incoming damage. The base ability does
## NOT make allies invisible (the earlier is_invisible implementation was
## too strong; enemies didn't target you at all and the cloud read as 100%
## immunity rather than concealment). Evasion is a real partial defense:
## enemies still attack, but lots of hits miss while you're in the smoke.
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
## re-applies the Smoke Screen buff (B_Smoke_Screen.tres, +EVASIONCHANCE) to each
## ally inside — the same shape Banner of the Vanguard uses for its defensive aura.
## A real buff (not a raw meta) means the player SEES it on the buff bar and in the
## Evasion stat, and the dodge runs through the unified enemy hit-chance roll in
## enemy_base. REFRESH stacking + a duration slightly longer than the tick interval
## keeps it continuous while inside and lets it lapse shortly after exit (per
## [[feedback_refresh_effects_use_expire_timestamp]]).

const ZONE_RADIUS: float = 90.0
const ZONE_DURATION: float = 4.0
const ZONE_TICK_INTERVAL: float = 0.5  ## half-second tick — keeps the evasion meta fresh

## The defensive aura allies inside the cloud get — a real BuffComponent buff
## (B_Smoke_Screen.tres) granting +EVASIONCHANCE, exactly the shape Banner of the
## Vanguard uses for its defensive aura. Unlike the old raw meta, the buff SHOWS on
## the buff bar and raises the visible Evasion stat, and the dodge is rolled by the
## unified enemy hit-chance path in enemy_base — so it also earns the dodge→
## guaranteed-crit payoff and (by design) does NOT auto-dodge telegraphed boss
## specials. The buff's +40 EVASIONCHANCE matches the ability's "+40% Evasion" tooltip.
const SMOKE_BUFF_ID: String = "Smoke Screen"

## Buff duration per refresh. > ZONE_TICK_INTERVAL so consecutive 0.5s ticks always
## overlap (no flicker while inside); the buffer past the tick interval is how long
## the cover lingers after the ally walks OUT (1.0s ⇒ ~0.5s linger).
const SMOKE_BUFF_DURATION: float = 1.0

## How long the Shadow Smoke (T3) inside-crit meta lingers past a tick — same
## per-tick-refresh + linger pattern, so the crit window stays continuous while
## inside and decays cleanly on exit.
const SMOKE_INSIDE_LINGER_SEC: float = 1.0

## T3 upgrade metas:
##   - smoke_choke_*: on enemies inside the cloud. health.gd checks both and
##     scales incoming-from-this-enemy damage down by smoke_choke_pct while
##     the expiry is in the future. Refreshed every enemy tick + lingers 2s
##     after the enemy leaves so Choking Smoke's "while inside AND 2s after
##     leaving" promise holds (per-tick refresh covers the "inside" case;
##     SMOKE_CHOKE_LINGER_SEC covers the "after leaving" case).
##   - smoke_inside_crit_until_ms: on each ally inside the cloud. combat.gd
##     forces is_crit while the timestamp is in the future. Refreshed every
##     ally tick — natural ramp-down past the linger after exit. NOT a
##     one-shot consume (unlike MarkOfTheHunt), so every attack from inside
##     the cloud crits as long as the meta is fresh.
const SMOKE_CHOKE_EXPIRE_META: String = "smoke_choke_expire_at_ms"
const SMOKE_CHOKE_PCT_META: String = "smoke_choke_pct"
const SMOKE_CHOKE_LINGER_SEC: float = 2.0
const SMOKE_INSIDE_CRIT_UNTIL_META: String = "smoke_inside_crit_until_ms"

## Per-cast config populated by execute() from PR 6 upgrade reads. The
## logic_script instance is constructed via `.new()` once per cast and held
## alive by the Callable references inside the GroundZone, so these instance
## vars persist for the cast's lifetime.
var _enemy_debuff_pct: float = 0.0
var _ally_heal_per_tick: int = 0
var _inside_crit_active: bool = false

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
		# Shadow Smoke is a binary "owned / not owned" upgrade — guaranteed
		# crit while inside the cloud, no scaling. The generator stores
		# magnitude > 0 when owned; treat any positive read as "active."
		_inside_crit_active = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_inside_crit") > 0.0

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

	# Ground "juice" — a tiled smoke band billowing across the cloud (circle:
	# width = diameter = 2×radius).
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "smoke_ground", owner_node.global_position, radius * 2.0, duration)


## Per-tick callback fired by the zone for each ALLY currently inside.
## Re-applies the Smoke Screen buff (+EVASIONCHANCE) — the actual dodge roll
## happens in enemy_base's hit-chance path, exactly like innate rogue evasion.
## REFRESH stacking + a duration slightly longer than the tick interval keeps the
## buff continuous while the ally is inside and lets it lapse shortly after they
## leave — no per-ally clear timer needed because it just stops being refreshed.
##
## Also drives the two ally-side T3 effects when owned: per-tick heal
## (Restorative Smoke) and an inside-the-cloud guaranteed-crit meta
## (Shadow Smoke) — combat.gd reads the latter to force is_crit=true on
## attacks while the ally is in the smoke.
func _apply_hidden(ally: Node) -> void:
	if not is_instance_valid(ally):
		return

	# Defensive aura: (re-)apply the Smoke Screen buff (+EVASIONCHANCE). Mirrors
	# Banner's _apply_banner_aura — a real BuffComponent buff so it shows on the buff
	# bar + Evasion stat, and the dodge is rolled by enemy_base's unified hit-chance
	# path. REFRESH stacking keeps it continuous while inside; it lapses ~0.5s after
	# the ally leaves (duration 1.0 > 0.5s tick).
	var buff_comp = ally.get_node_or_null("Components/Buff")
	if buff_comp != null and is_instance_valid(buff_comp) and buff_comp.has_method("apply_buff"):
		buff_comp.apply_buff(SMOKE_BUFF_ID, null, SMOKE_BUFF_DURATION)

	# Restorative Smoke (T3) — per-tick heal while inside. Direct HealthComponent
	# heal; safe to call every tick because heal clamps at max_health.
	if _ally_heal_per_tick > 0:
		var hc = ally.get("health_component")
		if hc != null and is_instance_valid(hc) and not hc.is_dead:
			if hc.has_method("heal_damage"):
				hc.heal_damage(_ally_heal_per_tick)
			elif "current_health" in hc and "max_health" in hc:
				hc.current_health = mini(int(hc.max_health), int(hc.current_health) + _ally_heal_per_tick)

	# Shadow Smoke (T3) — guaranteed crit while INSIDE the cloud. Uses the
	# same expire timestamp as evasion so the crit window stays active as
	# long as the ally is in the cloud and decays cleanly after exit (no
	# "go-in-then-out" requirement; the user can strike directly from cover).
	if _inside_crit_active:
		ally.set_meta(SMOKE_INSIDE_CRIT_UNTIL_META, Time.get_ticks_msec() + int(SMOKE_INSIDE_LINGER_SEC * 1000.0))


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
