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
	3: "res://assets/sprites/grass_slopes.png",
}
const MAPS := [
	"near_wilds", "deep_woods", "ruins", "mines", "keep", "emberscar",
	"weave", "dust_warren", "thornroot", "ember_meadows", "warlord",
	"meadow_path", "three_terraces", "gen_open", "gen_tower", "gen_cliffs",
]

## Hand-placed connectors for specific maps (overrides auto-inference). Each entry is
## [upper_branch_row, lower_platform_row, column] in tile coords; the ladder hangs from
## the upper branch with its bottom dangling ~1.5 tiles above the lower platform.
const MANUAL_CONNECTORS := {
	"gen_tower": [
		[11, 17, 33],   # top -> 30-32
		[25, 31, 7],    # 25-27 -> 24 (off-shoot, same level as 21-23)
		[25, 31, 23],   # 25-27 -> 21-23
		[31, 42, 18],   # 21-23 -> 15-17 (long)
		[31, 37, 35],   # 21-23 -> 18-20
		[37, 42, 30],   # 18-20 -> 15-17
		[46, 51, 6],    # 13-14 -> floor (left)
		[46, 51, 18],   # 13-14 -> floor (right)
	],
	"gen_cliffs": [
		[14, 22, 27, "rope"],     # mesa-1 shelf -> mesa 1
		[11, 19, 43, "ladder"],   # peak shelf -> peak
		[16, 22, 58, "rope"],     # mesa-3 shelf -> mesa 3
	],
	# Mirrors _open()'s ladder set. Floor climbers' lower row is approximated at FLOOR_Y here
	# (the real ones read the rolling surf); shelf-to-shelf rows are exact.
	"near_wilds": [
		[20, 26, 12, "rope"], [20, 26, 45, "rope"],
		[20, 26, 77, "rope"], [20, 26, 107, "rope"],
	],
	"gen_open": [
		[20, 26, 14, "ladder"],   # floor -> L1a
		[20, 26, 60, "rope"],     # floor -> L1a
		[20, 26, 100, "ladder"],  # floor -> L1b
		[20, 26, 134, "rope"],    # floor -> L1b
		[15, 20, 30, "rope"],     # L1a -> L2
		[15, 20, 88, "ladder"],   # L1b -> L2
		[10, 15, 54, "rope"],     # L2 -> L3
		[10, 15, 92, "ladder"],   # L2 -> L3
	],
}
## Proposed portal placements per map: [edge, destination-label]. A doorway sits on the
## ground a few tiles in from that edge, pointing to the neighbouring region (mirrors the
## map's MapManager connections). Like the connector proposals — shown for review.
const MANUAL_PORTALS := {
	"near_wilds": [["left", "Lantern's Rest"], ["right", "Ember-Meadows"]],
}
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

	var player_spawn := {}
	for n in nodes:
		if n["name"] == "PlayerSpawn":
			var pp := _vec(n["body"], "position")
			player_spawn = {"x": int(round(pp.x - tilemap_off.x - minx * 16)), "y": int(round(pp.y - tilemap_off.y - miny * 16))}
			break

	return {
		"name": name, "png": "%s.png" % name,
		"img_w": img.get_width(), "img_h": img.get_height(),
		"spawners": spawners,
		"player_spawn": player_spawn,
		"connectors": _connectors_for(name, layers, minx, miny),
		"portals": _portals_for(name, layers, minx, miny, maxx),
	}

## Hand-placed connectors if the map has an entry, else the auto-inferred ones.
func _connectors_for(name: String, layers: Array, minx: int, miny: int) -> Array:
	if MANUAL_CONNECTORS.has(name):
		var out := []
		for t in MANUAL_CONNECTORS[name]:
			out.append({
				"x": (t[2] - minx) * 16 + 8,
				"y_top": (t[0] - miny) * 16 - 1,
				"y_bottom": (t[1] - miny) * 16 - 24,
				"type": t[3] if t.size() > 3 else "ladder",
			})
		return out
	return _infer_connectors(layers, minx, miny)

## Propose a doorway on the ground a few tiles in from each edge for every neighbour, so the
## preview shows where portals should land. Surface = topmost solid ground/slope cell per
## column (one-way platforms + props excluded). Returns image-pixel rects {x, y_top, y_bottom}.
func _portals_for(name: String, layers: Array, minx: int, miny: int, maxx: int) -> Array:
	if not MANUAL_PORTALS.has(name): return []
	var top := {}
	for cells in layers:
		for c in cells:
			var src: int = cells[c][0]
			var ax: Vector2i = cells[c][1]
			var is_ground: bool = src == 3 or (src == 1 and not (ax.y == 9 and ax.x >= 17 and ax.x <= 19))
			if is_ground and (not top.has(c.x) or c.y < top[c.x]): top[c.x] = c.y
	var out := []
	for p in MANUAL_PORTALS[name]:
		var col: int = (minx + 4) if p[0] == "left" else (maxx - 4)
		while not top.has(col) and col > minx and col < maxx:
			col += 1 if p[0] == "left" else -1
		if not top.has(col): continue
		var surf: int = top[col]
		out.append({
			"x": (col - minx) * 16 + 8,
			"y_bottom": (surf - miny) * 16,
			"y_top": (surf - miny) * 16 - 44,
			"dest": p[1], "side": p[0],
		})
	return out

# --- connector inference ------------------------------------------------------

## Propose where ropes/ladders should go: for each wide platform, find the nearest
## wide surface 3-9 tiles below that overlaps it horizontally, and put a connector in
## the overlap. Returns image-pixel rects {x, y_top, y_bottom, type}. Map-agnostic.
func _infer_connectors(layers: Array, minx: int, miny: int) -> Array:
	# Occupancy of every platform/ground tile + the walkable surface rows (so we pick
	# wide branches as the "top" a ladder hangs from).
	var occupied := {}
	var surf_rows := {}
	var ground_top := {}
	for cells in layers:
		for c in cells:
			occupied[c] = true
			var src: int = cells[c][0]
			var ax: Vector2i = cells[c][1]
			if src == 1 and ax.y == 9 and ax.x >= 17 and ax.x <= 19:   # one-way platform tiles
				if not surf_rows.has(c.y): surf_rows[c.y] = {}
				surf_rows[c.y][c.x] = true
			elif not ground_top.has(c.x) or c.y < ground_top[c.x]:
				ground_top[c.x] = c.y
	for col in ground_top:
		var r: int = ground_top[col]
		if not surf_rows.has(r): surf_rows[r] = {}
		surf_rows[r][col] = true
	# group each row's columns into contiguous segments [row, x0, x1]; map each surface
	# cell to its segment so we can identify the platform directly below any column.
	var segs := []
	var seg_of := {}
	for r in surf_rows:
		var xs = surf_rows[r].keys(); xs.sort()
		var s: int = xs[0]; var p: int = xs[0]
		for k in range(1, xs.size()):
			if xs[k] == p + 1:
				p = xs[k]
			else:
				_add_seg(segs, seg_of, r, s, p); s = xs[k]; p = xs[k]
		_add_seg(segs, seg_of, r, s, p)
	# Each platform hangs a ladder down to EACH distinct platform directly below it — the
	# first surface hit scanning straight down a column, 3-12 tiles below. Scanning a
	# single column guarantees no pass-through; doing it across the whole platform gives a
	# ladder on each side that sits over a DIFFERENT lower platform (so e.g. the 25-27
	# branch drops one to the ledge toward 24 and another down to 21-23). Ladder hangs
	# from the platform; bottom dangles ~1.5 tiles above the lower one (jump-grab).
	var conns := []
	for u in segs:
		if u[2] - u[1] + 1 < 6: continue        # only wide fighting branches drop ladders
		var mid := int((u[1] + u[2]) / 2.0)
		var picks := {}                          # lower_seg_idx -> column (deduped)
		# left end: first column (scanning inward from the left) that overhangs a platform
		for c in range(u[1], mid + 1):
			var lo := _first_below(occupied, seg_of, c, u[0])
			if lo[0] != -1:
				if not picks.has(lo[0]): picks[lo[0]] = c
				break
		# right end: first column scanning inward from the right
		for c in range(u[2], mid - 1, -1):
			var lo := _first_below(occupied, seg_of, c, u[0])
			if lo[0] != -1:
				if not picks.has(lo[0]): picks[lo[0]] = c
				break
		for li in picks:
			var lo_seg = segs[li]
			var col := _overlap_col(u, lo_seg, occupied)   # centre the ladder in the overlap
			if col == -1: col = picks[li]
			conns.append({
				"x": (col - minx) * 16 + 8,
				"y_top": (u[0] - miny) * 16 - 1,
				"y_bottom": (lo_seg[0] - miny) * 16 - 24,
				"type": "ladder",
			})
	return conns

## The platform (seg index) + row directly below column `c` starting at row `urow`,
## but only if it is 3-12 tiles down (closer = jumpable, no ladder). Else [-1, -1].
func _first_below(occupied: Dictionary, seg_of: Dictionary, c: int, urow: int) -> Array:
	for rr in range(urow + 1, urow + 13):
		if occupied.has(Vector2i(c, rr)):
			if rr - urow >= 3: return [seg_of.get(Vector2i(c, rr), -1), rr]
			return [-1, -1]
	return [-1, -1]

## The clean column nearest the CENTRE of where `u` overhangs `lo` (scanning straight
## down hits `lo` first — never through an intermediate platform). -1 if none.
func _overlap_col(u: Array, lo: Array, occupied: Dictionary) -> int:
	var ox0: int = maxi(u[1], lo[1])
	var ox1: int = mini(u[2], lo[2])
	if ox1 < ox0: return -1
	var center := int((ox0 + ox1) / 2.0)
	var best := -1
	var bestd := 99999
	for c in range(ox0, ox1 + 1):
		var hit := -1
		for rr in range(u[0] + 1, lo[0] + 1):
			if occupied.has(Vector2i(c, rr)): hit = rr; break
		if hit == lo[0]:
			var d: int = absi(c - center)
			if d < bestd: bestd = d; best = c
	return best

func _add_seg(segs: Array, seg_of: Dictionary, r: int, x0: int, x1: int) -> void:
	var idx := segs.size()
	segs.append([r, x0, x1])
	for c in range(x0, x1 + 1): seg_of[Vector2i(c, r)] = idx

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
