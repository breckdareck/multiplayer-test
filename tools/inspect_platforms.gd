extends SceneTree
## Report the horizontal runs in the Mid + Platform layers of mines (row, col-range, length)
## plus the atlas tiles the Platform layer uses, so platform layout can be reworked deliberately.
const MAP := "res://scenes/Levels/meadow_path.tscn"

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()
	for lname in ["Mid", "Platform"]:
		var l: TileMapLayer = _layer(text, lname)
		if l == null: continue
		var cells := l.get_used_cells()
		var byrow := {}
		for c in cells:
			if not byrow.has(c.y): byrow[c.y] = []
			byrow[c.y].append(c.x)
		var rows := byrow.keys(); rows.sort()
		print("=== ", lname, " (", cells.size(), " cells, ", rows.size(), " rows) ===")
		for r in rows:
			var xs = byrow[r]; xs.sort()
			var runs := []; var s = xs[0]; var p = xs[0]
			for i in range(1, xs.size()):
				if xs[i] == p + 1: p = xs[i]
				else: runs.append("%d-%d(%d)" % [s, p, p - s + 1]); s = xs[i]; p = xs[i]
			runs.append("%d-%d(%d)" % [s, p, p - s + 1])
			print("  row ", r, ": ", " ".join(runs))
		if lname == "Platform" and cells.size() > 0:
			var seen := {}
			for c in cells:
				var k := "src%d %s" % [l.get_cell_source_id(c), str(l.get_cell_atlas_coords(c))]
				seen[k] = seen.get(k, 0) + 1
			print("  atlas usage: ", seen)
		l.free()
	quit()

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
