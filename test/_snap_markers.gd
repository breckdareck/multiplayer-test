extends SceneTree
## Re-seat every SlimeSpawner0 Marker2D in gen_open.tscn to exactly 1 tile above the
## surface directly beneath it (scanning down from just above the marker, so it finds
## the marker's own tier — floor or shelf — never a shelf overhead). Keeps all other
## edits. Transform: root = (col*16 - 218, row*16 - 285).
const PATH := "res://scenes/Levels/gen_open.tscn"
const OFFX := 218; const OFFY := 285

func _init() -> void:
	var f := FileAccess.open(PATH, FileAccess.READ); var text := f.get_as_text(); f.close()
	var solid := {}
	for ln in ["Mid", "Platform"]:
		var b := _layer_data(text, ln)
		if b == "": continue
		var tl := TileMapLayer.new(); tl.tile_map_data = Marshalls.base64_to_raw(b)
		for c in tl.get_used_cells(): solid[c] = true
		tl.free()
	var re := RegEx.new()
	re.compile('(\\[node name="M\\d+" type="Marker2D" parent="SlimeSpawner0"\\]\\nposition = Vector2\\()(-?\\d+), (-?\\d+)(\\))')
	var out := ""; var last := 0; var changed := 0
	for mm in re.search_all(text):
		var x := int(mm.get_string(2)); var y := int(mm.get_string(3))
		var col := int(round((x + OFFX) / 16.0))
		var mrow := int(round((y + OFFY) / 16.0))
		var surf := -99999
		for r in range(mrow - 3, mrow + 60):              # first solid at/below the tier
			if solid.has(Vector2i(col, r)): surf = r; break
		var ny := y
		if surf != -99999: ny = (surf - 1) * 16 - OFFY
		if ny != y: changed += 1
		out += text.substr(last, mm.get_start() - last)
		out += mm.get_string(1) + str(x) + ", " + str(ny) + mm.get_string(4)
		last = mm.get_end()
	out += text.substr(last)
	var w := FileAccess.open(PATH, FileAccess.WRITE); w.store_string(out); w.close()
	print("SNAP done, markers moved=", changed)
	quit()

func _layer_data(text: String, lname: String) -> String:
	var ni := text.find('name="%s" type="TileMapLayer"' % lname)
	if ni == -1: return ""
	var ne := text.find("\n[", text.find("\n", ni) + 1)
	if ne == -1: ne = text.length()
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, ni)
	if di == -1 or di > ne: return ""
	var s := di + key.length(); var e := text.find('"', s)
	return text.substr(s, e - s)
