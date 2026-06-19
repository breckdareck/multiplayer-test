extends SceneTree
## Rebuild the whole world's portal graph (branching, MapleStory-style) from GRAPH below.
## Per map: clear old portal instances + *_Portal_Spawn markers, then lay one (portal + co-located
## arrival marker) pair per connection, spread across the map's FLOOR (seated on the ground),
## ordered left->right by destination level (walk right to progress). Arrival/target names follow
## the <ThisToken>_<OtherToken>_Portal_Spawn convention. Verify with the print + a grep after.
const PORTAL_UID := "uid://brfb5t5im33fl"
# RADIAL "Sleepywood" world (2026-06-18): a low OUTER RING of 3 Hearths + low fields
# (a walkable loop), three SPOKES climbing inward from the ring Hearths, converging at
# the central Hearth Emberwatch, then a single deep CORE descent to the Warlord at the
# dead centre. Symmetric adjacency — every edge appears on both endpoints. (Maps are
# still 2D side-scrollers; the wheel is the world-map view + the connection graph.)
const GRAPH := {
	# --- Outer ring: walkable low loop (3 Hearths + 6 low fields) ---
	"lanterns_rest": ["near_wilds", "brackenway", "ruins"],
	"near_wilds": ["lanterns_rest", "meadow_path"],
	"meadow_path": ["near_wilds", "wickmoor"],
	"wickmoor": ["meadow_path", "tinderfields", "three_terraces"],
	"tinderfields": ["wickmoor", "ember_meadows"],
	"ember_meadows": ["tinderfields", "hollowmere"],
	"hollowmere": ["ember_meadows", "bramble_downs", "mirefen"],
	"bramble_downs": ["hollowmere", "brackenway"],
	"brackenway": ["bramble_downs", "lanterns_rest"],
	# --- Spoke 1 (from Lantern's Rest): the delve — 4 maps to Emberwatch ---
	"ruins": ["lanterns_rest", "old_battlefield"],
	"old_battlefield": ["ruins", "thornroot"],
	"thornroot": ["old_battlefield", "the_reliquary"],
	"the_reliquary": ["thornroot", "emberwatch"],
	# --- Spoke 2 (from Wickmoor): the overland trail — 4 maps to Emberwatch ---
	"three_terraces": ["wickmoor", "bandit_bluffs"],
	"bandit_bluffs": ["three_terraces", "dust_warren"],
	"dust_warren": ["bandit_bluffs", "wolfsreach"],
	"wolfsreach": ["dust_warren", "emberwatch"],
	# --- Spoke 3 (from Hollowmere): the deep road — 4 maps to Emberwatch ---
	"mirefen": ["hollowmere", "stonereach"],
	"stonereach": ["mirefen", "mines"],
	"mines": ["stonereach", "the_undercroft"],
	"the_undercroft": ["mines", "emberwatch"],
	# --- Central Hearth + the Core descent to the centre ---
	"emberwatch": ["the_reliquary", "wolfsreach", "the_undercroft", "deep_woods"],
	"deep_woods": ["emberwatch", "keep"],
	"keep": ["deep_woods", "mustering_fields"],
	"mustering_fields": ["keep", "the_scorchline"],
	"the_scorchline": ["mustering_fields", "emberscar"],
	"emberscar": ["the_scorchline", "cinderwaste"],
	"cinderwaste": ["emberscar", "weave"],
	"weave": ["cinderwaste", "the_unraveling"],
	"the_unraveling": ["weave", "ashvigil"],
	"ashvigil": ["the_unraveling", "warlord"],
	"warlord": ["ashvigil"],
}
const TOKEN := {
	"lanterns_rest": "LanternsRest", "near_wilds": "NearWilds", "meadow_path": "Meadow",
	"ember_meadows": "EmberMeadows", "ruins": "Ruins", "three_terraces": "Terraces",
	"thornroot": "Thornroot", "dust_warren": "DustWarren", "mines": "Mines",
	"emberwatch": "Emberwatch", "deep_woods": "DeepWoods", "keep": "Keep",
	"emberscar": "Emberscar", "weave": "Weave", "warlord": "Warlord",
	"old_battlefield": "OldBattlefield", "mustering_fields": "MusteringFields",
	"ashvigil": "Ashvigil", "cinderwaste": "Cinderwaste",
	"bramble_downs": "Bramble", "bandit_bluffs": "BanditBluffs",
	"the_undercroft": "Undercroft", "the_scorchline": "Scorchline",
	"the_unraveling": "Unraveling", "wickmoor": "Wickmoor", "hollowmere": "Hollowmere",
	"tinderfields": "Tinderfields", "brackenway": "Brackenway",
	"mirefen": "Mirefen", "stonereach": "Stonereach",
	"the_reliquary": "Reliquary", "wolfsreach": "Wolfsreach",
}
const LEVEL := {
	"lanterns_rest": 0, "wickmoor": 0, "hollowmere": 0,
	"near_wilds": 5, "meadow_path": 6, "tinderfields": 8, "ember_meadows": 10,
	"bramble_downs": 12, "brackenway": 14,
	"ruins": 20, "three_terraces": 22, "old_battlefield": 24, "mirefen": 26,
	"bandit_bluffs": 30, "thornroot": 33, "stonereach": 38, "dust_warren": 40,
	"the_reliquary": 40, "mines": 44, "wolfsreach": 44, "the_undercroft": 46, "emberwatch": 48,
	"deep_woods": 55, "keep": 60, "mustering_fields": 66, "the_scorchline": 72,
	"emberscar": 78, "cinderwaste": 84, "weave": 90, "the_unraveling": 94,
	"ashvigil": 96, "warlord": 100,
}

func _init() -> void:
	for map in GRAPH: _do_map(map)
	quit()

func _do_map(map: String) -> void:
	var path := "res://scenes/Levels/%s.tscn" % map
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: print(map, ": NO SCENE"); return
	var text := f.get_as_text(); f.close()

	var pid := _portal_id(text)
	if pid == "":
		pid = "portal_gen"
		var ins := text.find("\n", text.find("[gd_scene")) + 1
		text = text.substr(0, ins) + '[ext_resource type="PackedScene" uid="%s" path="res://scenes/Gameplay/portal.tscn" id="%s"]\n' % [PORTAL_UID, pid] + text.substr(ins)

	text = _clear(text, pid)
	var off := _tm_offset(text)
	var floor_top := _floor_surface(text)
	if floor_top.is_empty(): print(map, ": NO FLOOR"); return
	var cols := floor_top.keys(); cols.sort()
	var mincol: int = cols[0]; var maxcol: int = cols[-1]
	var third: int = int((maxcol - mincol) / 3.0)
	# Elevated platforms (above the floor) near each side edge — branch portals stack on these.
	var left_elev := []; var right_elev := []
	for c in _elevated(text, floor_top):
		if c.x <= mincol + third: left_elev.append(c)
		elif c.x >= maxcol - third: right_elev.append(c)
	left_elev.sort_custom(func(a, b): return a.x < b.x)    # closest to left edge first
	right_elev.sort_custom(func(a, b): return a.x > b.x)   # closest to right edge first

	var conns: Array = GRAPH[map].duplicate()
	conns.sort_custom(func(a, b): return LEVEL[a] < LEVEL[b])
	var n: int = conns.size()
	# Placement: lowest-level dest on the LEFT edge, highest on the RIGHT edge (the two side doors);
	# branch portals go on an elevated platform near a side, stacked above the side door — alternating
	# right/left so a 3rd door sits over the right edge, a 4th over the left.
	var place := []; place.resize(n)
	var center := (mincol + maxcol) / 2.0
	var lc: int = _flat_near(floor_top, mincol + 3, 1, mincol, maxcol); place[0] = Vector2i(lc, floor_top[lc])
	if n >= 2:
		var rc: int = _flat_near(floor_top, maxcol - 1, -1, mincol, maxcol); place[n - 1] = Vector2i(rc, floor_top[rc])
	var b := 0
	for i in range(1, n - 1):
		var pri = right_elev if b % 2 == 0 else left_elev
		var alt = left_elev if b % 2 == 0 else right_elev
		if not pri.is_empty(): place[i] = pri.pop_front()
		elif not alt.is_empty(): place[i] = alt.pop_front()
		else:  # no elevated platform — fall back to an inset floor spot near a side
			var fc: int = _nearest(floor_top, (maxcol - 10) if b % 2 == 0 else (mincol + 10))
			place[i] = Vector2i(fc, floor_top[fc])
		b += 1

	var body := ""
	for i in n:
		var other: String = conns[i]
		var px: int = place[i].x * 16 + off.x
		var py: int = place[i].y * 16 + off.y
		# Portal sits 16px ABOVE the surface (foot rests on it); arrival marker 12px above (land on it).
		body += '\n[node name="PortalTo%s" parent="." instance=ExtResource("%s")]\n' % [TOKEN[other], pid]
		body += 'position = Vector2(%d, %d)\n' % [px, py - 16]
		body += 'target_map_id = "%s"\n' % other
		body += 'target_spawn_point_name = "%s_%s_Portal_Spawn"\n' % [TOKEN[other], TOKEN[map]]
		# Arrival on the INNER side of the door: left-side portal -> spawn to its right; right-side -> left.
		var dx: int = 24 if place[i].x <= center else -24
		body += '\n[node name="%s_%s_Portal_Spawn" type="Marker2D" parent="."]\n' % [TOKEN[map], TOKEN[other]]
		body += 'position = Vector2(%d, %d)\n' % [px + dx, py - 12]

	text = text.rstrip("\n") + "\n" + body
	var w := FileAccess.open(path, FileAccess.WRITE); w.store_string(text); w.close()
	print(map, ": ", n, " portals -> ", conns)

func _portal_id(text: String) -> String:
	var i := text.find('path="res://scenes/Gameplay/portal.tscn"')
	if i == -1: return ""
	var idi := text.find('id="', i)
	var e := text.find('"', idi + 4)
	return text.substr(idi + 4, e - (idi + 4))

# Remove every portal-instance node and *_Portal_Spawn marker node (header -> next [node / EOF).
func _clear(text: String, pid: String) -> String:
	var heads := []
	var s := 0
	while true:
		var i := text.find("\n[node ", s)
		if i == -1: break
		heads.append(i + 1); s = i + 1
	heads.reverse()
	for h in heads:
		var le := text.find("]", h)
		var header := text.substr(h, le - h + 1)
		var is_portal := ('instance=ExtResource("%s")' % pid) in header
		var is_marker := '_Portal_Spawn"' in header and 'type="Marker2D"' in header
		if is_portal or is_marker:
			var nxt := text.find("\n[node ", h)
			var end := text.length() if nxt == -1 else nxt + 1
			text = text.substr(0, h) + text.substr(end)
	return text

func _tm_offset(text: String) -> Vector2i:
	var i := text.find('name="TileMap" type="TileMap"')
	if i == -1: return Vector2i.ZERO
	var ps := text.find("position = Vector2(", i)
	var nn := text.find("\n[node", i)
	if ps == -1 or (nn != -1 and ps > nn): return Vector2i.ZERO
	var inner := text.substr(ps + 19, text.find(")", ps) - (ps + 19)).split(",")
	return Vector2i(int(inner[0].strip_edges()), int(inner[1].strip_edges()))

# Per column, the top of the bottom-most contiguous solid run = the ground surface there.
func _floor_surface(text: String) -> Dictionary:
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
		var top: int = rows[-1]
		var set := {}
		for r in rows: set[r] = true
		while set.has(top - 1): top -= 1
		out[col] = top
	return out

# All used cells of a named TileMapLayer.
func _decode_layer(text: String, lname: String) -> Array:
	var i := text.find('name="%s" type="TileMapLayer"' % lname)
	if i == -1: return []
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, i)
	var nn := text.find("\n[node", i)
	if di == -1 or (nn != -1 and di > nn): return []
	var s := di + key.length()
	var l := TileMapLayer.new(); l.tile_map_data = Marshalls.base64_to_raw(text.substr(s, text.find('"', s) - s))
	var cells := l.get_used_cells(); l.free(); return cells

# Flat surface cells (Mid + Platform) sitting ABOVE the floor — the shelves/tiers branch portals stack on.
func _elevated(text: String, floor_top: Dictionary) -> Array:
	var up := Vector2i(0, -1)
	var solid := {}
	for ln in ["Mid", "Platform"]:
		for c in _decode_layer(text, ln): solid[c] = true
	var out := []
	for c in solid:
		if solid.has(c + up): continue
		if not floor_top.has(c.x) or c.y >= int(floor_top[c.x]) - 1: continue   # the floor itself, not a shelf
		var l := Vector2i(c.x - 1, c.y); var r := Vector2i(c.x + 1, c.y)
		if solid.has(l) and not solid.has(l + up) and solid.has(r) and not solid.has(r + up):
			out.append(c)
	return out

# Scan from start_col in `dir` for a FLAT floor column (same surface row as both neighbours — not a slope).
func _flat_near(floor_top: Dictionary, start_col: int, dir: int, mincol: int, maxcol: int) -> int:
	var col := start_col
	for _i in range(220):
		if floor_top.has(col) and floor_top.has(col - 1) and floor_top.has(col + 1) and floor_top[col] == floor_top[col - 1] and floor_top[col] == floor_top[col + 1]:
			return col
		col += dir
		if col < mincol or col > maxcol: break
	return _nearest(floor_top, start_col)

func _nearest(floor_top: Dictionary, col: int) -> int:
	if floor_top.has(col): return col
	for d in range(1, 200):
		if floor_top.has(col - d): return col - d
		if floor_top.has(col + d): return col + d
	return floor_top.keys()[0]
