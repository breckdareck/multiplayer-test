extends SceneTree
## Schematic spawn check (tile-art independent): decode Mid (solid) + Platform layers and
## draw every Spawn_* marker (red) + PlayerSpawn (green) over the terrain blocks, so we can
## see at a glance whether each pin rests on ground. Also prints any FLOATING markers.
const MAP := "res://scenes/Levels/ember_meadows.tscn"
const OUT := "res://docs/map_previews/_ember_meadows_spawncheck.png"
const Z := 6
const UP := Vector2i(0, -1)
# Mirror of fix_spawns.gd's rest zones (keep in sync) — drawn cyan so safe spots are visible.
const EDGE_SAFE := 8
const SAFE_PLATFORMS := []

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()
	var off := _tm_offset(text)
	var mid := {}; for c in _decode(text, "Mid"): mid[c] = true
	var plat := {}; for c in _decode(text, "Platform"): plat[c] = true
	var solid := {}; for c in mid: solid[c] = true
	for c in plat: solid[c] = true

	# Parse marker + player-spawn world positions -> the air cell they occupy.
	var markers := []; var player := Vector2i(-9999, 0)
	var is_marker := false; var is_player := false
	for ln in text.split("\n"):
		if ln.begins_with("[node"):
			is_marker = ('type="Marker2D"' in ln) and ('parent="Spawn_' in ln)
			is_player = 'name="PlayerSpawn"' in ln
		elif ln.begins_with("position = Vector2(") and (is_marker or is_player):
			var inner := ln.substr(19, ln.find(")") - 19).split(",")
			var col := int(round((int(inner[0].strip_edges()) - off.x - 8) / 16.0))
			var grow := int(round((int(inner[1].strip_edges()) - off.y) / 16.0)) + 1  # ground row
			var cell := Vector2i(col, grow - 1)  # the air cell the enemy stands in
			if is_player: player = cell
			else: markers.append(cell)
			is_marker = false; is_player = false

	# Floating check: ground cell directly under the air cell must be solid/platform.
	var floating := 0
	for m in markers:
		if not solid.has(Vector2i(m.x, m.y + 1)): floating += 1
	if not solid.has(Vector2i(player.x, player.y + 1)): floating += 1

	# Bounds across all solid cells.
	var minx := 99999; var miny := 99999; var maxx := -99999; var maxy := -99999
	for c in solid:
		minx = mini(minx, c.x); miny = mini(miny, c.y); maxx = maxi(maxx, c.x); maxy = maxi(maxy, c.y)
	var w := (maxx - minx + 3) * Z; var h := (maxy - miny + 3) * Z
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.07, 0.09))
	for c in mid: _blk(img, c - Vector2i(minx - 1, miny - 1), Color(0.32, 0.30, 0.34))
	for c in plat: _blk(img, c - Vector2i(minx - 1, miny - 1), Color(0.55, 0.40, 0.30))
	for c in solid:  # lighter top edge on surfaces; cyan if it's a rest (safe) surface
		if not solid.has(c + UP):
			var col := Color(0.62, 0.58, 0.55)
			if _safe(c, maxx): col = Color(0.3, 0.85, 0.95)
			_blk(img, c - Vector2i(minx - 1, miny - 1), col, 2)
	# Ropes (yellow vertical climb lines).
	for rp in _ropes(text):
		print("rope col=", int(round((rp[0] - off.x) / 16.0)), " rows ", int(round((rp[1] - off.y) / 16.0)), "..", int(round((rp[2] - off.y) / 16.0)))
	for rp in _ropes(text):
		var cx := int(round((rp[0] - off.x) / 16.0)) - (minx - 1)
		var y0 := int(round((rp[1] - off.y) / 16.0)) - (miny - 1)
		var y1 := int(round((rp[2] - off.y) / 16.0)) - (miny - 1)
		for ry in range(mini(y0, y1), maxi(y0, y1) + 1):
			for dy in range(Z):
				var px := cx * Z + Z / 2; var py := ry * Z + dy
				if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height(): img.set_pixel(px, py, Color(1, 0.9, 0.2))
	for m in markers: _dot(img, m - Vector2i(minx - 1, miny - 1), Color(1, 0.25, 0.25))
	_dot(img, player - Vector2i(minx - 1, miny - 1), Color(0.3, 1, 0.4))
	# Portals (magenta door, 3 tiles tall above the ground).
	for p in _portals(text):
		var pc := Vector2i(int(round((p.x - off.x) / 16.0)), int(round((p.y - off.y) / 16.0))) - Vector2i(minx - 1, miny - 1)
		print("portal at col ", int(round((p.x - off.x) / 16.0)), " row ", int(round((p.y - off.y) / 16.0)))
		for dy in range(-3, 1):
			_blk(img, Vector2i(pc.x, pc.y + dy), Color(0.95, 0.2, 0.85))
	img.save_png(OUT)
	print("OK markers=", markers.size(), " floating=", floating, " bounds=", Vector2i(minx, miny), "..", Vector2i(maxx, maxy))
	quit()

# Parse PortalTo* node instance positions -> world Vector2 per portal.
func _portals(text: String) -> Array:
	var out := []
	var is_portal := false
	for ln in text.split("\n"):
		if ln.begins_with("[node "):
			is_portal = ln.begins_with('[node name="PortalTo')
		elif is_portal and ln.begins_with("position = Vector2("):
			var p := ln.substr(19, ln.find(")") - 19).split(",")
			out.append(Vector2(float(p[0].strip_edges()), float(p[1].strip_edges()))); is_portal = false
	return out

# Parse the Ropes node's Area2D children -> [world_x, world_y_top, world_y_bottom] per rope.
func _ropes(text: String) -> Array:
	var out := []
	var lines := text.split("\n")
	var i := 0
	while i < lines.size():
		var ln: String = lines[i]
		if ln.begins_with("[node") and 'type="Area2D" parent="Ropes"]' in ln:
			var px := 0.0; var py := 0.0; var got := false
			var ot := -100.0; var ob := 100.0
			var j := i + 1
			while j < lines.size():
				var s: String = lines[j]
				if s.begins_with("[node") and 'parent="."' in s: break
				if s.begins_with("[node") and 'type="Area2D" parent="Ropes"]' in s: break
				if not got and s.begins_with("position = Vector2("):
					var p := s.substr(19, s.find(")") - 19).split(",")
					px = float(p[0].strip_edges()); py = float(p[1].strip_edges()); got = true
				elif s.begins_with("offset_top = "): ot = float(s.substr(13).strip_edges())
				elif s.begins_with("offset_bottom = "): ob = float(s.substr(16).strip_edges())
				j += 1
			out.append([px, py + ot, py + ob]); i = j; continue
		i += 1
	return out

func _safe(c: Vector2i, maxx: int) -> bool:
	if c.x <= EDGE_SAFE or c.x >= maxx - EDGE_SAFE: return true
	for sp in SAFE_PLATFORMS:
		if c.y == sp[0] and c.x >= sp[1] and c.x <= sp[2]: return true
	return false

func _blk(img: Image, cell: Vector2i, col: Color, hh: int = Z) -> void:
	for dy in range(hh):
		for dx in range(Z):
			var px := cell.x * Z + dx; var py := cell.y * Z + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height(): img.set_pixel(px, py, col)

func _dot(img: Image, cell: Vector2i, col: Color) -> void:
	var cx := cell.x * Z + Z / 2; var cy := cell.y * Z + Z / 2
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var px := cx + dx; var py := cy + dy
			if px >= 0 and py >= 0 and px < img.get_width() and py < img.get_height(): img.set_pixel(px, py, col)

func _tm_offset(text: String) -> Vector2i:
	var i := text.find('name="TileMap" type="TileMap"')
	if i == -1: return Vector2i.ZERO
	var ps := text.find("position = Vector2(", i)
	var inner := text.substr(ps + 19, text.find(")", ps) - (ps + 19)).split(",")
	return Vector2i(int(inner[0].strip_edges()), int(inner[1].strip_edges()))

func _decode(text: String, lname: String) -> Array:
	var i := text.find('name="%s" type="TileMapLayer"' % lname)
	if i == -1: return []
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, i)
	var nn := text.find("\n[node", i)
	if di == -1 or (nn != -1 and di > nn): return []
	var s := di + key.length()
	var l := TileMapLayer.new(); l.tile_map_data = Marshalls.base64_to_raw(text.substr(s, text.find('"', s) - s))
	var cells := l.get_used_cells(); l.free(); return cells
