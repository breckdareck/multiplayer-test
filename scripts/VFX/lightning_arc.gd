extends Node2D

## Transient chain-lightning VFX: a jagged bolt threaded through a series of world
## points (the struck target + each chained enemy), crackling and fading over a
## fraction of a second, then self-freeing.
##
## Purely cosmetic and CLIENT-SIDE. It is spawned per-peer by MapManager
## (broadcast_lightning_arc / client_show_lightning_arc -> _spawn_lightning_arc_visual)
## UNDER the visible map instance so it renders in the correct SubViewport — a
## Node2D under a /root autoload would draw into the camera-less root viewport and
## land off-screen (see the world-space-overlay note in the project memory). The
## authoritative chain DAMAGE is applied server-side by StaffElementComponent; this
## node never touches gameplay state.
##
## Points are stored in GLOBAL space and converted with to_local() at draw time, so
## the bolt lands correctly regardless of the map node's own transform.

const DURATION: float = 0.28              ## total lifetime in seconds
const REJAG_INTERVAL: float = 0.06        ## how often to re-randomize the jag (crackle)
const SEGMENTS_PER_ARC: int = 6           ## subdivisions of each enemy->enemy bolt
const JAGGED_AMPLITUDE: float = 14.0      ## max perpendicular jitter per inner point (px)
const CORE_COLOR: Color = Color(1.0, 0.96, 0.5)     ## bright yellow-white core
const GLOW_COLOR: Color = Color(0.5, 0.8, 1.0, 0.5) ## cool bluish glow underlay
const CORE_WIDTH: float = 2.0
const GLOW_WIDTH: float = 6.0

## Ordered GLOBAL anchor points the bolt threads through (target, then chained).
var _anchors: PackedVector2Array = PackedVector2Array()
## One jagged GLOBAL polyline per consecutive anchor pair; rebuilt for the crackle.
var _bolts: Array = []
var _elapsed: float = 0.0
var _rejag_accum: float = 0.0


## Called by MapManager right after the node is added under the map. `points` are
## global positions: the struck target first, then each chained enemy in order.
func setup(points: PackedVector2Array) -> void:
	_anchors = points
	_rebuild_bolts()
	queue_redraw()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	# Re-randomize the jag a few times across the lifetime so the bolt crackles
	# instead of sitting as a static zig-zag.
	_rejag_accum += delta
	if _rejag_accum >= REJAG_INTERVAL:
		_rejag_accum = 0.0
		_rebuild_bolts()
	queue_redraw()


func _draw() -> void:
	var alpha: float = 1.0 - (_elapsed / DURATION)
	var core: Color = CORE_COLOR
	core.a *= alpha
	var glow: Color = GLOW_COLOR
	glow.a *= alpha
	for bolt in _bolts:
		if bolt.size() < 2:
			continue
		# Convert the global polyline into this node's local space at draw time.
		var local_pts: PackedVector2Array = PackedVector2Array()
		for p in bolt:
			local_pts.append(to_local(p))
		draw_polyline(local_pts, glow, GLOW_WIDTH, true)
		draw_polyline(local_pts, core, CORE_WIDTH, true)


func _rebuild_bolts() -> void:
	_bolts.clear()
	for i in range(_anchors.size() - 1):
		_bolts.append(_make_bolt(_anchors[i], _anchors[i + 1]))


## Builds a jagged polyline (global space) from `from` to `to`: even subdivisions
## with random perpendicular jitter on the interior points, endpoints pinned.
func _make_bolt(from: Vector2, to: Vector2) -> PackedVector2Array:
	var pts: PackedVector2Array = PackedVector2Array()
	var perp: Vector2 = (to - from).orthogonal().normalized()
	for i in range(SEGMENTS_PER_ARC + 1):
		var t: float = float(i) / float(SEGMENTS_PER_ARC)
		var point: Vector2 = from.lerp(to, t)
		if i != 0 and i != SEGMENTS_PER_ARC:
			point += perp * randf_range(-JAGGED_AMPLITUDE, JAGGED_AMPLITUDE)
		pts.append(point)
	return pts
