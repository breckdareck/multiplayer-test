extends RefCounted

## A walkable-surface graph for one map, used for bot platformer pathfinding.
##
## Surfaces are discovered by raycast-probing the *live* physics world, so the
## graph works uniformly across TileMaps, one-way platforms and StaticBody2Ds
## without parsing any tileset data. Edges model how a bot can move between
## surfaces — walk, jump-up, drop-down, gap-jump — and jump edges are gated by
## the bot's real jump reach.
##
## Build once per map (physics must be live), then call find_path(). This is
## stage 1 of the platform-graph navigation work: the graph + A* exist and are
## inspectable via `/bot navgraph`, but are not yet wired into bot movement.

const GROUND_MASK: int = 0b101  ## World + Platforms — mirrors bot_brain.

const CELL: float = 16.0            ## Probe / cluster resolution (one tile).
const Y_TOLERANCE: float = 6.0      ## Max Y diff for adjacent columns to share a surface.
const STAND_EPS: float = 3.0        ## Ray must clear this much air before a hit is a surface.
const POINT_SPACING: float = 40.0   ## Graph points placed along a surface this far apart.
const MAX_LINK_DIST: float = 220.0  ## Point pairs farther apart than this are never linked.
const DROP_DX: float = 30.0         ## Max horizontal drift tolerated for a straight drop edge.
const MAX_COLUMN_ITERS: int = 400   ## Defensive cap on the per-column probe loop.

enum EdgeKind { WALK, JUMP, DROP, GAP }

var bounds: Rect2
var segments: Array[Dictionary] = []         ## Each: {y, x_min, x_max, last_col}
var points: PackedVector2Array = PackedVector2Array()
var point_segment: PackedInt32Array = PackedInt32Array()
var edges: Dictionary = {}                   ## Vector2i(from_id, to_id) -> EdgeKind
var astar: AStar2D = AStar2D.new()
var built: bool = false

var _max_jump_height: float = 40.0
var _jump_reach: float = 40.0


## Builds the graph for a live map node. `max_jump_height` and `jump_reach` are
## the bot's vertical and horizontal jump limits (see bot_brain). Returns false
## if the map has no live physics world.
func build(map_node: Node2D, max_jump_height: float, jump_reach: float) -> bool:
	built = false
	astar.clear()
	segments.clear()
	points = PackedVector2Array()
	point_segment = PackedInt32Array()
	edges.clear()

	if not is_instance_valid(map_node):
		return false
	var world := map_node.get_world_2d()
	if world == null:
		return false

	_max_jump_height = max_jump_height
	_jump_reach = jump_reach
	bounds = _compute_bounds(map_node)

	var columns := _probe_columns(world.direct_space_state)
	segments = _cluster_segments(columns)
	_place_points()
	_build_edges()
	built = true
	return true


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


## The EdgeKind for a directed edge, or -1 if the two points aren't connected
## that way. Stage 2's navigator uses this to know when to jump vs walk.
func edge_kind(from_id: int, to_id: int) -> int:
	return edges.get(Vector2i(from_id, to_id), -1)


## Summary counts for debug inspection.
func get_stats() -> Dictionary:
	var kinds := {EdgeKind.WALK: 0, EdgeKind.JUMP: 0, EdgeKind.DROP: 0, EdgeKind.GAP: 0}
	for k in edges.values():
		kinds[k] += 1
	return {
		"built": built,
		"bounds": bounds,
		"segments": segments.size(),
		"points": points.size(),
		"edges": edges.size(),
		"walk": kinds[EdgeKind.WALK],
		"jump": kinds[EdgeKind.JUMP],
		"drop": kinds[EdgeKind.DROP],
		"gap": kinds[EdgeKind.GAP],
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

func _probe_columns(space: PhysicsDirectSpaceState2D) -> Array:
	var result: Array = []
	var col_count := int(bounds.size.x / CELL)
	for c in range(col_count):
		var x := bounds.position.x + c * CELL + CELL * 0.5
		result.append(_probe_one_column(space, x))
	return result


## Casts repeated downward rays through one column, recording the top of every
## standable surface (a collider with open air above it).
func _probe_one_column(space: PhysicsDirectSpaceState2D, x: float) -> PackedFloat32Array:
	var ys := PackedFloat32Array()
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
		if hit_y - y >= STAND_EPS:
			# The ray crossed open air before hitting — top of a standable surface.
			ys.append(hit_y)
			y = hit_y + 2.0      # step just past the surface to find the next one
		else:
			# Started inside / flush against solid — skip a tile and retry.
			y = hit_y + CELL
	return ys


## Sweeps columns left to right, joining surface hits at a consistent Y into
## horizontal segments.
func _cluster_segments(columns: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var open: Array[Dictionary] = []
	for c in range(columns.size()):
		var col_x := bounds.position.x + c * CELL + CELL * 0.5
		var ys: PackedFloat32Array = columns[c]
		var matched := {}
		for sy in ys:
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
				open.append({"y": sy, "x_min": col_x, "x_max": col_x, "last_col": c})
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
		var x: float = seg.x_min
		while x < seg.x_max:
			_add_point(Vector2(x, seg.y), si)
			x += POINT_SPACING
		_add_point(Vector2(seg.x_max, seg.y), si)


func _add_point(pos: Vector2, seg_index: int) -> void:
	var id := points.size()
	points.append(pos)
	point_segment.append(seg_index)
	astar.add_point(id, pos)


func _build_edges() -> void:
	# Walk edges: consecutive points on the same segment.
	for i in range(1, points.size()):
		if point_segment[i] == point_segment[i - 1]:
			_connect(i - 1, i, EdgeKind.WALK, true)

	# Inter-segment edges: jump-up, drop-down, gap-jump.
	for i in range(points.size()):
		var pa: Vector2 = points[i]
		var nearest_drop := -1
		var nearest_drop_dy := INF
		for j in range(points.size()):
			if i == j or point_segment[i] == point_segment[j]:
				continue
			var pb: Vector2 = points[j]
			if pa.distance_to(pb) > MAX_LINK_DIST:
				continue
			var dx: float = absf(pb.x - pa.x)
			var dy: float = pa.y - pb.y      # > 0 => b is above a
			if dy > 2.0:
				if dy <= _max_jump_height and dx <= _jump_reach:
					_connect(i, j, EdgeKind.JUMP, false)
			elif dy < -2.0:
				# Keep only the nearest surface directly below — that's where a
				# straight drop actually lands.
				if dx <= DROP_DX and -dy < nearest_drop_dy:
					nearest_drop_dy = -dy
					nearest_drop = j
			else:
				if dx > CELL and dx <= _jump_reach * 2.0:
					_connect(i, j, EdgeKind.GAP, true)
		if nearest_drop >= 0:
			_connect(i, nearest_drop, EdgeKind.DROP, false)


func _connect(a: int, b: int, kind: int, bidirectional: bool) -> void:
	if not astar.are_points_connected(a, b):
		astar.connect_points(a, b, bidirectional)
	edges[Vector2i(a, b)] = kind
	if bidirectional:
		edges[Vector2i(b, a)] = kind
