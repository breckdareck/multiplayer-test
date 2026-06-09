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

## Shape model. v1 supports two shapes:
##   CIRCLE — symmetric radial zone (auras, smoke clouds, omni-direction)
##   RECT   — axis-aligned rectangle, ideal for "ground zone" abilities in a 2D
##            platformer where a wide-x / short-y rect hugs the floor and hits
##            enemies standing on it without towering over the camera
enum Shape { CIRCLE = 0, RECT = 1 }
var shape_type: int = Shape.CIRCLE

## Hit-test radius in pixels. Used when shape_type == CIRCLE.
var radius: float = 50.0

## Hit-test rect size (full width × height in pixels). Used when shape_type ==
## RECT. The rectangle is centered on the zone's global_position; callers
## that want a "ground rectangle" (hugging the floor, touching enemy hitboxes
## but not stretching above their heads) should typically set y in the
## 30–60 px range and x as the desired horizontal coverage.
var rect_size: Vector2 = Vector2(120.0, 40.0)

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

## Whether the zone draws its own fill + outline + boundary brackets. Boss
## telegraphs leave this true so the wind-up area reads clearly. Player-ability
## zones set it false — they already broadcast a tiled ground VFX
## (`broadcast_ground_vfx_everywhere`), so the zone's own outline is redundant
## and is suppressed. Pure-gameplay hit-testing is unaffected either way.
var draw_visual: bool = true

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

## Tick-pulse intensity in [0, 1]. Set to 1.0 each time _next_tick wraps; decays
## continuously so each tick produces a brief visible flash. Synchronized on
## every peer because the tick countdown is decremented in _physics_process
## above the server gate (deterministic timing).
var _tick_pulse: float = 0.0
const _TICK_PULSE_DECAY: float = 4.5  ## intensity drops by ~4.5/s (visible flash ~0.25s)

## Spawn flash — full intensity at spawn, decays over the first ~0.3s so the
## zone's appearance is unmistakable on every peer.
var _spawn_pulse: float = 1.0
const _SPAWN_PULSE_DECAY: float = 3.5

## Bracket length (px) for the corner L-shapes (RECT) and the radial tick
## marks (CIRCLE). Tuned so the boundary indicators read clearly without
## visually competing with the filled body.
const _BRACKET_LEN: float = 14.0
const _BRACKET_WIDTH: float = 3.0

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	add_to_group("networked_entities")
	_cached_map_root = get_parent()
	_next_tick = tick_interval
	_initial_alpha = visual_color.a
	if draw_visual:
		queue_redraw()


func _draw() -> void:
	# Player-ability zones suppress their own drawing (the ability already
	# broadcasts a tiled ground VFX). Only boss telegraphs draw the outline.
	if not draw_visual:
		return
	# Fill + bolder outline, then the temporary spawn/tick flash overlays + the
	# corner brackets (RECT) or radial tick marks (CIRCLE) that always
	# telegraph the zone's extent regardless of fade state.
	#
	# pulse_boost combines the spawn flash and per-tick flash so the zone
	# noticeably brightens on appearance and on every damage tick — together
	# the player gets the area's EXTENT (from brackets) and its CADENCE
	# (from the tick pulse).
	var pulse_boost: float = _spawn_pulse * 0.45 + _tick_pulse * 0.35

	var fill := visual_color
	fill.a = minf(1.0, visual_color.a + pulse_boost * 0.35)

	var outline := Color(visual_color.r, visual_color.g, visual_color.b, minf(1.0, visual_color.a * 2.5))
	outline.a = minf(1.0, outline.a + pulse_boost * 0.45)

	# Bracket / tick-mark color is always near full alpha so the boundary
	# stays unmistakable even after the fill has faded toward the end of the
	# zone's lifetime.
	var bracket := Color(visual_color.r, visual_color.g, visual_color.b, 0.95)

	if shape_type == Shape.RECT:
		var rect := Rect2(-rect_size * 0.5, rect_size)
		draw_rect(rect, fill, true)
		draw_rect(rect, outline, false, 2.5)
		_draw_rect_corner_brackets(bracket)
	else:
		draw_circle(Vector2.ZERO, radius, fill)
		draw_arc(Vector2.ZERO, radius, 0.0, TAU, 48, outline, 2.5)
		_draw_circle_tick_marks(bracket)


## L-shaped brackets at each rect corner. Each bracket is two short lines
## pointing INWARD along the rectangle's edges. The brackets are sized for
## visual clarity at the smallest expected zone (~140 px wide) and look fine
## scaled up — no per-zone tuning needed.
func _draw_rect_corner_brackets(color: Color) -> void:
	var half := rect_size * 0.5
	# Each entry: (corner position, x-direction inward, y-direction inward).
	# x/y dirs point AWAY from the corner along the adjacent edges so the
	# bracket sits inside the rectangle.
	var brackets: Array = [
		[Vector2(-half.x, -half.y), Vector2(1, 0), Vector2(0, 1)],   # TL
		[Vector2( half.x, -half.y), Vector2(-1, 0), Vector2(0, 1)],  # TR
		[Vector2( half.x,  half.y), Vector2(-1, 0), Vector2(0, -1)], # BR
		[Vector2(-half.x,  half.y), Vector2(1, 0), Vector2(0, -1)],  # BL
	]
	var L: float = _BRACKET_LEN
	for b in brackets:
		var c: Vector2 = b[0]
		var d1: Vector2 = b[1] * L
		var d2: Vector2 = b[2] * L
		draw_line(c, c + d1, color, _BRACKET_WIDTH)
		draw_line(c, c + d2, color, _BRACKET_WIDTH)


## Eight radial tick marks at compass points around the circle (N/NE/E/SE/
## S/SW/W/NW). Each tick is a short line from just inside the radius to
## exactly on the radius, drawn over the outline so the boundary reads at
## any fade level.
func _draw_circle_tick_marks(color: Color) -> void:
	var L: float = minf(_BRACKET_LEN, radius * 0.4)
	for i in range(8):
		var angle: float = float(i) * (TAU / 8.0)
		var outer := Vector2(cos(angle), sin(angle)) * radius
		var inner := Vector2(cos(angle), sin(angle)) * (radius - L)
		draw_line(inner, outer, color, _BRACKET_WIDTH)


func _physics_process(delta: float) -> void:
	_elapsed += delta

	# Visual upkeep — skipped entirely for non-drawing (player-ability) zones.
	if draw_visual:
		# Linear alpha taper across the zone's lifetime — full alpha at spawn,
		# 50% alpha at expiration so the zone visibly fades rather than vanishing.
		var t := clampf(_elapsed / duration, 0.0, 1.0)
		visual_color.a = _initial_alpha * (1.0 - 0.5 * t)

		# Decay the temporary-flash intensities. Runs on every peer because the
		# visual flash applies to both server and remote-mirror clones — the
		# server is also a client on a listen-server setup.
		_tick_pulse = maxf(0.0, _tick_pulse - delta * _TICK_PULSE_DECAY)
		_spawn_pulse = maxf(0.0, _spawn_pulse - delta * _SPAWN_PULSE_DECAY)
		queue_redraw()

	if _elapsed >= duration:
		queue_free()
		return

	# Tick countdown runs on ALL peers (above the is_server gate) so the
	# visual pulse fires simultaneously on server + remote-mirror clones.
	# The cadence is deterministic — both peers initialise _next_tick =
	# tick_interval in _ready, then decrement at the same rate. Damage
	# application stays server-only via _do_tick below.
	_next_tick -= delta
	if _next_tick > 0.0:
		return
	_next_tick = tick_interval
	_tick_pulse = 1.0  # visible flash on every peer
	if not multiplayer.is_server():
		return
	_do_tick()

#endregion


#region #################### Server-side damage tick ####################

func _do_tick() -> void:
	# Skip entirely if no work is configured — pure visual zones (the remote-
	# client mirror) early-return here.
	if damage_per_tick <= 0 and not on_tick_callback.is_valid() and not on_ally_tick_callback.is_valid():
		return

	var center: Vector2 = global_position

	# Ally tick — iterate the Players group (separate from Enemies) and fire
	# the ally callback once per ally currently overlapping. Same map filter
	# + shape overlap test as the enemy loop. Skipped when no ally callback
	# is configured (the common case).
	if on_ally_tick_callback.is_valid():
		for ally in get_tree().get_nodes_in_group("Players"):
			if not is_instance_valid(ally):
				continue
			if _cached_map_root != null and not _cached_map_root.is_ancestor_of(ally):
				continue
			if not _is_inside(ally.global_position, center):
				continue
			on_ally_tick_callback.call(ally)

	for enemy in get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		# Map filter: the Enemies group is GLOBAL across maps. Skip any enemy
		# not under our spawn-time parent (which IS the map's scene_instance).
		if _cached_map_root != null and not _cached_map_root.is_ancestor_of(enemy):
			continue
		# Shape overlap — circle radius² check OR axis-aligned rect bounds.
		# Explicit types because `enemy` from `get_nodes_in_group` is loosely
		# Variant and Godot's inference can't carry through without help.
		var enemy_pos: Vector2 = enemy.global_position
		if not _is_inside(enemy_pos, center):
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


## Shape-aware point-in-zone test. Branches on shape_type so CIRCLE uses a
## squared-distance comparison and RECT uses axis-aligned bounds. Both
## operate in global coordinates against the zone's `center` (passed in by
## the caller to avoid re-reading global_position twice per enemy).
func _is_inside(world_pos: Vector2, center: Vector2) -> bool:
	if shape_type == Shape.RECT:
		var local := world_pos - center
		var half := rect_size * 0.5
		return absf(local.x) <= half.x and absf(local.y) <= half.y
	# CIRCLE (default)
	var d2: float = (world_pos - center).length_squared()
	return d2 <= radius * radius

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
##
## CIRCLE-shaped convenience. Equivalent to `spawn_server_shaped` with
## shape_type=CIRCLE and rect_size unused. All existing call sites use this
## form; new ground-rect uses should call `spawn_server_rect` instead.
@warning_ignore("shadowed_variable")
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
	return spawn_server_shaped(
		applier, pos, Shape.CIRCLE, radius, Vector2.ZERO,
		duration, tick_interval, damage_per_tick,
		visual_color, on_tick_callback, on_ally_tick_callback,
	)


## RECT-shaped convenience. Wraps `spawn_server_shaped` for the common
## ground-rectangle pattern in this 2D platformer: a wide-x / short-y zone
## that hugs the floor and hits enemies standing on it without towering
## above their hitboxes. `rect_size` is full width × full height (centered
## on `pos`).
@warning_ignore("shadowed_variable")
static func spawn_server_rect(
	applier: Node,
	pos: Vector2,
	rect_size: Vector2,
	duration: float,
	tick_interval: float,
	damage_per_tick: int,
	visual_color: Color = Color(0.9, 0.4, 0.15, 0.35),
	on_tick_callback: Callable = Callable(),
	on_ally_tick_callback: Callable = Callable(),
) -> Node2D:
	return spawn_server_shaped(
		applier, pos, Shape.RECT, 0.0, rect_size,
		duration, tick_interval, damage_per_tick,
		visual_color, on_tick_callback, on_ally_tick_callback,
	)


## Lowest-level spawn helper. Used by both convenience entry points above
## so the actual zone construction lives in exactly one place.
@warning_ignore("shadowed_variable")
static func spawn_server_shaped(
	applier: Node,
	pos: Vector2,
	shape_type_arg: int,
	radius_arg: float,
	rect_size_arg: Vector2,
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
	zone.shape_type = shape_type_arg
	zone.radius = radius_arg
	zone.rect_size = rect_size_arg
	zone.duration = duration
	zone.tick_interval = tick_interval
	zone.damage_per_tick = damage_per_tick
	zone.applier = applier
	zone.visual_color = visual_color
	zone.on_tick_callback = on_tick_callback
	zone.on_ally_tick_callback = on_ally_tick_callback
	# Player-ability zones don't draw their own outline — the spawning ability
	# already broadcasts a tiled ground VFX that telegraphs the area. The zone
	# stays a pure server-authoritative hit-test region. (Boss telegraphs spawn
	# via MapManager._spawn_ground_zone_visual, which leaves draw_visual=true.)
	zone.draw_visual = false
	map_inst.add_child(zone)

	# No visual-mirror broadcast: with draw_visual off the mirror would render
	# nothing, and the spawning ability handles remote-client visuals via its
	# own broadcast_ground_vfx_everywhere call.

	return zone

#endregion
