extends Node2D
class_name DebugSpawnOverlay

## Dev-console overlay for the population spawn system (ADR 0015). Draws every
## EnemySpawner's spawn-point markers, a per-spawner alive/pool label, and a
## MAP-WIDE headline (total alive / map cap / occupancy) — since the cap is one
## budget across the whole map's spawn points, not per spawner. Toggled via the
## `spawns` console command.
##
## Lives as a child of the current map instance (inside that map's SubViewport) so
## markers align with world coordinates, and re-homes itself when the player
## travels. Density is server-authoritative, so numbers are real on the host and
## shown as host-only on a remote client (the markers still draw).

const _PALETTE: Array[Color] = [
	Color(0.45, 0.85, 1.0), Color(1.0, 0.78, 0.35), Color(0.60, 1.0, 0.55),
	Color(1.0, 0.55, 0.85), Color(0.78, 0.70, 1.0), Color(1.0, 0.96, 0.40),
]
const _MARKER_RADIUS := 14.0
const _FONT_SIZE := 14
const _HEADER_FONT_SIZE := 16
const _REDRAW_INTERVAL := 0.2

var _redraw_accum := 0.0
var _font: Font


func _ready() -> void:
	z_index = 4096 # draw over the map content
	z_as_relative = false
	_font = ThemeDB.fallback_font


func _process(delta: float) -> void:
	# Follow the local player across map changes: re-parent under whatever map is
	# current so markers stay in the right SubViewport / world.
	var cur = MapManager.current_map_instance
	if is_instance_valid(cur) and get_parent() != cur:
		call_deferred("reparent", cur, false)
		return

	_redraw_accum += delta
	if _redraw_accum >= _REDRAW_INTERVAL:
		_redraw_accum = 0.0
		queue_redraw()


func _draw() -> void:
	var map := get_parent()
	if not is_instance_valid(map):
		return
	var is_server := multiplayer.has_multiplayer_peer() and multiplayer.is_server()
	var overall := Vector2.ZERO
	var overall_n := 0
	var idx := 0

	for spawner in get_tree().get_nodes_in_group("EnemySpawners"):
		if not (is_instance_valid(spawner) and map.is_ancestor_of(spawner) \
				and spawner.has_method("get_population_report")):
			continue
		var report: Dictionary = spawner.get_population_report()
		var col: Color = _PALETTE[idx % _PALETTE.size()]
		idx += 1

		var locs: Array = report.get("spawn_locations", [])
		var centroid := Vector2.ZERO
		for gpos in locs:
			var p: Vector2 = to_local(gpos)
			centroid += p
			overall += p
			overall_n += 1
			draw_circle(p, _MARKER_RADIUS, Color(col.r, col.g, col.b, 0.16))
			draw_arc(p, _MARKER_RADIUS, 0.0, TAU, 28, col, 2.0, true)
			draw_line(p + Vector2(-6, 0), p + Vector2(6, 0), col, 1.5)
			draw_line(p + Vector2(0, -6), p + Vector2(0, 6), col, 1.5)

		if locs.is_empty():
			continue
		centroid /= locs.size()
		var density: String
		if is_server:
			density = "%d/%d" % [int(report.get("alive", 0)), int(report.get("pool", 0))]
		else:
			density = "pool:%d" % int(report.get("pool", 0))
		var star: String = "  *always" if report.get("excluded", false) else ""
		_label(centroid + Vector2(0, -_MARKER_RADIUS - 8.0),
			"%s  %s%s" % [String(report.get("name", "?")), density, star],
			col, _FONT_SIZE, false)

	# Map-wide headline — the number the cap actually acts on.
	if overall_n > 0:
		overall /= overall_n
		_label(overall + Vector2(0, -_MARKER_RADIUS - 42.0), _header_text(is_server),
			Color(1, 1, 1), _HEADER_FONT_SIZE, true)


func _header_text(is_server: bool) -> String:
	if not is_server:
		return "MAP cap — host-only"
	var s: Dictionary = MapManager.get_map_population_summary(MapManager.current_map_id)
	if s.is_empty():
		return "MAP cap — n/a"
	return "MAP  %d/%d alive   pool %d · occ %d" % [
		int(s.total_alive), int(s.map_cap), int(s.total_pool), int(s.occupants)]


## Draw a horizontally-centered single-line label whose bottom edge sits at
## `center_bottom`, with a dark background plate (outlined for the header).
func _label(center_bottom: Vector2, txt: String, col: Color, font_size: int, header: bool) -> void:
	var sz: Vector2 = _font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var top_left := center_bottom + Vector2(-sz.x * 0.5, -sz.y)
	var plate := Rect2(top_left - Vector2(5, 3), sz + Vector2(10, 6))
	draw_rect(plate, Color(0.05, 0.05, 0.08, 0.8) if header else Color(0, 0, 0, 0.6))
	if header:
		draw_rect(plate, col, false, 1.0)
	draw_string(_font, top_left + Vector2(0, _font.get_ascent(font_size)),
		txt, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
