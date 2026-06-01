class_name EnemyMarkIndicator
extends Node2D

## A small floating diamond drawn above a marked enemy's head, color-coded by
## the mark type that tagged it (Death Mark / Mark of the Hunt / Sentinel's
## Mark / Mana Surge). Purely cosmetic — visibility + color are driven by
## EnemyBase.sync_mark_indicator (a server→all-peers RPC). The diamond bobs
## gently for a "floating" read and pulses its alpha so it draws the eye.
##
## Self-contained custom-drawn marker (no art asset needed): a filled diamond
## with a dark outline. Created dynamically by EnemyBase._ready on every peer
## so the RPC has a node to toggle.

const SIZE: float = 6.0
const BOB_AMPLITUDE: float = 2.5
const BOB_SPEED: float = 3.2
const PULSE_SPEED: float = 4.0

var _color: Color = Color.WHITE
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


## Show the marker in the given color (called on every peer via the enemy's
## sync RPC).
func set_mark(color: Color) -> void:
	_color = color
	visible = true
	queue_redraw()


## Hide the marker (mark expired / consumed / enemy died).
func clear_mark() -> void:
	visible = false
