extends Node
## Subtle mouse parallax + idle drift for the menu background layers.
##
## Add as a child of a menu root (LoginScreen / CharacterSelect / CharacterCreate)
## that has any of the named TextureRect/particle layers below. On the first
## frame it records each layer's authored position, then each frame nudges it
## opposite the mouse (farther-back layers move less) and gives the clouds a slow
## autonomous sine drift so the scene breathes even when the mouse is still.
##
## Purely cosmetic and self-contained — no gameplay effect, no networking.

# layer name -> { parallax: px of mouse-tracking, drift: px of idle x-sway }
# NB: "Sky" is intentionally absent — it's the backmost full-screen layer, so
# moving it would reveal black at the edges. The Village can move (it reveals the
# Sky behind it), and the Clouds/Embers are small enough not to expose edges.
const LAYERS := {
	"Cloud1":  {"parallax": 14.0, "drift": 22.0},
	"Cloud2":  {"parallax": 18.0, "drift": -30.0},
	"Village": {"parallax": 12.0, "drift": 0.0},
	"Embers":  {"parallax": 8.0,  "drift": 0.0},
}
const SMOOTH := 5.0          # mouse follow easing (higher = snappier)
const DRIFT_SPEED := 0.18    # idle cloud sway speed (rad/s)

var _layers: Array = []      # [{node, base, parallax, drift, phase}]
var _t := 0.0
var _mouse := Vector2.ZERO   # smoothed, -1..1 from screen centre
var _primed := false


func _ready() -> void:
	var root := get_parent()
	if root == null:
		set_process(false)
		return
	var i := 0
	for layer_name in LAYERS:
		var node = root.get_node_or_null(NodePath(layer_name))
		if node != null and "position" in node:
			_layers.append({
				"node": node,
				"base": node.position,
				"parallax": float(LAYERS[layer_name].parallax),
				"drift": float(LAYERS[layer_name].drift),
				"phase": float(i),
			})
		i += 1
	set_process(not _layers.is_empty())


func _process(delta: float) -> void:
	_t += delta
	var vp := get_viewport()
	var target := Vector2.ZERO
	if vp != null:
		var size := vp.get_visible_rect().size
		if size.x > 0.0 and size.y > 0.0:
			var m := vp.get_mouse_position()
			target = (m / size) * 2.0 - Vector2.ONE
			target.x = clampf(target.x, -1.0, 1.0)
			target.y = clampf(target.y, -1.0, 1.0)
	# Skip the first frame's lerp so we start centred, not snapping from (0,0).
	if not _primed:
		_mouse = target
		_primed = true
	else:
		_mouse = _mouse.lerp(target, clampf(delta * SMOOTH, 0.0, 1.0))
	for layer in _layers:
		var pos: Vector2 = layer.base - _mouse * layer.parallax
		if layer.drift != 0.0:
			pos.x += sin(_t * DRIFT_SPEED + layer.phase) * layer.drift
		layer.node.position = pos
