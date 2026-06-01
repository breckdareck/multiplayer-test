class_name GroundZone
extends Node2D

## A persistent server-authoritative ground area that ticks damage on enemies
## inside it for a duration, then despawns. Cross-weapon infrastructure for
## any ability that wants a "drop a hazard / heal / control zone at a spot."
##
## Architecture mirrors the staff-element rider + lightning-arc patterns:
## - **Server-authoritative damage** — every tick enumerates Enemies overlapping
##   the zone, applies `health_comp.take_damage` server-side, and credits DOT
##   kills via the same `_credit_dot_kill` shape used by burns.
## - **Cosmetic visual is broadcast** — for remote clients, MapManager spawns a
##   visual-only mirror (damage_per_tick=0, applier=null) so the circle renders
##   without running gameplay logic.
## - **`networked_entities` group** — joined in _ready so MultiplayerManager's
##   cleanup sweep frees the zone on disconnect / channel switch.
## - **Tick cadence is zone-aligned** — every `tick_interval` the zone enumerates
##   currently-overlapping enemies and damages each; new entries wait until the
##   next tick boundary (matches the locked design — see project memory
##   project_ground_zone_infrastructure).
## - **Map filter** — `_cached_map_root` (parent at spawn time, i.e. the map's
##   scene_instance) gates damage to enemies in the same map, since the
##   `Enemies` group is GLOBAL across all maps (see CLAUDE.md).
##
## Spawn via `GroundZone.spawn_server(applier, pos, ...)` from any AL_*.gd's
## server-side context. The caller is responsible for the `is_server` guard
## (which AL_*.gd already does at its on_hit/execute entry).

#region #################### Configuration (filled at spawn) ####################

## Hit-test radius in pixels. v1 supports circular zones only — the most common
## shape across Caltrops / Pyre Burst pool / Earthsplitter / Smoke Bomb / etc.
var radius: float = 50.0

## Total lifetime in seconds. Zone queue_frees itself after this many seconds
## have elapsed since spawn. Runs on all peers so remote-client visuals expire
## without needing a separate teardown RPC.
var duration: float = 4.0

## Seconds between damage ticks. The first tick fires `tick_interval` seconds
## after spawn (not immediately) so a new zone doesn't instantly damage on
## frame 0 — this matches the locked tick cadence: enemies inside at spawn
## wait one full interval before taking their first tick.
var tick_interval: float = 1.0

## Absolute integer damage per enemy per tick. Set by the caller — typically
## `int(ability_main_hit_damage * pct)` so the zone scales proportionally with
## the spawning ability (matches the staff-element-burn pattern: 12% of the
## triggering hit). Pass 0 for a pure-utility zone (no damage, only callback).
var damage_per_tick: int = 0

## The player node responsible for damage attribution. Used for aggro routing,
## the source of the damage number, mastery XP credit on a DOT kill, and the
## on_kill passive dispatch. May be set to null on visual-mirror clones.
var applier: Node = null

## Color of the filled circle drawn on every peer. Alpha gates how prominent
## the zone reads on screen. Use Fire-orange for burn pools, Ice-blue for
## slow patches, etc.
var visual_color: Color = Color(0.9, 0.4, 0.15, 0.35)

## Optional per-tick callback. Signature: `func(enemy: Node) -> void`.
## Called once per enemy per tick AFTER damage is applied. Use for non-damage
## status effects (Caltrops slow, Smoke Bomb concealment, Frost Patch chill).
## Server-only — never set on visual-mirror clones.
var on_tick_callback: Callable = Callable()

## Optional per-tick ALLY callback. Signature: `func(ally: Node) -> void`.
## Called once per ally per tick — iterates the "Players" group in addition
## to the Enemies group. Use for defensive party-buff zones (Banner of the
## Vanguard's +Defense + HP regen aura) where the zone is benevolent to
## party members. Server-only — never set on visual-mirror clones.
var on_ally_tick_callback: Callable = Callable()

#endregion


#region #################### Internal state ####################

var _elapsed: float = 0.0
var _next_tick: float = 0.0
var _cached_map_root: Node = null
var _initial_alpha: float = 0.35

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	add_to_group("networked_entities")
	_cached_map_root = get_parent()
	_next_tick = tick_interval
	_initial_alpha = visual_color.a
	queue_redraw()


func _draw() -> void:
	# Filled disc + thin outline. The outline is a slightly bolder version of
	# the fill so different-element zones (fire-orange, ice-blue) read at a
	# glance without per-zone art.
	draw_circle(Vector2.ZERO, radius, visual_color)
	var outline := Color(visual_color.r, visual_color.g, visual_color.b, minf(1.0, visual_color.a * 2.5))
	draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outline, 2.0)


func _physics_process(delta: float) -> void:
	_elapsed += delta

	# Linear alpha taper across the zone's lifetime — full alpha at spawn,
	# 50% alpha at expiration so the zone visibly fades rather than vanishing.
	var t := clampf(_elapsed / duration, 0.0, 1.0)
	visual_color.a = _initial_alpha * (1.0 - 0.5 * t)
	queue_redraw()

	if _elapsed >= duration:
		queue_free()
		return

	# Server-only damage tick. Visual-mirror clones on remote clients have
	# damage_per_tick == 0, so even if this passed it would no-op — but
	# gating on is_server is the canonical pattern for any state mutator.
	if not multiplayer.is_server():
		return

	_next_tick -= delta
	if _next_tick > 0.0:
		return
	_next_tick = tick_interval
	_do_tick()

#endregion


#region #################### Server-side damage tick ####################

func _do_tick() -> void:
	# Skip entirely if no work is configured — pure visual zones (the remote-
	# client mirror) early-return here.
	if damage_per_tick <= 0 and not on_tick_callback.is_valid() and not on_ally_tick_callback.is_valid():
		return

	var center: Vector2 = global_position
	var r2: float = radius * radius

	# Ally tick — iterate the Players group (separate from Enemies) and fire
	# the ally callback once per ally currently overlapping. Same map filter
	# + circle overlap check as the enemy loop. Skipped when no ally
	# callback is configured (the common case).
	if on_ally_tick_callback.is_valid():
		for ally in get_tree().get_nodes_in_group("Players"):
			if not is_instance_valid(ally):
				continue
			if _cached_map_root != null and not _cached_map_root.is_ancestor_of(ally):
				continue
			var ally_pos: Vector2 = ally.global_position
			var dist_sq: float = (ally_pos - center).length_squared()
			if dist_sq > r2:
				continue
			on_ally_tick_callback.call(ally)

	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		# Map filter: the Enemies group is GLOBAL across maps. Skip any enemy
		# not under our spawn-time parent (which IS the map's scene_instance).
		if _cached_map_root != null and not _cached_map_root.is_ancestor_of(enemy):
			continue
		# Circle overlap — center distance vs radius. Explicit types because
		# `enemy` from `get_nodes_in_group` is loosely Variant and Godot's
		# inference can't carry through to length_squared() without help.
		var enemy_pos: Vector2 = enemy.global_position
		var d2: float = (enemy_pos - center).length_squared()
		if d2 > r2:
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue

		# Damage path — always bypass i-frames (a 1s tick lined up with the 1s
		# invuln window would otherwise lose half its ticks). is_crit=false
		# because DOT-style zone ticks never crit. show_number=true so the
		# player sees the zone is working.
		if damage_per_tick > 0:
			var was_alive: bool = not hc.is_dead
			var src = applier if is_instance_valid(applier) else null
			hc.take_damage(damage_per_tick, src, true, false, true)
			# Credit DOT kill the same way burns do — mastery XP + on_kill
			# passives wouldn't fire through combat.gd's _execute_hit otherwise.
			if was_alive and hc.is_dead:
				_credit_dot_kill(src, enemy)

		# Optional non-damage callback (Caltrops slow / Smoke Bomb cover / etc.)
		if on_tick_callback.is_valid():
			on_tick_callback.call(enemy)

#endregion


#region #################### DOT-kill credit (same shape as StaffElement + burns) ####################

## When a zone tick lands the killing blow, combat.gd._execute_hit never runs
## so mastery XP and on_kill passive events would silently not fire. This
## credits the applier exactly like a direct hit would. Verbatim from
## StaffElementComponent._credit_dot_kill — kept inline for self-containment.
func _credit_dot_kill(applier_node, target: Node) -> void:
	if applier_node == null or not is_instance_valid(applier_node):
		return
	if target == null or not is_instance_valid(target):
		return

	var mastery_comp = applier_node.get("weapon_mastery_component")
	var combat_comp = applier_node.get("combat_component")
	if mastery_comp and combat_comp and "monster_level" in target and applier_node.level_component:
		var kill_xp: int = WeaponMasteryComponent.compute_kill_xp(
			target.monster_level,
			applier_node.level_component.level
		)
		var kill_disc: int = combat_comp._active_weapon_discipline()
		if kill_disc != -1:
			mastery_comp.grant_mastery_xp_server(kill_disc, kill_xp)
		var sec_disc: int = combat_comp._secondary_weapon_discipline()
		if sec_disc != -1 and sec_disc != kill_disc:
			mastery_comp.grant_mastery_xp_server(sec_disc, kill_xp)

	var ability_comp = applier_node.get("ability_component")
	if ability_comp and ability_comp.has_method("dispatch_passive_event_on_kill"):
		ability_comp.dispatch_passive_event_on_kill(target)

#endregion


#region #################### Server-side static spawner ####################

## **SERVER-ONLY**. Spawns a GroundZone under the applier's current map and
## broadcasts a visual mirror to every other client on that map. Call from
## any AL_*.gd's server-guarded code path (which AL_*.gd already establishes
## at the top of `execute` / `on_hit`).
##
## `applier` must be the casting player node (carries `player_id` and a
## CombatComponent). `pos` is in global coordinates.
##
## `damage_per_tick` is the absolute integer damage applied per enemy per
## tick. Callers compute it as `int(main_hit_damage * pct)` to scale with the
## spawning ability — matching the staff-element-burn convention
## (`BURN_HIT_PCT = 0.12 × triggering hit`). Pass 0 for utility-only zones.
##
## `on_tick_callback` is an optional Callable(enemy: Node) -> void invoked
## per enemy per tick AFTER damage. Use for slow/chill/concealment-style
## effects that the zone applies passively.
## Return type is Node2D rather than GroundZone because Godot 4's parser
## can't resolve a class's own class_name inside its own static methods at
## load time. Callers receive the same object — only the static type is
## widened — and can still access the properties directly.
static func spawn_server(
	applier: Node,
	pos: Vector2,
	radius: float,
	duration: float,
	tick_interval: float,
	damage_per_tick: int,
	visual_color: Color = Color(0.9, 0.4, 0.15, 0.35),
	on_tick_callback: Callable = Callable(),
	on_ally_tick_callback: Callable = Callable(),
) -> Node2D:
	if not is_instance_valid(applier):
		return null
	if not applier.multiplayer.is_server():
		push_warning("GroundZone.spawn_server called off-server — ignoring")
		return null
	if not "player_id" in applier:
		push_warning("GroundZone.spawn_server: applier has no player_id")
		return null

	var map_id: String = MapManager.get_player_map(applier.player_id)
	if map_id == "":
		return null
	var map_inst = MapManager.active_maps[map_id].get("scene_instance")
	if not is_instance_valid(map_inst):
		return null

	# load() at runtime sidesteps the same-script self-reference issue.
	var zone = load("res://scripts/Gameplay/ground_zone.gd").new()
	zone.global_position = pos
	zone.radius = radius
	zone.duration = duration
	zone.tick_interval = tick_interval
	zone.damage_per_tick = damage_per_tick
	zone.applier = applier
	zone.visual_color = visual_color
	zone.on_tick_callback = on_tick_callback
	zone.on_ally_tick_callback = on_ally_tick_callback
	map_inst.add_child(zone)

	# Broadcast a visual-only mirror to remote clients viewing the same map.
	# The host is also a client but its mirror is unnecessary — the
	# authoritative zone above already renders on screen when the host is on
	# this map (matches the lightning-arc broadcast pattern).
	MapManager.broadcast_ground_zone(map_id, pos, radius, duration, visual_color)

	return zone

#endregion
