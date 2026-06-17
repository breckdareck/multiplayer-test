extends SceneTree
## Rebuild the cave's floating-ledge tiers in mines.tscn: clear the short ledges on the three
## tier rows and lay down fewer, longer platforms (good for training), reusing the rock-top
## L/M/R tiles already present on those tiers. Other terrain (ceiling, floor, edge ledges) is
## untouched. Re-run fix_spawns.gd afterwards (the markers move with the platforms).
const MAP := "res://scenes/Levels/mines.tscn"
const CLEAR_ROWS := [12, 14, 17, 22]
# New platform spans per tier row: [col_start, col_end] inclusive. Tiers (12/17/22) are the long
# training platforms, staggered so you can jump tier-to-tier. Row 14 holds the small isolated
# safe perches — 4 tiles each, sitting in row-12 gaps above the full-height ropes at cols 22/90/123,
# so you climb a rope to rest there and enemies (kept off by fix_spawns) can't reach them.
const NEW := {
	12: [[24, 42], [64, 82], [104, 122]],
	14: [[20, 23], [88, 91], [130, 133]],
	17: [[14, 30], [48, 66], [84, 102], [120, 138]],
	22: [[24, 42], [64, 82], [104, 122]],
}

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()
	var src: TileMapLayer = _layer(text, "Mid")
	if src == null: print("NO MID LAYER"); quit(); return
	var lmr := _sample_lmr(src)
	if lmr.is_empty(): print("NO LEDGE TILE TO SAMPLE"); quit(); return

	var out := TileMapLayer.new()
	for c in src.get_used_cells():
		if c.y in CLEAR_ROWS: continue
		out.set_cell(c, src.get_cell_source_id(c), src.get_cell_atlas_coords(c), src.get_cell_alternative_tile(c))
	var n := 0
	for row in NEW:
		for span in NEW[row]:
			var a: int = span[0]; var b: int = span[1]
			for x in range(a, b + 1):
				var t = lmr["m"]
				if x == a: t = lmr["l"]
				elif x == b: t = lmr["r"]
				out.set_cell(Vector2i(x, row), t[0], t[1], t[2])
			n += 1
	var b64 := Marshalls.raw_to_base64(out.tile_map_data)
	text = _replace_data(text, "Mid", b64)
	var w := FileAccess.open(MAP, FileAccess.WRITE); w.store_string(text); w.close()
	print("OK rebuilt ", n, " platforms across rows ", CLEAR_ROWS)
	src.free(); out.free(); quit()

func _sample_lmr(src: TileMapLayer) -> Dictionary:
	for row in CLEAR_ROWS:
		var xs := []
		for c in src.get_used_cells():
			if c.y == row: xs.append(c.x)
		xs.sort()
		var s := -1; var p := -1
		for x in xs:
			if s == -1: s = x; p = x
			elif x == p + 1: p = x
			else:
				if p - s >= 2: return _lmr(src, row, s, p)
				s = x; p = x
		if s != -1 and p - s >= 2: return _lmr(src, row, s, p)
	return {}

func _lmr(src: TileMapLayer, row: int, s: int, p: int) -> Dictionary:
	return {
		"l": [src.get_cell_source_id(Vector2i(s, row)), src.get_cell_atlas_coords(Vector2i(s, row)), src.get_cell_alternative_tile(Vector2i(s, row))],
		"m": [src.get_cell_source_id(Vector2i(s + 1, row)), src.get_cell_atlas_coords(Vector2i(s + 1, row)), src.get_cell_alternative_tile(Vector2i(s + 1, row))],
		"r": [src.get_cell_source_id(Vector2i(p, row)), src.get_cell_atlas_coords(Vector2i(p, row)), src.get_cell_alternative_tile(Vector2i(p, row))],
	}

func _replace_data(text: String, lname: String, b64: String) -> String:
	var i := text.find('name="%s" type="TileMapLayer"' % lname)
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, i)
	var s := di + key.length()
	return text.substr(0, s) + b64 + text.substr(text.find('"', s))

func _layer(text: String, lname: String) -> TileMapLayer:
	var i := text.find('name="%s" type="TileMapLayer"' % lname)
	if i == -1: return null
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, i)
	var nn := text.find("\n[node", i)
	if di == -1 or (nn != -1 and di > nn): return null
	var s := di + key.length()
	var l := TileMapLayer.new(); l.tile_map_data = Marshalls.base64_to_raw(text.substr(s, text.find('"', s) - s))
	return l
