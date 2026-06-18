extends Control
## MapleStory-style minimap. A small always-on HUD widget (top-left) that draws a
## scaled silhouette of the current map's platforms plus live dots for the local
## player, other players/bots, portals, and (toggleable) enemies.
##
## Pure CLIENT-SIDE presentation: it reads already-replicated node positions and
## the map's own TileMapLayer. It never mutates state and sends no RPCs.
##
## Registered as a `bind_player` widget under PlayerHUD so LocalPlayerUI rebinds it
## on every spawn; it also implements `notify_map_arrival()` for the host's
## reparent map-change fast-path (which does NOT re-emit local_player_changed).
##
## Coordinate spaces: the live map lives in its own SubViewport World2D, so we must
## NOT use Godot's to_local()/to_global() to cross into this CanvasLayer. Instead we
## read world positions (all in the map's world) and map them arithmetically into
## the minimap rect via `_world_to_map()`.

const PANEL_BG := Color(0.05, 0.06, 0.09, 0.78)
const PANEL_BORDER := Color(0.9, 0.85, 0.5, 0.5)
const TERRAIN_COLOR := Color(0.45, 0.62, 0.42, 0.85)
const PORTAL_COLOR := Color(0.4, 1.0, 0.55, 1.0)
const PLAYER_COLOR := Color(1.0, 0.9, 0.2, 1.0)   ## local player
const OTHER_COLOR := Color(0.4, 0.7, 1.0, 1.0)    ## other humans
const BOT_COLOR := Color(0.7, 0.7, 0.75, 1.0)     ## bots
const ENEMY_COLOR := Color(1.0, 0.35, 0.35, 1.0)

const EXPANDED_SIZE := Vector2(212, 168)
const HEADER_H := 20.0
const PAD := 6.0
## How far a wide map may zoom past full-width-fit before the view starts
## scrolling to follow the player (instead of cramming the whole width in).
## Higher = long maps render at a more readable scale and scroll to follow you.
const SCROLL_ZOOM := 3.0
## Upper bound on the fit scale (minimap-px per world-px). Without this a TINY map
## fits-to-height and balloons to fill the whole box; the cap holds a tiny map at a
## sane scale, centered, with breathing room — instead of over-zooming it.
const MAX_ZOOM := 0.28
## Character dots are lifted this many px so they sit ON TOP of the platform line
## rather than centered on it (a character's origin is at its feet = the tile top).
const ENTITY_LIFT := 5.0

@export var show_enemies: bool = true

var _player: Node = null
var _map_instance: Node = null
var _layer: TileMapLayer = null
var _plat_layer: TileMapLayer = null   ## one-way Platform layer (shelves / drop-downs)
## World-space rect of the current map's painted terrain (the playfield extent).
var _world_bounds: Rect2 = Rect2()
## Surface-cell top-left corners in WORLD space (recomputed only on map change).
## Stored in world space so the draw transform can fit them with a UNIFORM scale
## (preserve aspect / letterbox) instead of stretching X and Y independently.
var _terrain_world: PackedVector2Array = PackedVector2Array()
var _tile_size: Vector2 = Vector2(16, 16)
var _collapsed: bool = false
var _title: String = ""
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(12, 12)
	custom_minimum_size = EXPANDED_SIZE
	size = EXPANDED_SIZE
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = ThemeDB.fallback_font
	set_process(true)


## Called by LocalPlayerUI on spawn / remote map change.
func bind_player(body) -> void:
	_player = body
	_refresh_map()


## Called by LocalPlayerUI on the host reparent fast-path (no new body).
func notify_map_arrival() -> void:
	_refresh_map()


func _refresh_map() -> void:
	_map_instance = MapManager.current_map_instance
	_title = MapManager.MAP_DISPLAY_NAMES.get(MapManager.current_map_id, MapManager.current_map_id)
	_layer = null
	_plat_layer = null
	_terrain_world = PackedVector2Array()
	_world_bounds = Rect2()
	if not is_instance_valid(_map_instance):
		queue_redraw()
		return
	if _map_instance is MapBase:
		_layer = (_map_instance as MapBase)._find_playable_tilemap_layer(_map_instance)
		if _layer:
			_plat_layer = _layer.get_parent().get_node_or_null("Platform")
	_compute_terrain()
	queue_redraw()


## Build the world-space playfield rect and a normalized terrain-cell list once
## per map. Prefers the painted tilemap extent (tight) over the padded camera box.
func _compute_terrain() -> void:
	if _layer == null or _layer.tile_set == null:
		# Fall back to the map's camera bounds so we can still draw a box + dots.
		if _map_instance and _map_instance.get("camera_limit_left") != null:
			var l: float = _map_instance.get("camera_limit_left")
			var t: float = _map_instance.get("camera_limit_top")
			var r: float = _map_instance.get("camera_limit_right")
			var b: float = _map_instance.get("camera_limit_bottom")
			_world_bounds = Rect2(l, t, maxf(1.0, r - l), maxf(1.0, b - t))
		return
	var ts: Vector2 = Vector2(_layer.tile_set.tile_size)
	_tile_size = ts
	var cells: Array[Vector2i] = _layer.get_used_cells()
	# Include the one-way Platform layer (shelves / drop-down platforms), not just Mid, so the
	# minimap silhouette shows every standable surface.
	if _plat_layer != null:
		cells.append_array(_plat_layer.get_used_cells())
	if cells.is_empty():
		return
	# Keep only WALKABLE SURFACES — a tile with empty space directly above it is a
	# platform/ground top. This drops the solid dirt body (and any deep fill) so the
	# minimap shows thin platform lines (MapleStory-style), not a filled silhouette.
	var cellset := {}
	for c in cells:
		cellset[c] = true
	var surface: Array[Vector2i] = []
	for c in cells:
		if not cellset.has(c + Vector2i(0, -1)):
			surface.append(c)
	if surface.is_empty():
		surface = cells
	# Frame the map by the SURFACE extent, so deep fill can't stretch/sink the view.
	var minc: Vector2i = surface[0]
	var maxc: Vector2i = surface[0]
	for c in surface:
		minc.x = mini(minc.x, c.x); minc.y = mini(minc.y, c.y)
		maxc.x = maxi(maxc.x, c.x); maxc.y = maxi(maxc.y, c.y)
	var wmin: Vector2 = _layer.to_global(Vector2(minc) * ts)
	var wmax: Vector2 = _layer.to_global(Vector2(maxc + Vector2i(1, 1)) * ts)
	var margin: Vector2 = (wmax - wmin) * 0.06 + ts
	_world_bounds = Rect2(wmin - margin, (wmax - wmin) + margin * 2.0)
	if _world_bounds.size.x <= 0 or _world_bounds.size.y <= 0:
		return
	var world := PackedVector2Array()
	for c in surface:
		world.append(_layer.to_global(Vector2(c) * ts))
	_terrain_world = world


func _process(_delta: float) -> void:
	if visible and not _collapsed and is_instance_valid(_player):
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	# Click the header to collapse/expand.
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if event.position.y <= HEADER_H:
			_collapsed = not _collapsed
			size.y = HEADER_H if _collapsed else EXPANDED_SIZE.y
			queue_redraw()
			accept_event()


## Fit transform {s, off}, preserving aspect (uniform scale). Vertical always fits
## the full height (letterboxed). Horizontally: short/normal maps are centered and
## shown whole, but a map too wide to read at full-width-fit is zoomed in (up to
## SCROLL_ZOOM×) and the view SCROLLS to follow the player, clamped to map edges —
## so a long level slides past instead of cramming into the box.
func _fit(body: Rect2) -> Dictionary:
	if _world_bounds.size.x <= 0 or _world_bounds.size.y <= 0:
		return {"s": 1.0, "off": body.position}
	var s_h: float = body.size.y / _world_bounds.size.y
	var s_w: float = body.size.x / _world_bounds.size.x
	var s: float = minf(minf(s_h, s_w * SCROLL_ZOOM), MAX_ZOOM)

	var off_y: float = body.position.y + (body.size.y - _world_bounds.size.y * s) * 0.5
	var content_w: float = _world_bounds.size.x * s
	var off_x: float
	if content_w <= body.size.x:
		off_x = body.position.x + (body.size.x - content_w) * 0.5
	else:
		var px: float = _world_bounds.position.x + _world_bounds.size.x * 0.5
		if is_instance_valid(_player) and _player is Node2D:
			px = (_player as Node2D).global_position.x
		var desired: float = body.position.x + body.size.x * 0.5 - (px - _world_bounds.position.x) * s
		off_x = clampf(desired, body.position.x + body.size.x - content_w, body.position.x)
	return {"s": s, "off": Vector2(off_x, off_y)}


## Map a world-space point into the minimap body using a fit (see _fit).
func _world_to_map(p: Vector2, fit: Dictionary) -> Vector2:
	return fit["off"] + (p - _world_bounds.position) * fit["s"]


func _draw() -> void:
	var full := Rect2(Vector2.ZERO, Vector2(size.x, HEADER_H if _collapsed else size.y))
	draw_rect(full, PANEL_BG, true)
	draw_rect(full, PANEL_BORDER, false, 1.0)
	# Header
	draw_rect(Rect2(0, 0, size.x, HEADER_H), Color(0, 0, 0, 0.35), true)
	if _font:
		draw_string(_font, Vector2(PAD, 14), _title if _title != "" else "Map",
			HORIZONTAL_ALIGNMENT_LEFT, size.x - PAD * 2, 12, Color.WHITE)
		draw_string(_font, Vector2(size.x - 16, 14), "–" if not _collapsed else "+",
			HORIZONTAL_ALIGNMENT_LEFT, 12, 12, Color(1, 1, 1, 0.7))
	if _collapsed:
		return

	var body := Rect2(PAD, HEADER_H + PAD, size.x - PAD * 2, size.y - HEADER_H - PAD * 2)
	var fit := _fit(body)

	# Terrain — surface cells drawn at the uniform scale so they stay to-scale.
	# Cull anything scrolled outside the body so it can't spill over the frame.
	var lo: float = body.position.x
	var hi: float = body.end.x
	if _terrain_world.size() > 0:
		var cell := _tile_size * float(fit["s"])
		cell.x = maxf(1.0, cell.x)
		cell.y = maxf(1.5, cell.y)
		for w in _terrain_world:
			var tp: Vector2 = _world_to_map(w, fit)
			if tp.x + cell.x < lo or tp.x > hi:
				continue
			draw_rect(Rect2(tp, cell), TERRAIN_COLOR, true)
	elif _world_bounds.size != Vector2.ZERO:
		draw_rect(body, Color(0.3, 0.35, 0.3, 0.35), false, 1.0)

	if not is_instance_valid(_map_instance):
		return

	# Portals (drawn beneath entities)
	for child in _map_instance.get_children():
		if child is Portal:
			var pp: Vector2 = _world_to_map((child as Node2D).global_position, fit)
			if pp.x < lo - 3.0 or pp.x > hi + 3.0:
				continue
			draw_rect(Rect2(pp - Vector2(3, 3), Vector2(6, 6)), PORTAL_COLOR, true)
			draw_rect(Rect2(pp - Vector2(3, 3), Vector2(6, 6)), Color(0, 0.3, 0.1, 0.9), false, 1.0)

	# Enemies (optional)
	if show_enemies:
		for e in get_tree().get_nodes_in_group("Enemies"):
			if not is_instance_valid(e) or not _map_instance.is_ancestor_of(e):
				continue
			var ep: Vector2 = _world_to_map((e as Node2D).global_position, fit)
			if ep.x < lo or ep.x > hi:
				continue
			draw_circle(ep - Vector2(0, ENTITY_LIFT), 2.0, ENEMY_COLOR)

	# Players / bots (local player drawn last, on top)
	var players_node: Node = _map_instance.get_node_or_null("Players")
	if players_node:
		for pl in players_node.get_children():
			if not (pl is Node2D) or not is_instance_valid(pl):
				continue
			if pl == _player:
				continue
			var col: Color = OTHER_COLOR
			var pid = pl.get("player_id")
			if typeof(pid) == TYPE_INT and pid < 0:
				col = BOT_COLOR
			var op: Vector2 = _world_to_map((pl as Node2D).global_position, fit) - Vector2(0, ENTITY_LIFT)
			if op.x < lo or op.x > hi:
				continue
			draw_circle(op, 2.5, col)

	if is_instance_valid(_player) and _player is Node2D:
		var me: Vector2 = _world_to_map((_player as Node2D).global_position, fit) - Vector2(0, ENTITY_LIFT)
		draw_circle(me, 4.0, PLAYER_COLOR)
		draw_circle(me, 4.0, Color(0.3, 0.25, 0.0, 1.0))
		draw_circle(me, 3.0, PLAYER_COLOR)
