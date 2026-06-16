extends SceneTree
## Learn the country-village autotile rule from existing maps. For every placed
## ground cell, compute its 8-neighbor "solid" pattern and record which atlas tile
## the designer used. Aggregates across all Level scenes. No scene instantiation
## (feeds tile_map_data into a throwaway TileMapLayer), so no autoload issues.
## Delete after.

const DIRS = [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0),
              Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]  # NW N NE W E SW S SE

func _init() -> void:
	var dir := DirAccess.open("res://scenes/Levels")
	var files := []
	if dir:
		for f in dir.get_files():
			if f.ends_with(".tscn"):
				files.append(f.get_basename())

	var pattern_tile := {}   # "src:ax,ay" -> {pattern_bits: count}
	var src_totals := {}     # source_id -> total cells
	var per_map_src1 := {}

	for map_id in files:
		var path := "res://scenes/Levels/%s.tscn" % map_id
		var fa := FileAccess.open(path, FileAccess.READ)
		if fa == null: continue
		var text := fa.get_as_text(); fa.close()
		# Each TileMapLayer's tile_map_data base64.
		var node_re := RegEx.new(); node_re.compile('\\[node name="([^"]+)" type="TileMapLayer"')
		var data_re := RegEx.new(); data_re.compile('tile_map_data = PackedByteArray\\("([^"]*)"\\)')
		for nm in node_re.search_all(text):
			var start := nm.get_end()
			var next_node := text.find("\n[node ", start)
			var dm := data_re.search(text, start)
			if dm == null: continue
			if next_node != -1 and dm.get_start() > next_node: continue
			var b64 := dm.get_string(1)
			var bytes := Marshalls.base64_to_raw(b64)
			var tl := TileMapLayer.new()
			tl.tile_map_data = bytes
			var cells := tl.get_used_cells()
			# Build solid set for this layer.
			var solid := {}
			for c in cells: solid[c] = true
			for c in cells:
				var src := tl.get_cell_source_id(c)
				src_totals[src] = src_totals.get(src, 0) + 1
				if src != 1: continue   # source 1 = country village tileset
				per_map_src1[map_id] = per_map_src1.get(map_id, 0) + 1
				var ax := tl.get_cell_atlas_coords(c)
				var bits := 0
				for i in range(8):
					if solid.has(c + DIRS[i]): bits |= (1 << i)
				var k := "%d,%d" % [ax.x, ax.y]
				if not pattern_tile.has(bits): pattern_tile[bits] = {}
				pattern_tile[bits][k] = pattern_tile[bits].get(k, 0) + 1
			tl.free()

	print("=== source usage (cells) ===")
	for s in src_totals: print("  source ", s, ": ", src_totals[s])
	print("=== source-1 cells per map ===")
	for m in per_map_src1: print("  ", m, ": ", per_map_src1[m])
	print("=== learned: 8-neighbor pattern -> atlas tile (bits NW,N,NE,W,E,SW,S,SE) ===")
	var keys := pattern_tile.keys(); keys.sort()
	for bits in keys:
		var tiles = pattern_tile[bits]
		var parts := []
		for k in tiles: parts.append("%s x%d" % [k, tiles[k]])
		print("  ", _bitstr(bits), " (", bits, "): ", ", ".join(parts))
	quit()

func _bitstr(b: int) -> String:
	var s := ""
	for i in range(8): s += ("1" if (b & (1 << i)) else "0")
	return s
