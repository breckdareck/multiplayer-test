extends RefCounted

## A walkable-surface graph for one map, used for bot platformer pathfinding.
##
## Surfaces are discovered by raycast-probing the *live* physics world, so the
## graph works uniformly across TileMaps, one-way platforms and StaticBody2Ds
## without parsing any tileset data. Each surface is classified solid or
## one-way. Edges model how a bot can move between surfaces — walk, jump-up,
## drop-down, gap-jump — gated by the bot's real jump reach and by where a drop
## is actually possible (a solid surface's ledges, or anywhere on a one-way
## platform).
##
## Build incrementally (begin_build + build_step) while physics is live, then
## call find_path() / find_id_path().

const GROUND_MASK: int = 0b101  ## World + Platforms — mirrors bot_brain.
const WORLD_MASK: int = 0b001   ## Solid world only — excludes one-way platforms.

const CELL: float = 16.0            ## Probe / cluster resolution (one tile).
const Y_TOLERANCE: float = 6.0      ## Max Y diff for adjacent columns to share a surface.
const AIR_GAP_CHECK: float = 6.0    ## A surface hit only counts if this much space above it is clear.
const SOLID_PROBE_DEPTH: float = 2.0 ## How far below a surface top to sample when classifying it.
const POINT_SPACING: float = 40.0   ## Graph points placed along a surface this far apart.
const MAX_LINK_DIST: float = 220.0  ## Point pairs farther apart than this are never linked.
## Max horizontal drift tolerated for a drop edge. A bot in free-fall drifts
## move_speed * fall_time horizontally; for a typical 200 px fall, drift is
## ~80 px. 30 px (the previous value) restricted drops to nearly-straight-down
## and made the graph prefer tiny offset platforms over the wide ground floor
## directly under a ledge — bots ended up trying to land on shelf platforms
## they couldn't physically reach.
const DROP_DX: float = 80.0
## Max vertical fall (px) a DROP edge may span. Unlike jumps/gaps (bounded by
## MAX_LINK_DIST), a bot can fall an arbitrary height, so drops get a far larger
## cap — without it, MAX_LINK_DIST (220) split maps into disconnected islands the
## bot couldn't descend between (lower platforms 250-700px below were unreachable).
const DROP_MAX_FALL: float = 800.0
const MAX_COLUMN_ITERS: int = 400   ## Defensive cap on the per-column probe loop.

enum EdgeKind { WALK, JUMP, DROP, GAP, CLIMB }

## Horizontal tolerance (px) for matching a ladder's column to a surface's x-span
## and to a graph point — a ladder connects a surface if its x falls within the
## surface's extent (plus this slack) and there's a point near that column.
const LADDER_X_TOL: float = 24.0
## Vertical reach (px) added when matching surfaces to a ladder column. ASYMMETRIC
## on purpose: the bot can MOUNT from a platform up to ~a jump below the zone
## bottom (it hops up into the zone), but it can NOT climb past the zone TOP — the
## climb ends there — so only a platform flush at/just above the top counts.
## A symmetric reach connected platforms far ABOVE the rope's top that the bot
## could never reach, leaving it jumping at a phantom connector forever.
const LADDER_ABOVE_REACH: float = 16.0   ## ~one tile: a platform flush at the zone top.
## Below-the-zone reach (the mount hop) is jump-height + a tile of body overlap,
## computed per build from the bot's real jump in _build_ladder_edges.

var bounds: Rect2
var segments: Array[Dictionary] = []         ## Each: {y, x_min, x_max, last_col, one_way}
var points: PackedVector2Array = PackedVector2Array()
var point_segment: PackedInt32Array = PackedInt32Array()
var point_is_ledge: PackedByteArray = PackedByteArray()  ## 1 at a segment's end points.
var edges: Dictionary = {}                   ## Vector2i(from_id, to_id) -> EdgeKind
## Each detected ladder/rope column: {x, top, bottom} world coords. Stored so the
## debug overlay can show that the graph actually picked up the ladders.
var ladder_zones: Array[Dictionary] = []
var astar: AStar2D = AStar2D.new()
var built: bool = false

var _max_jump_height: float = 40.0
var _jump_reach: float = 40.0

# Incremental build state. Surface probing fires thousands of raycasts, so it
# is spread across frames (build_step) to avoid a one-frame hitch.
var _building: bool = false
var _build_map_node: Node2D = null
var _build_col_total: int = 0
var _build_col_index: int = 0
var _build_columns: Array = []


## Starts an incremental build for a live map node. `max_jump_height` and
## `jump_reach` are the bot's jump limits (see bot_brain). Returns false if the
## map has no live physics world. Drive it with build_step() until `built`.
func begin_build(map_node: Node2D, max_jump_height: float, jump_reach: float) -> bool:
	built = false
	_building = false
	astar.clear()
	segments.clear()
	points = PackedVector2Array()
	point_segment = PackedInt32Array()
	point_is_ledge = PackedByteArray()
	edges.clear()
	ladder_zones.clear()
	_build_columns = []
	_build_col_index = 0

	if not is_instance_valid(map_node) or map_node.get_world_2d() == null:
		return false

	_max_jump_height = max_jump_height
	_jump_reach = jump_reach
	_build_map_node = map_node
	bounds = _compute_bounds(map_node)
	_build_col_total = int(bounds.size.x / CELL)
	_building = true
	return true


## Advances an in-progress build by up to `max_columns` probe columns. Sets
## `built` once finished. Aborts cleanly (leaving built = false) if the map was
## freed mid-build.
func build_step(max_columns: int) -> void:
	if not _building:
		return
	if not is_instance_valid(_build_map_node) or _build_map_node.get_world_2d() == null:
		_building = false
		_build_map_node = null
		return
	var space := _build_map_node.get_world_2d().direct_space_state

	var end_col := mini(_build_col_index + max_columns, _build_col_total)
	while _build_col_index < end_col:
		var x := bounds.position.x + _build_col_index * CELL + CELL * 0.5
		_build_columns.append(_probe_one_column(space, x))
		_build_col_index += 1

	if _build_col_index >= _build_col_total:
		# All columns probed — finish: cluster, place points, link edges.
		segments = _cluster_segments(_build_columns)
		_place_points()
		_build_edges()
		_build_columns = []
		_build_map_node = null
		_building = false
		built = true


## Whether an incremental build is still running.
func is_building() -> bool:
	return _building


## Synchronous full build — used by debug tooling (`/bot navgraph`). Gameplay
## uses begin_build + build_step to spread the probe cost across frames.
func build(map_node: Node2D, max_jump_height: float, jump_reach: float) -> bool:
	if not begin_build(map_node, max_jump_height, jump_reach):
		return false
	while _building:
		build_step(_build_col_total)
	return built


## Returns a waypoint path (world positions) from `from` to `to`, snapping each
## endpoint to its nearest graph point. Empty if no path exists.
func find_path(from: Vector2, to: Vector2) -> PackedVector2Array:
	if not built or astar.get_point_count() == 0:
		return PackedVector2Array()
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	if a < 0 or b < 0:
		return PackedVector2Array()
	return astar.get_point_path(a, b)


## Like find_path but returns the A* point IDs rather than positions, so a
## caller can walk the path and query each hop's edge kind / position.
func find_id_path(from: Vector2, to: Vector2) -> PackedInt64Array:
	if not built or astar.get_point_count() == 0:
		return PackedInt64Array()
	var a := astar.get_closest_point(from)
	var b := astar.get_closest_point(to)
	if a < 0 or b < 0:
		return PackedInt64Array()
	return astar.get_id_path(a, b)


## World position of a graph point.
func point_position(id: int) -> Vector2:
	return astar.get_point_position(id)


## Whether a point ID still exists in this graph (guards against stale IDs
## held across a map change).
func has_point(id: int) -> bool:
	return astar.has_point(id)


## The EdgeKind for a directed edge, or -1 if the two points aren't connected
## that way. The navigator uses this to know when to jump vs walk.
func edge_kind(from_id: int, to_id: int) -> int:
	return edges.get(Vector2i(from_id, to_id), -1)


## Summary counts for debug inspection.
func get_stats() -> Dictionary:
	var kinds := {EdgeKind.WALK: 0, EdgeKind.JUMP: 0, EdgeKind.DROP: 0, EdgeKind.GAP: 0, EdgeKind.CLIMB: 0}
	for k in edges.values():
		kinds[k] += 1
	var one_way_segs := 0
	for seg in segments:
		if seg.one_way:
			one_way_segs += 1
	return {
		"built": built,
		"bounds": bounds,
		"segments": segments.size(),
		"one_way_segments": one_way_segs,
		"points": points.size(),
		"edges": edges.size(),
		"walk": kinds[EdgeKind.WALK],
		"jump": kinds[EdgeKind.JUMP],
		"drop": kinds[EdgeKind.DROP],
		"gap": kinds[EdgeKind.GAP],
		"climb": kinds[EdgeKind.CLIMB],
	}


# --- Bounds -----------------------------------------------------------------

func _compute_bounds(map_node: Node) -> Rect2:
	var rect := Rect2()
	var found := false
	for layer in _find_tilemap_layers(map_node):
		var used: Rect2i = layer.get_used_rect()
		if used.size.x <= 0 or used.size.y <= 0:
			continue
		var tile_size := Vector2(CELL, CELL)
		if layer.tile_set != null:
			tile_size = Vector2(layer.tile_set.tile_size)
		var world_rect := Rect2(
			Vector2(used.position) * tile_size,
			Vector2(used.size) * tile_size)
		world_rect.position += layer.global_position
		if not found:
			rect = world_rect
			found = true
		else:
			rect = rect.merge(world_rect)
	if not found:
		# No tilemap found — fall back to a generous box around the origin.
		rect = Rect2(-2500, -1200, 5000, 2400)
	return rect.grow(CELL * 2.0)


func _find_tilemap_layers(node: Node) -> Array:
	var out: Array = []
	if node is TileMapLayer:
		out.append(node)
	for child in node.get_children():
		out.append_array(_find_tilemap_layers(child))
	return out


# --- Surface probing --------------------------------------------------------

## Casts repeated downward rays through one column, recording each standable
## surface: its top Y and whether it is a one-way platform (vs solid ground).
## Returns an Array of {y: float, one_way: bool}.
func _probe_one_column(space: PhysicsDirectSpaceState2D, x: float) -> Array:
	var surfaces: Array = []
	var bottom := bounds.position.y + bounds.size.y
	var y := bounds.position.y
	var iters := 0
	while y < bottom and iters < MAX_COLUMN_ITERS:
		iters += 1
		var q := PhysicsRayQueryParameters2D.create(Vector2(x, y), Vector2(x, bottom), GROUND_MASK)
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			break
		var hit_y: float = hit.position.y
		# A ray starting inside stacked solid tiles still "hits" every internal
		# tile boundary below it. A genuine standable surface has clear air just
		# above it — verify that, rejecting internal boundaries.
		if not _point_solid(space, Vector2(x, hit_y - AIR_GAP_CHECK), GROUND_MASK):
			# Classify: solid world geometry just under the top, or a one-way
			# platform (something on the Platforms layer but not on World).
			var solid := _point_solid(space, Vector2(x, hit_y + SOLID_PROBE_DEPTH), WORLD_MASK)
			surfaces.append({"y": hit_y, "one_way": not solid})
		y = hit_y + 2.0      # nudge past this hit and keep scanning down
	return surfaces


## True if a point lies inside collision geometry on `mask`.
func _point_solid(space: PhysicsDirectSpaceState2D, p: Vector2, mask: int) -> bool:
	var q := PhysicsPointQueryParameters2D.new()
	q.position = p
	q.collision_mask = mask
	q.collide_with_areas = false
	q.collide_with_bodies = true
	return not space.intersect_point(q, 1).is_empty()


## Sweeps columns left to right, joining surface hits at a consistent Y into
## horizontal segments. A segment inherits the one-way flag of its first hit.
func _cluster_segments(columns: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var open: Array[Dictionary] = []
	for c in range(columns.size()):
		var col_x := bounds.position.x + c * CELL + CELL * 0.5
		var surfaces: Array = columns[c]
		var matched := {}
		for surf in surfaces:
			var sy: float = surf.y
			var best := -1
			var best_d := Y_TOLERANCE
			for oi in range(open.size()):
				if matched.has(oi):
					continue
				var seg: Dictionary = open[oi]
				if seg.last_col != c - 1:
					continue
				var d: float = absf(seg.y - sy)
				if d <= best_d:
					best_d = d
					best = oi
			if best >= 0:
				open[best].x_max = col_x
				open[best].y = (open[best].y + sy) * 0.5
				open[best].last_col = c
				matched[best] = true
			else:
				open.append({"y": sy, "x_min": col_x, "x_max": col_x,
					"last_col": c, "one_way": surf.one_way})
		# Close any segment that wasn't extended into this column.
		var still_open: Array[Dictionary] = []
		for seg in open:
			if seg.last_col == c:
				still_open.append(seg)
			else:
				result.append(seg)
		open = still_open
	for seg in open:
		result.append(seg)
	return result


# --- Graph construction -----------------------------------------------------

func _place_points() -> void:
	for si in range(segments.size()):
		var seg := segments[si]
		var first_id := points.size()
		var x: float = seg.x_min
		while x < seg.x_max:
			_add_point(Vector2(x, seg.y), si)
			x += POINT_SPACING
		_add_point(Vector2(seg.x_max, seg.y), si)
		# The segment's two end points are its ledges.
		point_is_ledge[first_id] = 1
		point_is_ledge[points.size() - 1] = 1


func _add_point(pos: Vector2, seg_index: int) -> void:
	var id := points.size()
	points.append(pos)
	point_segment.append(seg_index)
	point_is_ledge.append(0)
	astar.add_point(id, pos)


## Whether a bot can descend from a point: off a solid surface only at its
## ledges (segment ends), but anywhere on a one-way platform (drops through).
func _can_drop_from(point_id: int) -> bool:
	if point_is_ledge[point_id] == 1:
		return true
	return bool(segments[point_segment[point_id]].one_way)


func _build_edges() -> void:
	# Walk edges: consecutive points on the same segment.
	for i in range(1, points.size()):
		if point_segment[i] == point_segment[i - 1]:
			_connect(i - 1, i, EdgeKind.WALK, true)

	# Inter-segment edges: jump-up, drop-down, gap-jump.
	for i in range(points.size()):
		var pa: Vector2 = points[i]
		var can_drop := _can_drop_from(i)
		# Track the nearest drop landing on each side of the source — left
		# (dx ≤ 0) and right (dx ≥ 0). Connecting only the single nearest by
		# dy makes the graph prefer tiny shelf platforms one tile beneath a
		# ledge over the much wider main-ground floor a bit further down on
		# the other side. With both sides exposed, A* picks based on overall
		# path cost (Euclidean), which naturally favors the wide floor.
		var drop_left := -1
		var drop_left_dy := INF
		var drop_right := -1
		var drop_right_dy := INF
		for j in range(points.size()):
			if i == j or point_segment[i] == point_segment[j]:
				continue
			var pb: Vector2 = points[j]
			# Coarse cap = the largest any edge can be (a long fall). JUMP/GAP are
			# bound far tighter by their own dx/dy limits below; only DROP uses the
			# full range, so the old blanket MAX_LINK_DIST here was really a drop cap
			# that wrongly islanded the map.
			if pa.distance_to(pb) > DROP_MAX_FALL:
				continue
			var raw_dx: float = pb.x - pa.x
			var dx: float = absf(raw_dx)
			var dy: float = pa.y - pb.y      # > 0 => b is above a
			if dy > 2.0:
				if pa.distance_to(pb) > MAX_LINK_DIST:
					continue
				# Horizontal reach of a jump shrinks as it gains height (you trade
				# distance for altitude): full _jump_reach for a low step, down to
				# the rise-only half near max height. A flat reach would claim
				# impossible far-and-high hops; this scaled bound still admits the
				# diagonal up-edges a zigzag staircase needs.
				var height_frac: float = clampf(dy / maxf(_max_jump_height, 1.0), 0.0, 1.0)
				var horiz_limit: float = lerpf(_jump_reach, _jump_reach * 0.5, height_frac)
				if dy <= _max_jump_height and dx <= horiz_limit and _jump_path_clear(pa, pb):
					_connect(i, j, EdgeKind.JUMP, false)
			elif dy < -2.0:
				# A drop is only valid where the bot can actually leave the
				# surface — a solid ledge, or anywhere on a one-way platform —
				# AND the path between source and destination is unobstructed.
				# Without the path-clear check, A* happily picks DROP edges
				# that cut across solid terrain (e.g. straight across a
				# triangle-shaped staircase) and the bot tries to execute them
				# by walking into the side of the obstacle.
				if not can_drop or dx > DROP_DX:
					continue
				if not _jump_path_clear(pa, pb):
					continue
				if raw_dx >= 0.0 and -dy < drop_right_dy:
					drop_right_dy = -dy
					drop_right = j
				if raw_dx <= 0.0 and -dy < drop_left_dy:
					drop_left_dy = -dy
					drop_left = j
			else:
				# GAP = same-level hop across a pit. _jump_reach is now the FULL
				# flat-jump distance, so cap at it directly (the old *2.0 doubled a
				# rise-only under-estimate that happened to land near one flat jump).
				if dx > CELL and dx <= _jump_reach and _jump_path_clear(pa, pb):
					_connect(i, j, EdgeKind.GAP, true)
		if drop_left >= 0:
			_connect(i, drop_left, EdgeKind.DROP, false)
		if drop_right >= 0 and drop_right != drop_left:
			_connect(i, drop_right, EdgeKind.DROP, false)

	# Vertical CLIMB edges along ladders/ropes — the maps' intended way up/down
	# between platforms too far apart to jump.
	_build_ladder_edges()


## Connects the surfaces a ladder/rope spans with bidirectional CLIMB edges, so
## A* can route a bot up or down it. For each ladder we take the graph point
## nearest the ladder's column on every surface that falls within its vertical
## extent, sort them by height, and link adjacent levels — climbing one gap per
## edge (which is how these maps stack their ladders).
func _build_ladder_edges() -> void:
	if not is_instance_valid(_build_map_node):
		return
	var ladders: Array = []
	_collect_ladders(_build_map_node, ladders)
	# How far below the zone bottom a platform can be and still be mounted: the bot
	# hops up _max_jump_height and its body (~one tile) overlaps into the zone.
	var below_reach: float = _max_jump_height + CELL
	for ladder in ladders:
		var ext: Dictionary = _ladder_extent(ladder)
		if ext.is_empty():
			continue
		ladder_zones.append(ext)   # record for the debug overlay
		var lx: float = ext.x
		var level_points: Array = []   # [{y, id}]
		for seg_i in range(segments.size()):
			var seg: Dictionary = segments[seg_i]
			# Asymmetric: a platform up to `below_reach` BELOW the zone bottom can be
			# mounted (hop into the zone); ABOVE the zone top only a flush platform
			# counts (the climb can't go past the top). x-extent must include the
			# column. (y grows downward: ext.top is the higher edge.)
			if seg.y < ext.top - LADDER_ABOVE_REACH or seg.y > ext.bottom + below_reach:
				continue
			if lx < seg.x_min - LADDER_X_TOL or lx > seg.x_max + LADDER_X_TOL:
				continue
			var pid: int = _nearest_point_on_segment(seg_i, lx)
			if pid >= 0 and absf(points[pid].x - lx) <= POINT_SPACING:
				level_points.append({"y": seg.y, "id": pid})
		level_points.sort_custom(func(a, b): return a.y < b.y)
		for k in range(1, level_points.size()):
			_connect(level_points[k - 1].id, level_points[k].id, EdgeKind.CLIMB, true)


## Recursively gathers Ladder-scripted Area2Ds (ladders and ropes share ladder.gd)
## under a map node.
func _collect_ladders(node: Node, out: Array) -> void:
	if node is Area2D and node.get_script() != null \
			and String(node.get_script().resource_path).ends_with("ladder.gd"):
		out.append(node)
	for c in node.get_children():
		_collect_ladders(c, out)


## A ladder's column x and vertical world extent, from its RectangleShape2D.
## Returns {} if it has no usable collision shape.
func _ladder_extent(ladder: Node) -> Dictionary:
	for c in ladder.get_children():
		if c is CollisionShape2D and (c as CollisionShape2D).shape is RectangleShape2D:
			var cs := c as CollisionShape2D
			var half_h: float = (cs.shape as RectangleShape2D).size.y * 0.5 * absf(cs.global_scale.y)
			var cy: float = cs.global_position.y
			return {"x": (ladder as Node2D).global_position.x, "top": cy - half_h, "bottom": cy + half_h}
	return {}


## Graph point on a given segment closest to a column x, or -1 if the segment has
## no points.
func _nearest_point_on_segment(seg_i: int, x: float) -> int:
	var best := -1
	var best_dx := INF
	for i in range(points.size()):
		if point_segment[i] != seg_i:
			continue
		var d: float = absf(points[i].x - x)
		if d < best_dx:
			best_dx = d
			best = i
	return best


## Whether a jump/gap edge between two points is unobstructed. Rejects an edge
## when solid world geometry sits between the points — a ceiling or wall the bot
## would bonk into. Solid hits right at the destination are its own platform and
## don't count; one-way platforms never block (the bot passes through them).
func _jump_path_clear(a: Vector2, b: Vector2) -> bool:
	if not is_instance_valid(_build_map_node) or _build_map_node.get_world_2d() == null:
		return true  # can't verify — don't prune the edge
	var space := _build_map_node.get_world_2d().direct_space_state
	var q := PhysicsRayQueryParameters2D.create(a, b, WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return true
	return hit.position.distance_to(b) <= CELL


func _connect(a: int, b: int, kind: int, bidirectional: bool) -> void:
	if not astar.are_points_connected(a, b):
		astar.connect_points(a, b, bidirectional)
	edges[Vector2i(a, b)] = kind
	if bidirectional:
		edges[Vector2i(b, a)] = kind
