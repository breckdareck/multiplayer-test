class_name EnemyMarkIndicator
extends Node2D

## Floating STATUS ROW above an enemy's head — one small code-drawn glyph per
## active status (marks, the weaken debuff, and the DoT/chill status tags),
## laid out in a centered horizontal strip. Purely cosmetic — the glyph list
## is driven by EnemyBase.sync_mark_indicator (a server→all-peers RPC) from
## the server's throttled status scan. The row bobs gently and pulses its
## alpha so it draws the eye without dominating the sprite.
##
## Layout control (the "boss with everything on it" case): the server caps
## the list at EnemyBase._MAX_STATUS_ICONS in priority order (marks first,
## then weaken, then DoTs) and appends an overflow count; this node renders
## whatever it's told plus a "+n" tail when overflow > 0. Glyphs never
## overlap — fixed SLOT_SPACING, row re-centers as statuses come and go.
##
## Glyph vocabulary (all code-drawn, no art assets — project convention):
##   "skull"     — Death Mark (red): death is coming
##   "crosshair" — Hunter's Mark (gold): hunted
##   "flag"      — Sentinel's Mark (blue): the vanguard's banner
##   "sparkle"   — Mana Resonance (purple): arcane charge
##   "weaken"    — attack-down (steel): downward sword, red strike-through
##   "droplet"   — Bleeding (red)
##   "bubbles"   — Poisoned (green)
##   "flame"     — Burning (orange)
##   "snowflake" — Chilled (ice blue)
##   "diamond"   — fallback for any unmapped status

const SIZE: float = 6.0
const SLOT_SPACING: float = 16.0
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED: float = 3.2
const PULSE_SPEED: float = 4.0
const OUTLINE_COLOR: Color = Color(0.05, 0.05, 0.08, 0.85)

var _shapes: PackedStringArray = PackedStringArray()
var _colors: PackedColorArray = PackedColorArray()
var _overflow: int = 0
var _t: float = 0.0
var _base_y: float = 0.0


func _ready() -> void:
	_base_y = position.y
	visible = false
	# Draw above most map elements but below UI.
	z_index = 50


func _process(delta: float) -> void:
	if not visible:
		return
	_t += delta
	# Bob: sinusoidal vertical offset around the authored base position.
	position.y = _base_y + sin(_t * BOB_SPEED) * BOB_AMPLITUDE
	# Pulse the redraw so the alpha shimmer animates.
	queue_redraw()


## Replace the whole row (called on every peer via the enemy's sync RPC).
## An empty list hides the row.
func set_statuses(shapes: PackedStringArray, colors: PackedColorArray, overflow: int = 0) -> void:
	_shapes = shapes
	_colors = colors
	_overflow = overflow
	visible = _shapes.size() > 0
	queue_redraw()


## Back-compat single-status setter (older call sites / debug).
func set_mark(color: Color, shape: String = "diamond") -> void:
	set_statuses(PackedStringArray([shape]), PackedColorArray([color]))


func clear_mark() -> void:
	set_statuses(PackedStringArray(), PackedColorArray())


func _draw() -> void:
	var n: int = _shapes.size()
	if n == 0:
		return
	# Alpha shimmer between ~0.65 and 1.0 so the row subtly pulses.
	var pulse: float = 0.825 + 0.175 * sin(_t * PULSE_SPEED)

	var slots: int = n + (1 if _overflow > 0 else 0)
	var start_x: float = -(float(slots - 1) * SLOT_SPACING) * 0.5
	for i in range(n):
		var c: Color = _colors[i] if i < _colors.size() else Color.WHITE
		var fill: Color = Color(c.r, c.g, c.b, c.a * pulse)
		draw_set_transform(Vector2(start_x + float(i) * SLOT_SPACING, 0.0))
		_draw_glyph(_shapes[i], fill, pulse)
	draw_set_transform(Vector2.ZERO)

	if _overflow > 0:
		var tail_x: float = start_x + float(slots - 1) * SLOT_SPACING
		var font := ThemeDB.fallback_font
		var text := "+%d" % _overflow
		draw_string(font, Vector2(tail_x - 6.0, 4.0), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
			Color(0.9, 0.92, 0.96, pulse))


func _draw_glyph(shape: String, fill: Color, pulse: float) -> void:
	match shape:
		"weaken":
			_draw_weaken(fill, pulse)
		"skull":
			_draw_skull(fill)
		"crosshair":
			_draw_crosshair(fill)
		"flag":
			_draw_flag(fill)
		"sparkle":
			_draw_sparkle(fill)
		"droplet":
			_draw_droplet(fill)
		"bubbles":
			_draw_bubbles(fill)
		"flame":
			_draw_flame(fill)
		"snowflake":
			_draw_snowflake(fill)
		_:
			_draw_diamond(fill)


func _draw_diamond(fill: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -SIZE), Vector2(SIZE, 0), Vector2(0, SIZE), Vector2(-SIZE, 0),
	])
	draw_colored_polygon(pts, fill)
	var loop: PackedVector2Array = PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(loop, OUTLINE_COLOR, 1.5)


## Attack-down: a steel sword pointing DOWN with a red strike-through.
func _draw_weaken(fill: Color, pulse: float) -> void:
	var s: float = SIZE * 1.25
	var guard_y: float = -s * 0.3
	var blade_w: float = 1.7
	var blade: PackedVector2Array = PackedVector2Array([
		Vector2(-blade_w, guard_y), Vector2(blade_w, guard_y),
		Vector2(blade_w, s - 2.0), Vector2(0, s + 1.5), Vector2(-blade_w, s - 2.0),
	])
	draw_colored_polygon(blade, fill)
	draw_line(Vector2(-s * 0.65, guard_y), Vector2(s * 0.65, guard_y), fill, 2.0)
	draw_line(Vector2(0, guard_y), Vector2(0, -s * 0.8), fill, 2.0)
	draw_circle(Vector2(0, -s * 0.9), 1.6, fill)
	var slash: Color = Color(0.95, 0.22, 0.18, 0.9 * pulse)
	draw_line(Vector2(-s, s * 0.85), Vector2(s, -s * 0.85), slash, 2.4)


## Death Mark: a small skull — round head, dark eye sockets, stubby jaw.
func _draw_skull(fill: Color) -> void:
	draw_circle(Vector2(0, -1.5), SIZE * 0.8, fill)
	draw_rect(Rect2(-SIZE * 0.45, 2.0, SIZE * 0.9, 3.0), fill)
	draw_circle(Vector2(-2.0, -2.0), 1.4, OUTLINE_COLOR)
	draw_circle(Vector2(2.0, -2.0), 1.4, OUTLINE_COLOR)
	draw_line(Vector2(0, 2.5), Vector2(0, 4.5), OUTLINE_COLOR, 1.0)


## Hunter's Mark: a crosshair — ring, four ticks, center dot.
func _draw_crosshair(fill: Color) -> void:
	draw_arc(Vector2.ZERO, SIZE * 0.75, 0.0, TAU, 20, fill, 1.8)
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(dir * SIZE * 0.45, dir * SIZE * 1.15, fill, 1.8)
	draw_circle(Vector2.ZERO, 1.3, fill)


## Sentinel's Mark: the vanguard's banner — pole + triangular pennant.
func _draw_flag(fill: Color) -> void:
	draw_line(Vector2(-2.5, SIZE), Vector2(-2.5, -SIZE), fill, 1.8)
	var pennant: PackedVector2Array = PackedVector2Array([
		Vector2(-2.5, -SIZE), Vector2(SIZE, -SIZE * 0.45), Vector2(-2.5, 1.0),
	])
	draw_colored_polygon(pennant, fill)


## Mana Resonance: a four-point arcane sparkle.
func _draw_sparkle(fill: Color) -> void:
	var lon: float = SIZE * 1.1
	var lat: float = SIZE * 0.32
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -lon), Vector2(lat, -lat), Vector2(lon, 0), Vector2(lat, lat),
		Vector2(0, lon), Vector2(-lat, lat), Vector2(-lon, 0), Vector2(-lat, -lat),
	])
	draw_colored_polygon(pts, fill)


## Bleeding: a blood droplet — pointed top, round belly.
func _draw_droplet(fill: Color) -> void:
	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -SIZE),
		Vector2(SIZE * 0.55, -0.5), Vector2(SIZE * 0.62, 2.2), Vector2(0, SIZE * 0.75),
		Vector2(-SIZE * 0.62, 2.2), Vector2(-SIZE * 0.55, -0.5),
	])
	draw_colored_polygon(pts, fill)
	draw_circle(Vector2(0, 1.8), SIZE * 0.58, fill)


## Poisoned: rising toxin bubbles, large to small.
func _draw_bubbles(fill: Color) -> void:
	draw_circle(Vector2(-1.5, 2.0), 3.0, fill)
	draw_circle(Vector2(2.8, -1.0), 2.1, fill)
	draw_circle(Vector2(-0.5, -4.5), 1.3, fill)


## Burning: a flame — outer tongue in the status color, hot inner core.
func _draw_flame(fill: Color) -> void:
	var outer: PackedVector2Array = PackedVector2Array([
		Vector2(0, -SIZE * 1.1), Vector2(2.2, -2.0), Vector2(SIZE * 0.7, 0.5),
		Vector2(SIZE * 0.55, 3.2), Vector2(0, SIZE * 0.85),
		Vector2(-SIZE * 0.55, 3.2), Vector2(-SIZE * 0.7, 0.5), Vector2(-1.2, -2.5),
	])
	draw_colored_polygon(outer, fill)
	var core: Color = Color(1.0, 0.92, 0.55, fill.a)
	draw_circle(Vector2(0, 2.2), SIZE * 0.38, core)


## Chilled: a six-spoke snowflake.
func _draw_snowflake(fill: Color) -> void:
	for k in range(3):
		var ang: float = float(k) * PI / 3.0
		var v: Vector2 = Vector2(cos(ang), sin(ang)) * SIZE
		draw_line(-v, v, fill, 1.6)
	draw_circle(Vector2.ZERO, 1.4, fill)
