extends SceneTree
## Render each map faithfully from its .tscn (decode every TileMapLayer + blit each
## cell from its source sheet) AND extract spawn-point data — every spawner's enemy
## type, pool size, and each spawn marker projected into image pixels. Writes clean
## PNGs + spawns.json under res://docs/map_previews/ for the annotated-preview
## pipeline (tools/annotate_map_previews.py draws the pins + legend).
##
## Run: Godot --headless --path <overhaul> --script res://tools/render_map_previews.gd

const SHEETS := {
	0: "res://assets/sprites/world_tileset.png",
	1: "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/country village tileset.png",
	2: "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/Country_village_props.png",
}
const MAPS := [
	"near_wilds", "deep_woods", "ruins", "mines", "keep", "emberscar",
	"weave", "dust_warren", "thornroot", "ember_meadows", "warlord",
	"meadow_path", "three_terraces", "gen_open", "gen_tower", "gen_cliffs",
]
const OUT_DIR := "res://docs/map_previews"
# Distinct pin colours, assigned per enemy type in order of first appearance.
const PALETTE := [
	"#ff5a5a", "#4aa3ff", "#5ad15a", "#ffc94a", "#c46aff",
	"#ff8a3d", "#3fd0c0", "#ff6fae", "#9ad34a", "#6a7bff",
]

var _enemy_color := {}    # enemy name -> hex colour (stable across all maps)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var imgs := {}
	for s in SHEETS:
		var im := Image.new()
		if im.load(SHEETS[s]) == OK:
			im.convert(Image.FORMAT_RGBA8); imgs[s] = im
	var manifest := []
	for name in MAPS:
		var entry := _render(name, imgs)
		if not entry.is_empty():
			manifest.append(entry)
			print(name, ": ", entry["img_w"], "x", entry["img_h"],
				" spawners=", entry["spawners"].size())
	var jf := FileAccess.open(OUT_DIR + "/spawns.json", FileAccess.WRITE)
	jf.store_string(JSON.stringify(manifest, "  ")); jf.close()
	print("DONE maps=", manifest.size())
	quit()

func _render(name: String, imgs: Dictionary) -> Dictionary:
	var fa := FileAccess.open("res://scenes/Levels/%s.tscn" % name, FileAccess.READ)
	if fa == null: return {}
	var text := fa.get_as_text(); fa.close()

	# ext_resource id -> path
	var ext := {}
	var ere := RegEx.new(); ere.compile('\\[ext_resource[^\\]]*\\]')
	for m in ere.search_all(text):
		var line := m.get_string(0)
		var pid := _attr(line, "id"); var path := _attr(line, "path")
		if pid != "": ext[pid] = path

	# Parse every node into {name, parent, body}.
	var nodes := _nodes(text)
	var tilemap_off := Vector2.ZERO
	var spawner_pos := {}                                  # spawner node name -> Vector2
	for n in nodes:
		if n["name"] == "TileMap": tilemap_off = _vec(n["body"], "position")

	# Render the tile layers (tight bounding box) -> minx/miny used for projection.
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
	if layers.is_empty(): return {}

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
	img.save_png("%s/%s.png" % [OUT_DIR, name])

	# Collect spawner node positions (default 0) so child markers project correctly.
	for n in nodes:
		if n["body"].find("enemy_scene = ExtResource(") != -1:
			spawner_pos[n["name"]] = _vec(n["body"], "position")

	# Build a marker lookup: parent spawner -> { markerName: Vector2 }
	var markers_by_parent := {}
	for n in nodes:
		if not spawner_pos.has(n["parent"]): continue
		markers_by_parent.get_or_add(n["parent"], {})[n["name"]] = _vec(n["body"], "position")

	# One legend entry per spawner.
	var spawners := []
	for n in nodes:
		if not spawner_pos.has(n["name"]): continue
		var eid := _ext_id(n["body"], "enemy_scene")
		var enemy := _enemy_name(ext.get(eid, ""))
		if not _enemy_color.has(enemy):
			_enemy_color[enemy] = PALETTE[_enemy_color.size() % PALETTE.size()]
		var pool := 0
		var pm := RegEx.new(); pm.compile('pool_size = (\\d+)')
		var pmm := pm.search(n["body"])
		if pmm: pool = int(pmm.get_string(1))
		# project this spawner's markers
		var sp: Vector2 = spawner_pos[n["name"]]
		var mlist := []
		var mk: Dictionary = markers_by_parent.get(n["name"], {})
		for order in _ordered_locs(n["body"]):
			if not mk.has(order): continue
			var w: Vector2 = sp + mk[order]
			var ix := int(round(w.x - tilemap_off.x - minx * 16))
			var iy := int(round(w.y - tilemap_off.y - miny * 16))
			mlist.append([ix, iy])
		spawners.append({
			"enemy": enemy, "color": _enemy_color[enemy],
			"pool_size": pool, "markers": mlist,
		})

	return {
		"name": name, "png": "%s.png" % name,
		"img_w": img.get_width(), "img_h": img.get_height(),
		"spawners": spawners,
	}

# --- scene-text helpers -------------------------------------------------------

func _nodes(text: String) -> Array:
	var res := []
	var nre := RegEx.new(); nre.compile('\\[node name="([^"]+)"([^\\]]*)\\]')
	var ms := nre.search_all(text)
	for i in ms.size():
		var m = ms[i]
		var body_end := text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
		res.append({
			"name": m.get_string(1),
			"parent": _attr(m.get_string(2), "parent"),
			"body": text.substr(m.get_end(), body_end - m.get_end()),
		})
	return res

func _attr(s: String, key: String) -> String:
	# Word-boundary so id="" does not match inside uid="".
	var re := RegEx.new(); re.compile('(?:^|[^A-Za-z_])%s="([^"]*)"' % key)
	var m := re.search(s)
	return m.get_string(1) if m else ""

func _vec(body: String, key: String) -> Vector2:
	var re := RegEx.new(); re.compile('%s = Vector2\\((-?[0-9.]+), (-?[0-9.]+)\\)' % key)
	var m := re.search(body)
	if m == null: return Vector2.ZERO
	return Vector2(float(m.get_string(1)), float(m.get_string(2)))

func _ext_id(body: String, key: String) -> String:
	var re := RegEx.new(); re.compile('%s = ExtResource\\("([^"]+)"\\)' % key)
	var m := re.search(body)
	return m.get_string(1) if m else ""

func _ordered_locs(body: String) -> Array:
	# spawn_locations = [NodePath("M0"), NodePath("M1"), ...] -> ["M0","M1",...]
	var re := RegEx.new(); re.compile('NodePath\\("([^"]+)"\\)')
	var i := body.find("spawn_locations = [")
	if i == -1: return []
	var e := body.find("]", i)
	var seg := body.substr(i, e - i)
	var out := []
	for m in re.search_all(seg): out.append(m.get_string(1))
	return out

func _enemy_name(path: String) -> String:
	if path == "": return "Enemy"
	var stem := path.get_file().get_basename()
	var parts := stem.replace("_", " ").split(" ")
	var out := []
	for p in parts:
		if p.length() > 0: out.append(p[0].to_upper() + p.substr(1))
	return " ".join(out)
