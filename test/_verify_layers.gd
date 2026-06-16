extends SceneTree
## Decode gen_open's TileMapLayers and report each layer's tile sources, to confirm
## ground->Mid, platforms->Platform(17-19,9), decorations->Background(source 2).
func _init() -> void:
	var f := FileAccess.open("res://scenes/Levels/gen_open.tscn", FileAccess.READ)
	var text := f.get_as_text(); f.close()
	var node_re := RegEx.new(); node_re.compile('\\[node name="([^"]+)" type="TileMapLayer"')
	var data_re := RegEx.new(); data_re.compile('tile_map_data = PackedByteArray\\("([^"]*)"\\)')
	for nm in node_re.search_all(text):
		var lname := nm.get_string(1); var start := nm.get_end()
		var nextnode := text.find("\n[node ", start)
		var dm := data_re.search(text, start)
		if dm == null or (nextnode != -1 and dm.get_start() > nextnode):
			print(lname, ": (empty)"); continue
		var tl := TileMapLayer.new(); tl.tile_map_data = Marshalls.base64_to_raw(dm.get_string(1))
		var cells := tl.get_used_cells(); var srcs := {}; var rows9 := 0
		for c in cells:
			var s := tl.get_cell_source_id(c); srcs["src%d" % s] = srcs.get("src%d" % s, 0) + 1
			if s == 1 and tl.get_cell_atlas_coords(c).y == 9: rows9 += 1
		print(lname, ": cells=", cells.size(), " sources=", srcs, " platform_tiles(17-19,9)=", rows9)
		tl.free()
	quit()
