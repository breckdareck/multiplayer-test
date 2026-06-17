extends SceneTree
## Reposition a hand-edited map's enemy spawn markers (+ PlayerSpawn) onto the CURRENT terrain:
## decode the Mid + Platform tile layers, find flat top-surface stretches, and snap every
## Spawn_* marker there (1 tile above), spread across the spawners. Run:
##   godot --headless --path <overhaul> --script res://tools/fix_spawns.gd --log-file ...
const UP := Vector2i(0, -1)
const MAP := "res://scenes/Levels/meadow_path.tscn"
# Cave maps have a ceiling whose top edge is a false "surface" — require solid above a spot to
# reject it. Outdoor maps (no ceiling) must NOT require that, or every surface gets rejected.
const CAVE := false
# Rest zones (no enemies spawn here): the small isolated perches on row 14 (climbed to via the
# ropes), plus a thin portal buffer at each map edge so you aren't dropped onto a mob.
const EDGE_SAFE := 8
const SAFE_PLATFORMS := []  # [ground_row, col_start, col_end] — none yet for deep_woods

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()
	var off := _tm_offset(text)
	var solid := {}
	for ln in ["Mid", "Platform"]:
		for c in _decode(text, ln): solid[c] = true
	var miny := 99999; var maxx := -99999
	for c in solid: miny = mini(miny, c.y); maxx = maxi(maxx, c.x)
	# Flat top-surface spots: a solid/platform cell with air above whose L+R are also surfaces,
	# AND that sits UNDER a ceiling (some solid above it in its column) — this rejects the roof's
	# own top edge, which has air above but is outside the play area.
	var raw := []
	for c in solid:
		if solid.has(c + UP): continue
		var l := Vector2i(c.x - 1, c.y); var r := Vector2i(c.x + 1, c.y)
		if not (solid.has(l) and not solid.has(l + UP) and solid.has(r) and not solid.has(r + UP)): continue
		if CAVE:
			var roofed := false
			for y in range(miny, c.y):
				if solid.has(Vector2i(c.x, y)): roofed = true; break
			if not roofed: continue
		raw.append(c)
	raw.sort_custom(func(a, b): return (a.y < b.y) or (a.y == b.y and a.x < b.x))
	var spots := []; var lastx := {}
	for s in raw:
		if not lastx.has(s.y) or s.x - lastx[s.y] >= 3:
			spots.append(s); lastx[s.y] = s.x
	if spots.is_empty(): print("NO SPOTS FOUND"); quit(); return
	# Enemies avoid the rest zones; the player can still spawn there.
	var enemy_spots := []
	for s in spots:
		if not _safe(s, maxx): enemy_spots.append(s)
	if enemy_spots.is_empty(): enemy_spots = spots

	# Collect markers grouped by spawner, then interleave so each enemy type spreads out.
	var nre := RegEx.new(); nre.compile('\\[node name="M\\d+" type="Marker2D" parent="(Spawn_[a-z_]+)"\\]')
	var by := {}; var order := []
	for m in nre.search_all(text):
		var sp := m.get_string(1)
		if not by.has(sp): by[sp] = []; order.append(sp)
		by[sp].append(m.get_end())
	var seq := []; var maxn := 0
	for sp in order: maxn = maxi(maxn, by[sp].size())
	for k in range(maxn):
		for sp in order:
			if k < by[sp].size(): seq.append(by[sp][k])

	# Spread markers evenly across ALL surface spots (sorted top->bottom), so enemies
	# populate every tier, not just the first 30 rows.
	var edits := []
	for i in seq.size():
		var s = enemy_spots[mini(enemy_spots.size() - 1, int(float(i) * enemy_spots.size() / maxi(1, seq.size())))]
		edits.append([seq[i], "position = Vector2(%d, %d)" % [s.x * 16 + off.x + 8, (s.y - 1) * 16 + off.y]])
	# PlayerSpawn -> leftmost spot on the floor (the lowest rows).
	var lowrow := 0
	for s in spots: lowrow = maxi(lowrow, s.y)
	var bottom := []
	for s in spots:
		if s.y >= lowrow - 2: bottom.append(s)
	var pspot = bottom[0]
	for s in bottom:
		if s.x < pspot.x: pspot = s
	var pi := text.find('[node name="PlayerSpawn"')
	if pi != -1: edits.append([pi, "position = Vector2(%d, %d)" % [pspot.x * 16 + off.x + 8, (pspot.y - 1) * 16 + off.y]])

	# Apply position replacements from last to first so earlier offsets stay valid.
	edits.sort_custom(func(a, b): return a[0] > b[0])
	for e in edits:
		var ps := text.find("position = Vector2(", e[0])
		var nn := text.find("\n[node", e[0])
		if ps != -1 and (nn == -1 or ps < nn):
			text = text.substr(0, ps) + e[1] + text.substr(text.find(")", ps) + 1)

	var w := FileAccess.open(MAP, FileAccess.WRITE); w.store_string(text); w.close()
	print("OK repositioned ", seq.size(), " enemy markers across ", enemy_spots.size(), " spots (", spots.size() - enemy_spots.size(), " rest spots reserved); PlayerSpawn -> ", pspot)
	quit()

# A ground cell is safe (no enemies) if it's within the edge buffer or on a designated rest platform.
func _safe(c: Vector2i, maxx: int) -> bool:
	if c.x <= EDGE_SAFE or c.x >= maxx - EDGE_SAFE: return true
	for sp in SAFE_PLATFORMS:
		if c.y == sp[0] and c.x >= sp[1] and c.x <= sp[2]: return true
	return false

func _tm_offset(text: String) -> Vector2i:
	var i := text.find('name="TileMap" type="TileMap"')
	if i == -1: return Vector2i.ZERO
	var ps := text.find("position = Vector2(", i)
	var nn := text.find("\n[node", i)
	if ps == -1 or (nn != -1 and ps > nn): return Vector2i.ZERO
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
