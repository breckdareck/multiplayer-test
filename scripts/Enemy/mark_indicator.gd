class_name EnemyMarkIndicator
extends Node2D

## A small floating glyph drawn above a marked enemy's head, color-coded by
## the mark type that tagged it (Death Mark / Mark of the Hunt / Sentinel's
## Mark / Mana Surge). Purely cosmetic — visibility, color, and SHAPE are
## driven by EnemyBase.sync_mark_indicator (a server→all-peers RPC). The
## glyph bobs gently for a "floating" read and pulses its alpha so it draws
## the eye.
##
## Self-contained custom-drawn marker (no art asset needed). Two shapes:
##   "diamond" — the classic mark glyph (filled diamond, dark outline)
##   "weaken"  — a downward-pointing sword with a red slash through it,
##               the ATTACK-DOWN debuff tell (Challenging Shout / Choking
##               Smoke / Suppressing Fire). Weapon + strike-through + the
##               downward point all read "this enemy hits softer".
## Created dynamically by EnemyBase._ready on every peer so the RPC has a
## node to toggle.

const SIZE: float = 6.0
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED: float = 3.2
const PULSE_SPEED: float = 4.0

var _color: Color = Color.WHITE
var _shape: String = "diamond"
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


func _draw() -> void:
	# Alpha shimmer between ~0.65 and 1.0 so the marker subtly pulses.
	var pulse: float = 0.825 + 0.175 * sin(_t * PULSE_SPEED)
	var fill: Color = Color(_color.r, _color.g, _color.b, _color.a * pulse)
	var outline: Color = Color(0.05, 0.05, 0.08, 0.85)

	if _shape == "weaken":
		_draw_weaken(fill, pulse)
		return

	var pts: PackedVector2Array = PackedVector2Array([
		Vector2(0, -SIZE),  # top
		Vector2(SIZE, 0),   # right
		Vector2(0, SIZE),   # bottom
		Vector2(-SIZE, 0),  # left
	])
	draw_colored_polygon(pts, fill)
	# Closed outline.
	var loop: PackedVector2Array = PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]])
	draw_polyline(loop, outline, 1.5)


## Attack-down glyph: a steel sword pointing DOWN (pommel up, tip down) with
## a red strike-through. Drawn slightly larger than the diamond so the two
## strokes stay legible at gameplay zoom.
func _draw_weaken(fill: Color, pulse: float) -> void:
	var s: float = SIZE * 1.25
	var guard_y: float = -s * 0.3

	# Blade: from the crossguard down to the tip.
	var blade_w: float = 1.7
	var blade: PackedVector2Array = PackedVector2Array([
		Vector2(-blade_w, guard_y),
		Vector2(blade_w, guard_y),
		Vector2(blade_w, s - 2.0),
		Vector2(0, s + 1.5),   # tip — pointing DOWN ("attack down")
		Vector2(-blade_w, s - 2.0),
	])
	draw_colored_polygon(blade, fill)
	# Crossguard + grip + pommel.
	draw_line(Vector2(-s * 0.65, guard_y), Vector2(s * 0.65, guard_y), fill, 2.0)
	draw_line(Vector2(0, guard_y), Vector2(0, -s * 0.8), fill, 2.0)
	draw_circle(Vector2(0, -s * 0.9), 1.6, fill)

	# The "no" slash: a bold red diagonal through the whole sword.
	var slash: Color = Color(0.95, 0.22, 0.18, 0.9 * pulse)
	draw_line(Vector2(-s, s * 0.85), Vector2(s, -s * 0.85), slash, 2.4)


## Show the marker in the given color + shape (called on every peer via the
## enemy's sync RPC).
func set_mark(color: Color, shape: String = "diamond") -> void:
	_color = color
	_shape = shape
	visible = true
	queue_redraw()


## Hide the marker (mark expired / consumed / enemy died).
func clear_mark() -> void:
	visible = false
