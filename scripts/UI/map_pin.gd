@tool
extends Control
class_name MapPin
## A single, hand-placeable world-map location marker. It renders ITSELF (dot + name +
## level), so the world map is fully WYSIWYG in the editor — open local_player_ui.tscn,
## find MoveableWindows/WorldMap/MapArea/Pins, and drag these onto the terrain. The
## position you set in the editor IS where the pin sits in game. world_map.gd fills in
## the live label/colour/current-location state at runtime via configure().

@export var map_id: String = ""

var tint: Color = Color(0.62, 0.82, 0.55)
var label_text: String = ""
var level_text: String = ""
var is_town: bool = false
var is_gate: bool = false
var is_current: bool = false

const R := 9.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()

## Called by world_map.gd when the map opens. Sets the live appearance + redraws.
func configure(p_label: String, p_level: String, p_tint: Color, p_town: bool, p_current: bool, p_gate := false) -> void:
	label_text = p_label; level_text = p_level; tint = p_tint
	is_town = p_town; is_current = p_current; is_gate = p_gate
	queue_redraw()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var nm := label_text if label_text != "" else map_id
	var col := tint
	if Engine.is_editor_hint():
		# editor preview colours so regions read while dragging
		if is_gate or map_id == "__core__": col = Color(0.65, 0.45, 0.8)
		elif map_id in ["lanterns_rest", "wickmoor", "hollowmere", "emberwatch"]: col = Color(0.95, 0.8, 0.35)
	# current-location halo
	if is_current:
		draw_circle(Vector2.ZERO, R + 7.0, Color(0.45, 0.85, 1.0, 0.22))
		draw_arc(Vector2.ZERO, R + 4.0, 0.0, TAU, 24, Color(0.45, 0.85, 1.0, 0.9), 2.0)
	var town := is_town or is_gate or (Engine.is_editor_hint() and (map_id == "__core__" or map_id in ["lanterns_rest", "wickmoor", "hollowmere", "emberwatch"]))
	if town:
		var s := R + 2.0
		draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), col)
		draw_rect(Rect2(-s, -s, s * 2.0, s * 2.0), Color(0, 0, 0, 0.7), false, 2.0)
	else:
		draw_circle(Vector2.ZERO, R, col)
		draw_arc(Vector2.ZERO, R, 0.0, TAU, 24, Color(0, 0, 0, 0.7), 1.5)
		draw_circle(Vector2(-R * 0.35, -R * 0.35), R * 0.22, Color(1, 1, 1, 0.5))
	var fs := 15 if town else 12
	var lc := Color(1, 0.92, 0.7) if town else Color(0.93, 0.91, 0.84)
	_label(font, nm, R + 5.0, fs, lc)
	if level_text != "":
		_label(font, level_text, R + 5.0 + fs + 3.0, 11, Color(0.62, 0.92, 1.0))

func _label(font: Font, s: String, dy: float, fs: int, col: Color) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var p := Vector2(-w * 0.5, dy + fs)
	draw_string(font, p + Vector2(1, 1), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0, 0, 0, 0.75))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
