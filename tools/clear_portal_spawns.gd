extends SceneTree
## Transition safety: across every map, move any enemy spawn marker that sits within BUFFER tiles
## of a portal off to a clear stretch of floor, so portaling in never drops you onto a mob. Only
## floor-level markers near a door move (platform markers above stay); map-agnostic (matches any
## M# Marker2D regardless of spawner naming — Spawn_* or <Enemy>Spawner).
const BUFFER := 4
const MAPS := ["lanterns_rest", "near_wilds", "meadow_path", "ember_meadows", "ruins", "three_terraces", "old_battlefield", "thornroot", "dust_warren", "mines", "emberwatch", "deep_woods", "keep", "mustering_fields", "emberscar", "cinderwaste", "ashvigil", "weave", "warlord", "bramble_downs", "bandit_bluffs", "the_undercroft", "the_scorchline", "the_unraveling", "tinderfields", "brackenway", "mirefen", "stonereach", "wickmoor", "hollowmere", "the_reliquary", "wolfsreach"]

func _init() -> void:
	for m in MAPS: _do(m)
	quit()

func _do(map: String) -> void:
	var path := "res://scenes/Levels/%s.tscn" % map
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return
	var text := f.get_as_text(); f.close()
	var off := _tm_offset(text)
	var floor_top := _floor_surface(text)
	if floor_top.is_empty(): return
	var portals := _portal_cells(text, off)
	if portals.is_empty(): return
	# Floor columns clear of every portal (a free landing strip for relocated markers).
	var free := []
	for c in floor_top.keys():
		var ok := true
		for p in portals:
			if absi(c - p.x) <= BUFFER: ok = false; break
		if ok: free.append(c)
	free.sort()
	if free.is_empty(): return

	# Find every M# Marker2D + its position; relocate the ones boxed near a portal.
	var nre := RegEx.new(); nre.compile('\\[node name="M\\d+" type="Marker2D"[^\\n]*\\]\\s*\\nposition = Vector2\\((-?\\d+), (-?\\d+)\\)')
	var edits := []; var moved := 0
	for mm in nre.search_all(text):
		var wx := int(mm.get_string(1)); var wy := int(mm.get_string(2))
		var cell := Vector2i(int(round(float(wx - off.x) / 16.0)), int(round(float(wy - off.y) / 16.0)))
		var near := false
		for p in portals:
			if absi(cell.x - p.x) <= BUFFER and absi(cell.y - p.y) <= BUFFER: near = true; break
		if not near: continue
		# Move to the NEAREST clear column (stay local — don't pile everything in the left corner),
		# and consume it so multiple displaced markers don't stack on one spot.
		if free.is_empty(): break
		var bi := 0
		for k in range(free.size()):
			if absi(free[k] - cell.x) < absi(free[bi] - cell.x): bi = k
		var tc: int = free[bi]; free.remove_at(bi)
		var tr: int = floor_top[tc]
		var np := "position = Vector2(%d, %d)" % [tc * 16 + off.x + 8, (tr - 1) * 16 + off.y]
		# offset of the position substring within the match
		var pidx: int = mm.get_start() + mm.get_string().find("position = Vector2(")
		edits.append([pidx, mm.get_end(), np]); moved += 1
	if edits.is_empty(): return
	edits.sort_custom(func(a, b): return a[0] > b[0])
	for e in edits:
		text = text.substr(0, e[0]) + e[2] + text.substr(e[1])
	var w := FileAccess.open(path, FileAccess.WRITE); w.store_string(text); w.close()
	print(map, ": moved ", moved, " marker(s) off portals (", free.size(), " clear cols)")

func _portal_cells(text: String, off: Vector2i) -> Array:
	var out := []
	var is_portal := false
	for ln in text.split("\n"):
		if ln.begins_with("[node "):
			is_portal = ln.begins_with('[node name="PortalTo')
		elif is_portal and ln.begins_with("position = Vector2("):
			var p := ln.substr(19, ln.find(")") - 19).split(",")
			out.append(Vector2i(int(round((float(p[0].strip_edges()) - off.x) / 16.0)), int(round((float(p[1].strip_edges()) - off.y) / 16.0)))); is_portal = false
	return out

func _tm_offset(text: String) -> Vector2i:
	var i := text.find('name="TileMap" type="TileMap"')
	if i == -1: return Vector2i.ZERO
	var ps := text.find("position = Vector2(", i)
	var nn := text.find("\n[node", i)
	if ps == -1 or (nn != -1 and ps > nn): return Vector2i.ZERO
	var inner := text.substr(ps + 19, text.find(")", ps) - (ps + 19)).split(",")
	return Vector2i(int(inner[0].strip_edges()), int(inner[1].strip_edges()))

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
		var top: int = rows[-1]; var set := {}
		for r in rows: set[r] = true
		while set.has(top - 1): top -= 1
		out[col] = top
	return out
