@tool
extends Control
## Draws the roads between world-map pins, reading the real connection graph from the
## world-map catalog and the live pin positions from the sibling "Pins" node. @tool so
## the roads update in the editor as you drag pins. Sits above the map image, below the
## pins. Re-reads the catalog in the editor; at runtime world_map.gd calls refresh().

const CATALOG := "res://config/world_map_data.json"
var _conn: Dictionary = {}

func _ready() -> void:
	_load()
	queue_redraw()

func refresh() -> void:
	_load()
	queue_redraw()

func _load() -> void:
	_conn.clear()
	if not FileAccess.file_exists(CATALOG):
		return
	var f := FileAccess.open(CATALOG, FileAccess.READ)
	var p = JSON.parse_string(f.get_as_text())
	if p is Dictionary:
		var maps = p.get("maps", {})
		for m in maps:
			_conn[m] = maps[m].get("connections", [])

func _pins() -> Dictionary:
	var out := {}
	var node := get_node_or_null("../Pins")
	if node == null:
		node = get_node_or_null("../CorePins")
	if node == null:
		return out
	for c in node.get_children():
		var mid = c.get("map_id")
		if mid != null and str(mid) != "":
			out[str(mid)] = c
	return out

func _draw() -> void:
	var pins := _pins()
	var drawn := {}
	for a in pins:
		for b in _conn.get(a, []):
			if not pins.has(b):
				continue
			var key: String = a + "|" + b if a < b else b + "|" + a
			if drawn.has(key):
				continue
			drawn[key] = true
			var pa: Vector2 = _ctr(pins[a]) - global_position
			var pb: Vector2 = _ctr(pins[b]) - global_position
			draw_line(pa, pb, Color(0.08, 0.06, 0.04, 0.85), 5.0)
			draw_line(pa, pb, Color(0.84, 0.69, 0.43), 2.0)
	# gateway road: Emberwatch -> the Core descent
	if pins.has("emberwatch") and pins.has("__core__"):
		var pe: Vector2 = _ctr(pins["emberwatch"]) - global_position
		var pg: Vector2 = _ctr(pins["__core__"]) - global_position
		draw_line(pe, pg, Color(0.6, 0.35, 0.25), 3.0)

func _ctr(pin) -> Vector2:
	return pin.global_position + pin.size * 0.5
