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
## CROSSWAY world (Stage 2, 2026-06-19): replacing the radial wheel, one town arm at a time.
## Lantern's Rest arm is BUILT first: town -> branchy LOW FRONTIER (Lv2-16, pockets off the spine)
## -> linear CLIMB (Lv17-47) -> Emberwatch (halfway) -> the Core descent (back half, unchanged).
## The Wickmoor / Hollowmere arms + the old ring/spoke maps are intentionally DROPPED from the graph
## (their scenes remain on disk, unwired & unreachable) until they're cloned in a later stage.
const GRAPH := {
	# FISHBONE (opt7 mockup): Lantern's Rest in the MIDDLE — a branchy LOW FRONTIER of dead-end
	# grinding pockets hangs off one side; a straight CLIMB to Emberwatch runs off the other.
	"lanterns_rest": ["near_wilds", "old_causeway"],
	# --- LOW FRONTIER spine (the main side-grind path, ascending away from town) ---
	"near_wilds": ["lanterns_rest", "glimmerfen", "firefly_hollow"],
	"glimmerfen": ["near_wilds", "tinderfields", "brackenway"],
	"tinderfields": ["glimmerfen", "ember_meadows", "lanternwood"],
	"ember_meadows": ["tinderfields", "hollow_warren"],
	# --- LOW FRONTIER pockets (dead-end grinding chains hanging off the spine) ---
	"firefly_hollow": ["near_wilds", "meadow_path"],
	"meadow_path": ["firefly_hollow"],
	"brackenway": ["glimmerfen", "bramble_downs"],
	"bramble_downs": ["brackenway"],
	"lanternwood": ["tinderfields", "watchers_ruin"],
	"watchers_ruin": ["lanternwood"],
	"hollow_warren": ["ember_meadows", "beacon_rise"],
	"beacon_rise": ["hollow_warren"],
	# --- the CLIMB to Emberwatch (Lv18-47): the straight inward ascent ---
	"old_causeway": ["lanterns_rest", "ruins"],
	"ruins": ["old_causeway", "thornroot"],
	"thornroot": ["ruins", "old_battlefield"],
	"old_battlefield": ["thornroot", "the_reliquary"],
	"the_reliquary": ["old_battlefield", "embergate"],
	"embergate": ["the_reliquary", "emberwatch"],
	# === WICKMOOR arm (drowned moor) — same fishbone, parallel Lv2-48 to Emberwatch ===
	"wickmoor": ["reedmire", "long_ford"],
	"reedmire": ["wickmoor", "sodden_flats", "glowmoss_burrow"],
	"sodden_flats": ["reedmire", "heatherreach", "the_brackens"],
	"heatherreach": ["sodden_flats", "blackpeat", "willowmere"],
	"blackpeat": ["heatherreach", "mudwarren"],
	"glowmoss_burrow": ["reedmire", "peat_steps"],
	"peat_steps": ["glowmoss_burrow"],
	"the_brackens": ["sodden_flats", "gorse_downs"],
	"gorse_downs": ["the_brackens"],
	"willowmere": ["heatherreach", "drowned_shrine"],
	"drowned_shrine": ["willowmere"],
	"mudwarren": ["blackpeat", "bogbeacon"],
	"bogbeacon": ["mudwarren"],
	"long_ford": ["wickmoor", "the_sluice"],
	"the_sluice": ["long_ford", "mirewarren"],
	"mirewarren": ["the_sluice", "bonemarsh"],
	"bonemarsh": ["mirewarren", "the_oubliette"],
	"the_oubliette": ["bonemarsh", "marshgate"],
	"marshgate": ["the_oubliette", "emberwatch"],
	# === HOLLOWMERE arm (stone crags) — same fishbone, parallel Lv2-48 to Emberwatch ===
	"hollowmere": ["the_shallows", "stone_span"],
	"the_shallows": ["hollowmere", "craghollow", "pebble_warren"],
	"craghollow": ["the_shallows", "echo_downs", "gullstone_bluffs"],
	"echo_downs": ["craghollow", "greymoor", "mistfield"],
	"greymoor": ["echo_downs", "hollow_deep"],
	"pebble_warren": ["the_shallows", "cairn_steps"],
	"cairn_steps": ["pebble_warren"],
	"gullstone_bluffs": ["craghollow", "windward_downs"],
	"windward_downs": ["gullstone_bluffs"],
	"mistfield": ["echo_downs", "sunken_hall"],
	"sunken_hall": ["mistfield"],
	"hollow_deep": ["greymoor", "beacon_crag"],
	"beacon_crag": ["hollow_deep"],
	"stone_span": ["hollowmere", "riftway"],
	"riftway": ["stone_span", "gravewarren"],
	"gravewarren": ["riftway", "shattercliffs"],
	"shattercliffs": ["gravewarren", "deepshaft"],
	"deepshaft": ["shattercliffs", "hollowgate"],
	"hollowgate": ["deepshaft", "emberwatch"],
	# --- Central Hearth (3 arms converge) + the Core descent (back half, unchanged) ---
	"emberwatch": ["embergate", "marshgate", "hollowgate", "deep_woods"],
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
	"firefly_hollow": "FireflyHollow", "glimmerfen": "Glimmerfen", "lanternwood": "Lanternwood",
	"hollow_warren": "HollowWarren", "watchers_ruin": "WatchersRuin", "beacon_rise": "BeaconRise",
	"old_causeway": "OldCauseway", "embergate": "Embergate",
	# Wickmoor arm
	"reedmire": "Reedmire", "sodden_flats": "SoddenFlats", "heatherreach": "Heatherreach",
	"blackpeat": "Blackpeat", "glowmoss_burrow": "GlowmossBurrow", "peat_steps": "PeatSteps",
	"the_brackens": "Brackens", "gorse_downs": "GorseDowns", "willowmere": "Willowmere",
	"drowned_shrine": "DrownedShrine", "mudwarren": "Mudwarren", "bogbeacon": "Bogbeacon",
	"long_ford": "LongFord", "the_sluice": "Sluice", "mirewarren": "Mirewarren",
	"bonemarsh": "Bonemarsh", "the_oubliette": "Oubliette", "marshgate": "Marshgate",
	# Hollowmere arm
	"the_shallows": "Shallows", "craghollow": "Craghollow", "echo_downs": "EchoDowns",
	"greymoor": "Greymoor", "pebble_warren": "PebbleWarren", "cairn_steps": "CairnSteps",
	"gullstone_bluffs": "GullstoneBluffs", "windward_downs": "WindwardDowns", "mistfield": "Mistfield",
	"sunken_hall": "SunkenHall", "hollow_deep": "HollowDeep", "beacon_crag": "BeaconCrag",
	"stone_span": "StoneSpan", "riftway": "Riftway", "gravewarren": "Gravewarren",
	"shattercliffs": "Shattercliffs", "deepshaft": "Deepshaft", "hollowgate": "Hollowgate",
}
## Per-map level — used ONLY to decide each portal's side (higher dest = RIGHT door / progress,
## lower = LEFT / backtrack), so both ends of an edge land on opposite sides. Values track the
## Lantern's-arm roster bands; equal levels fall back to a name tiebreak.
const LEVEL := {
	"lanterns_rest": 0,
	"firefly_hollow": 3, "near_wilds": 4, "meadow_path": 5, "brackenway": 6,
	"glimmerfen": 7, "bramble_downs": 8, "lanternwood": 10, "tinderfields": 11,
	"ember_meadows": 12, "hollow_warren": 13, "watchers_ruin": 14, "beacon_rise": 16,
	"old_causeway": 20, "ruins": 25, "thornroot": 31, "old_battlefield": 37,
	"the_reliquary": 42, "embergate": 46, "emberwatch": 48,
	# Wickmoor + Hollowmere arms (same per-slot bands as Lantern's): towns 0; spine 5/7/11/12;
	# pockets 4/6/7/9/10/15/14/17; climb 20/25/31/37/42/46.
	"wickmoor": 0, "hollowmere": 0,
	"reedmire": 5, "sodden_flats": 7, "heatherreach": 11, "blackpeat": 12,
	"glowmoss_burrow": 4, "peat_steps": 6, "the_brackens": 7, "gorse_downs": 9,
	"willowmere": 10, "drowned_shrine": 15, "mudwarren": 14, "bogbeacon": 17,
	"long_ford": 20, "the_sluice": 25, "mirewarren": 31, "bonemarsh": 37, "the_oubliette": 42, "marshgate": 46,
	"the_shallows": 5, "craghollow": 7, "echo_downs": 11, "greymoor": 12,
	"pebble_warren": 4, "cairn_steps": 6, "gullstone_bluffs": 7, "windward_downs": 9,
	"mistfield": 10, "sunken_hall": 15, "hollow_deep": 14, "beacon_crag": 17,
	"stone_span": 20, "riftway": 25, "gravewarren": 31, "shattercliffs": 37, "deepshaft": 42, "hollowgate": 46,
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
	var my_level: int = LEVEL[map]
	var n: int = conns.size()
	var center := (mincol + maxcol) / 2.0

	# Per-edge SIDE, decided ONLY from the (this, other) level pair — so BOTH endpoints
	# of an edge agree and end up on OPPOSITE sides: exit right <-> arrive left, always.
	# Forward (higher-level destination) = RIGHT door (walk right to progress); a
	# lower-level destination = LEFT door (backtrack). Equal levels use a symmetric
	# name tiebreak so the two ends still disagree on side.
	var right_side := []   # forward / progress
	var left_side := []    # backward / return
	for other in conns:
		var fwd: bool = (LEVEL[other] > my_level) if LEVEL[other] != my_level else (map < other)
		if fwd: right_side.append(other)
		else: left_side.append(other)
	right_side.sort_custom(func(a, c): return LEVEL[a] < LEVEL[c])   # easiest forward at the floor edge
	left_side.sort_custom(func(a, c): return LEVEL[a] > LEVEL[c])    # nearest backward at the floor edge

	# Seat each side's doors: the primary on that side's floor edge, extras on an
	# elevated shelf if one exists, else fanned across that HALF so multi-door hubs
	# never push a door past the centre line (which would flip its apparent side).
	var pos_by_other := {}
	_place_side(right_side, floor_top, mincol, maxcol, center, true, right_elev, pos_by_other)
	_place_side(left_side, floor_top, mincol, maxcol, center, false, left_elev, pos_by_other)

	var body := ""
	for i in n:
		var other: String = conns[i]
		var p: Vector2i = pos_by_other[other]
		var px: int = p.x * 16 + off.x
		var py: int = p.y * 16 + off.y
		# Portal sits 16px ABOVE the surface (foot rests on it); arrival marker 12px above (land on it).
		body += '\n[node name="PortalTo%s" parent="." instance=ExtResource("%s")]\n' % [TOKEN[other], pid]
		body += 'position = Vector2(%d, %d)\n' % [px, py - 16]
		body += 'target_map_id = "%s"\n' % other
		body += 'target_spawn_point_name = "%s_%s_Portal_Spawn"\n' % [TOKEN[other], TOKEN[map]]
		# Arrival on the INNER side of the door: left-side portal -> spawn to its right; right-side -> left.
		var dx: int = 24 if p.x <= center else -24
		body += '\n[node name="%s_%s_Portal_Spawn" type="Marker2D" parent="."]\n' % [TOKEN[map], TOKEN[other]]
		body += 'position = Vector2(%d, %d)\n' % [px + dx, py - 12]

	text = text.rstrip("\n") + "\n" + body
	var w := FileAccess.open(path, FileAccess.WRITE); w.store_string(text); w.close()
	print(map, ": ", n, " portals -> ", conns)

# Seat a side's doors. j==0 -> the floor EDGE (flat seat). Extras -> an elevated
# shelf on that side if available, else fanned evenly across that half toward (but
# never past) the centre, so every door stays unambiguously on its side.
func _place_side(group: Array, floor_top: Dictionary, mincol: int, maxcol: int, center: float, is_right: bool, elev: Array, out: Dictionary) -> void:
	var k: int = group.size()
	for j in k:
		var other: String = group[j]
		if j == 0:
			var ec: int = _flat_near(floor_top, (maxcol - 1) if is_right else (mincol + 3), -1 if is_right else 1, mincol, maxcol)
			out[other] = Vector2i(ec, floor_top[ec])
		elif not elev.is_empty():
			out[other] = elev.pop_front()
		else:
			var edge := float(maxcol - 1) if is_right else float(mincol + 3)
			var inner := center + (4.0 if is_right else -4.0)
			var target := int(lerp(edge, inner, float(j) / float(k)))
			var col: int = _nearest(floor_top, target)
			out[other] = Vector2i(col, floor_top[col])


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
