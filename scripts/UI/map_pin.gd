@tool
extends Control
class_name MapPin
## A single, hand-placeable world-map location marker. It renders ITSELF (dot + name +
## level) centred in a small clickable box, so you can grab and drag it directly in the
## 2D editor (open local_player_ui.tscn, find MoveableWindows/WorldMap/MapArea/Pins).
## The box CENTRE is the location; world_map.gd fills live label/colour/current state via
## configure(). Positioned by anchors (fraction of the fullscreen map) so pins track the
## image at any resolution.

@export var map_id: String = ""

var tint: Color = Color(0.62, 0.82, 0.55)
var label_text: String = ""
var level_text: String = ""
var is_town: bool = false
var is_gate: bool = false
var is_current: bool = false

const R := 9.0
const BOX := 24.0   # clickable hit-box (so the pin is grabbable in the editor)

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(BOX, BOX)
	queue_redraw()

## The location point in this pin's own space (centre of the box).
func center() -> Vector2:
	return global_position + size * 0.5

## Called by world_map.gd when the map opens. Sets the live appearance + redraws.
func configure(p_label: String, p_level: String, p_tint: Color, p_town: bool, p_current: bool, p_gate := false) -> void:
	label_text = p_label; level_text = p_level; tint = p_tint
	is_town = p_town; is_current = p_current; is_gate = p_gate
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var c := size * 0.5
	var nm := label_text if label_text != "" else map_id
	var gate := is_gate or map_id == "__core__" or map_id == "__surface__"
	var town := is_town or gate
	var col := tint
	if Engine.is_editor_hint():
		# editor preview colours so regions read while dragging
		if gate: col = Color(0.65, 0.45, 0.8)
		elif map_id in ["lanterns_rest", "wickmoor", "hollowmere", "emberwatch"]:
			col = Color(0.95, 0.8, 0.35); town = true
		# faint box outline so the grab target is visible in the editor
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, 0.10), false, 1.0)
	if is_current:
		draw_circle(c, R + 7.0, Color(0.45, 0.85, 1.0, 0.22))
		draw_arc(c, R + 4.0, 0.0, TAU, 24, Color(0.45, 0.85, 1.0, 0.9), 2.0)
	if town:
		var s := R + 2.0
		draw_rect(Rect2(c.x - s - 2.0, c.y - s - 2.0, (s + 2.0) * 2.0, (s + 2.0) * 2.0), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(c.x - s, c.y - s, s * 2.0, s * 2.0), col)
		draw_rect(Rect2(c.x - s, c.y - s, s * 2.0, s * 2.0), Color(0, 0, 0, 0.9), false, 2.0)
	else:
		draw_circle(c, R + 2.0, Color(0, 0, 0, 0.55))   # dark halo so the dot reads on bright art
		draw_circle(c, R, col)
		draw_arc(c, R, 0.0, TAU, 24, Color(0, 0, 0, 0.9), 2.0)
		draw_circle(c + Vector2(-R * 0.35, -R * 0.35), R * 0.22, Color(1, 1, 1, 0.5))
	var fs := 15 if town else 12
	var lc := Color(1, 0.92, 0.7) if town else Color(0.93, 0.91, 0.84)
	_label(font, nm, c, R + 5.0, fs, lc)
	if level_text != "":
		_label(font, level_text, c, R + 5.0 + fs + 3.0, 11, Color(0.62, 0.92, 1.0))

func _label(font: Font, s: String, c: Vector2, dy: float, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(c.x - w * 0.5, c.y + dy + fs)
	# full 8-direction black outline so the name reads on any bright/busy terrain
	for o in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1), Vector2(0, -1), Vector2(0, 1), Vector2(-1, 0), Vector2(1, 0)]:
		draw_string(font, p + o, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.95))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
