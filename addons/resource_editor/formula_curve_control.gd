@tool
class_name FormulaCurveControl
extends Control

## Inline curve preview for an AbilityScalingFormula, shown at the top of that
## formula's sub-inspector (via WeaponContentInspector). Plots value-over-level
## so you can see a curve's shape while editing it in the native Inspector.

const C_DARK   = Color(0.10, 0.11, 0.13)
const C_BORDER = Color(0.30, 0.32, 0.38)
const C_DIM    = Color(0.55, 0.58, 0.64)
const MAX_LEVEL := 20  # the formula sub-resource doesn't carry max_level; show shape

var _formula: Resource
var _accent := Color(0.75, 0.48, 1.00)


func _init() -> void:
	custom_minimum_size = Vector2(0, 120)
	if Engine.is_editor_hint():
		var th := EditorInterface.get_editor_theme()
		if th and th.has_color("accent_color", "Editor"):
			_accent = th.get_color("accent_color", "Editor")


func set_formula(formula: Resource) -> void:
	_formula = formula
	if formula and not formula.changed.is_connected(queue_redraw):
		formula.changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	var sz := size
	var bg := StyleBoxFlat.new()
	bg.bg_color = C_DARK
	bg.border_color = C_BORDER
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	draw_style_box(bg, Rect2(Vector2.ZERO, sz))

	var font := ThemeDB.fallback_font
	if font == null:
		return
	if _formula == null or not _formula.has_method("calculate"):
		draw_string(font, Vector2(12, sz.y / 2 + 4), "No formula.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
		return

	var values: Array[float] = []
	var max_val := -INF
	var min_val := INF
	for lvl in range(1, MAX_LEVEL + 1):
		var v := float(_formula.calculate(lvl))
		values.append(v)
		max_val = maxf(max_val, v)
		min_val = minf(min_val, v)
	if absf(max_val - min_val) < 0.001:
		max_val = min_val + 1.0

	var pad_l := 40.0
	var pad_r := 12.0
	var pad_t := 12.0
	var pad_b := 22.0
	var plot_w := sz.x - pad_l - pad_r
	var plot_h := sz.y - pad_t - pad_b
	if plot_w <= 1 or plot_h <= 1:
		return
	var origin := Vector2(pad_l, pad_t + plot_h)

	for i in range(4):
		var y := pad_t + plot_h * float(i) / 3.0
		draw_line(Vector2(pad_l, y), Vector2(pad_l + plot_w, y), Color(C_BORDER, 0.4), 1)
	draw_line(origin, Vector2(pad_l + plot_w, origin.y), C_BORDER, 1)
	draw_line(origin, Vector2(pad_l, pad_t), C_BORDER, 1)

	var points := PackedVector2Array()
	for i in range(values.size()):
		var fx := 0.0 if MAX_LEVEL == 1 else float(i) / float(MAX_LEVEL - 1)
		var fy := (values[i] - min_val) / (max_val - min_val)
		points.push_back(Vector2(pad_l + plot_w * fx, pad_t + plot_h - plot_h * fy))
	if points.size() >= 2:
		var fill := points.duplicate()
		fill.push_back(Vector2(points[points.size() - 1].x, origin.y))
		fill.push_back(Vector2(points[0].x, origin.y))
		draw_colored_polygon(fill, Color(_accent, 0.15))
		draw_polyline(points, _accent, 2.0, true)
	for p in points:
		draw_circle(p, 2.5, _accent)

	draw_string(font, Vector2(4, pad_t + 8), "%.1f" % max_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	draw_string(font, Vector2(4, pad_t + plot_h), "%.1f" % min_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	draw_string(font, Vector2(pad_l - 2, origin.y + 14), "Lv1", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	draw_string(font, Vector2(pad_l + plot_w - 22, origin.y + 14), "Lv%d" % MAX_LEVEL, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
