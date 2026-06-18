extends SceneTree
## Re-place every enemy spawn marker EVENLY across the map's flat floor: pick flat-floor columns
## (surface row == both neighbours, so not a slope), drop those within PORTAL_BUF of a portal or
## EDGE of the rim, then spread the markers across them at an even stride, interleaved by spawner
## (so enemy types alternate). Floor-only, so the elevated safe shelves stay enemy-free.
const MAPS := ["old_battlefield", "mustering_fields", "cinderwaste"]
const PORTAL_BUF := 5
const EDGE := 3

func _init() -> void:
	for m in MAPS: _do(m)
	quit()

func _do(map: String) -> void:
	var path := "res://scenes/Levels/%s.tscn" % map
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: print(map, ": NO SCENE"); return
	var text := f.get_as_text(); f.close()
	var off := _tm_offset(text)
	var floor_top := _floor(text)
	if floor_top.is_empty(): print(map, ": NO FLOOR"); return
	var cols := floor_top.keys(); cols.sort()
	var mincol: int = cols[0]; var maxcol: int = cols[-1]
	var portal_cols := _portal_cols(text, off)

	# Flat floor columns, clear of slopes / portals / edges.
	var valid := []
	for col in cols:
		if col <= mincol + EDGE or col >= maxcol - EDGE: continue
		if floor_top.get(col - 1, -999) != floor_top[col] or floor_top.get(col + 1, -999) != floor_top[col]: continue
		var near := false
		for pc in portal_cols:
			if absi(col - pc) <= PORTAL_BUF: near = true; break
		if not near: valid.append(col)
	valid.sort()
	if valid.is_empty(): print(map, ": NO VALID FLOOR"); return

	# Collect markers grouped by spawner, then interleave so types alternate along the row.
	var nre := RegEx.new(); nre.compile('\\[node name="M\\d+" type="Marker2D" parent="(Spawn_[a-z_]+)"\\]\\s*\\nposition = Vector2\\(-?\\d+, -?\\d+\\)')
	var by := {}; var order := []
	for mm in nre.search_all(text):
		var sp := mm.get_string(1)
		if not by.has(sp): by[sp] = []; order.append(sp)
		by[sp].append(mm)
	var seq := []; var maxn := 0
	for sp in order: maxn = maxi(maxn, by[sp].size())
	for k in range(maxn):
		for sp in order:
			if k < by[sp].size(): seq.append(by[sp][k])
	if seq.is_empty(): print(map, ": NO MARKERS"); return

	# Even stride across the valid columns; rewrite each marker's position (last-to-first).
	var edits := []
	for i in seq.size():
		var col: int = valid[mini(valid.size() - 1, int(float(i) * valid.size() / seq.size()))]
		var row: int = floor_top[col]
		var np := "position = Vector2(%d, %d)" % [col * 16 + off.x + 8, (row - 1) * 16 + off.y]
		var mm = seq[i]
		var pidx: int = mm.get_start() + mm.get_string().find("position = Vector2(")
		edits.append([pidx, mm.get_end(), np])
	edits.sort_custom(func(a, b): return a[0] > b[0])
	for e in edits:
		text = text.substr(0, e[0]) + e[2] + text.substr(e[1])
	var w := FileAccess.open(path, FileAccess.WRITE); w.store_string(text); w.close()
	print(map, ": ", seq.size(), " markers spread over ", valid.size(), " flat-floor columns")

func _portal_cols(text: String, off: Vector2i) -> Array:
	var out := []
	var is_p := false
	for ln in text.split("\n"):
		if ln.begins_with("[node "): is_p = ln.begins_with('[node name="PortalTo')
		elif is_p and ln.begins_with("position = Vector2("):
			var p := ln.substr(19, ln.find(")") - 19).split(",")
			out.append(int(round((float(p[0].strip_edges()) - off.x) / 16.0))); is_p = false
	return out

func _tm_offset(text: String) -> Vector2i:
	var i := text.find('name="TileMap" type="TileMap"')
	if i == -1: return Vector2i.ZERO
	var ps := text.find("position = Vector2(", i)
	var inner := text.substr(ps + 19, text.find(")", ps) - (ps + 19)).split(",")
	return Vector2i(int(inner[0].strip_edges()), int(inner[1].strip_edges()))

func _floor(text: String) -> Dictionary:
	var i := text.find('name="Mid" type="TileMapLayer"')
	if i == -1: return {}
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, i)
	if di == -1: return {}
	var s := di + key.length()
	var l := TileMapLayer.new(); l.tile_map_data = Marshalls.base64_to_raw(text.substr(s, text.find('"', s) - s))
	var byc := {}
	for c in l.get_used_cells():
		if not byc.has(c.x): byc[c.x] = []
		byc[c.x].append(c.y)
	l.free()
	var out := {}
	for col in byc:
		var rows: Array = byc[col]; rows.sort()
		var top: int = rows[-1]; var set := {}
		for r in rows: set[r] = true
		while set.has(top - 1): top -= 1
		out[col] = top
	return out
