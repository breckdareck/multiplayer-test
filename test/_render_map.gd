extends SceneTree
## Render existing maps faithfully (decode every TileMapLayer's tile_map_data and
## blit each cell from its source sheet) so we can study how good maps are built
## with this tileset. Saves _ref_<map>.png. Delete after.

const SHEETS := {
	0: "res://assets/sprites/world_tileset.png",
	1: "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/country village tileset.png",
	2: "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/Country_village_props.png",
}

func _init() -> void:
	var imgs := {}
	for s in SHEETS:
		var im := Image.new()
		if im.load(SHEETS[s]) == OK:
			im.convert(Image.FORMAT_RGBA8); imgs[s] = im
	for map_id in ["ruins", "mines", "dust_warren", "thornroot"]:
		_render(map_id, imgs)
	quit()

func _render(map_id: String, imgs: Dictionary) -> void:
	var fa := FileAccess.open("res://scenes/Levels/%s.tscn" % map_id, FileAccess.READ)
	if fa == null: return
	var text := fa.get_as_text(); fa.close()
	var node_re := RegEx.new(); node_re.compile('\\[node name="([^"]+)" type="TileMapLayer"')
	var data_re := RegEx.new(); data_re.compile('tile_map_data = PackedByteArray\\("([^"]*)"\\)')
	var layers := []
	var minx := 99999; var miny := 99999; var maxx := -99999; var maxy := -99999
	for nm in node_re.search_all(text):
		var start := nm.get_end()
		var dm := data_re.search(text, start)
		if dm == null: continue
		var nextnode := text.find("\n[node ", start)
		if nextnode != -1 and dm.get_start() > nextnode: continue
		var tl := TileMapLayer.new(); tl.tile_map_data = Marshalls.base64_to_raw(dm.get_string(1))
		var cells := {}
		for c in tl.get_used_cells():
			cells[c] = [tl.get_cell_source_id(c), tl.get_cell_atlas_coords(c)]
			minx = min(minx, c.x); miny = min(miny, c.y); maxx = max(maxx, c.x); maxy = max(maxy, c.y)
		tl.free()
		if not cells.is_empty(): layers.append(cells)
	if layers.is_empty(): return
	var img := Image.create((maxx - minx + 1) * 16, (maxy - miny + 1) * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.16, 0.22, 1.0))
	for cells in layers:
		for c in cells:
			var src: int = cells[c][0]
			if not imgs.has(src): continue
			var ax: Vector2i = cells[c][1]
			var sheet: Image = imgs[src]
			if ax.x < 0 or ax.y < 0 or (ax.x + 1) * 16 > sheet.get_width() or (ax.y + 1) * 16 > sheet.get_height(): continue
			img.blend_rect(sheet, Rect2i(ax.x * 16, ax.y * 16, 16, 16), Vector2i((c.x - minx) * 16, (c.y - miny) * 16))
	img.save_png("res://_ref_%s.png" % map_id)
	print("rendered ", map_id, "  ", (maxx - minx + 1), "x", (maxy - miny + 1), " tiles")
