extends SceneTree
## Read-only audit of portal PLACEMENT in every level scene:
##  1) GROUND: each portal sits ~on the floor surface at its column (not floating/buried).
##  2) SIDES: for each edge A<->B, A's door to B and B's door to A are on OPPOSITE map halves
##     (so you exit one side and arrive on the opposite side of the next map).
## Prints per-map portal sides + any violations. Mutates nothing.
const LVL := "res://scenes/Levels/"

func _init() -> void:
	var maps := {}   # mid -> { center, portals: { target: {col,row,side,gy_expected,gy_actual,on_ground} } }
	var dir := DirAccess.open(LVL)
	var files := dir.get_files(); files.sort()
	for f in files:
		if not f.ends_with(".tscn"): continue
		var mid := f.get_basename()
		if mid in ["map_template"]: continue
		var text := FileAccess.open(LVL + f, FileAccess.READ).get_as_text()
		var floor_top := _floor_surface(text)
		if floor_top.is_empty(): continue            # no standard floor layer (town/hub) -> skip
		var off := _tm_offset(text)
		var cols: Array = floor_top.keys(); cols.sort()
		var center: float = (float(cols[0]) + float(cols[-1])) / 2.0
		var portals := {}
		for blk in text.split("\n[node "):
			var tmm := _re(blk, 'target_map_id\\s*=\\s*"([^"]+)"')
			if tmm == "": continue
			var pm := _re(blk, 'position = Vector2\\(([-0-9.]+), ([-0-9.]+)\\)')
			if pm == "": continue
			var parts := pm.split("|")
			var px := float(parts[0]); var py := float(parts[1])
			var col := int(round((px - off.x) / 16.0))
			var side := "L" if col < center else "R"
			var on_ground := false; var gy_exp := 0.0
			var fcol := col
			if not floor_top.has(fcol):                # nudge to nearest floor column
				for d in range(1, 6):
					if floor_top.has(col - d): fcol = col - d; break
					if floor_top.has(col + d): fcol = col + d; break
			if floor_top.has(fcol):
				gy_exp = float(floor_top[fcol]) * 16.0 + float(off.y) - 16.0   # portal raised 16px above floor
				on_ground = abs(py - gy_exp) <= 24.0
			portals[tmm] = {"col": col, "side": side, "ground": on_ground, "dy": py - gy_exp}
		maps[mid] = {"center": center, "portals": portals}

	var ground_bad := []; var side_bad := []; var total := 0
	for mid in maps:
		for tgt in maps[mid]["portals"]:
			total += 1
			var p = maps[mid]["portals"][tgt]
			if not p["ground"]:
				ground_bad.append("%s -> %s  (off ground by %d px, side %s)" % [mid, tgt, int(p["dy"]), p["side"]])
	# side opposition per edge
	var checked := {}
	for mid in maps:
		for tgt in maps[mid]["portals"]:
			var key: String = mid + "|" + tgt if mid < tgt else tgt + "|" + mid
			if checked.has(key): continue
			checked[key] = true
			if not maps.has(tgt) or not maps[tgt]["portals"].has(mid): continue   # one end is a town w/o floor
			var sa: String = maps[mid]["portals"][tgt]["side"]
			var sb: String = maps[tgt]["portals"][mid]["side"]
			if sa == sb:
				side_bad.append("%s(%s) <-> %s(%s)  SAME side" % [mid, sa, tgt, sb])

	print("=== PORTAL PLACEMENT AUDIT ===")
	print("maps audited: %d   portals: %d" % [maps.size(), total])
	print("--- GROUND violations: %d ---" % ground_bad.size())
	for s in ground_bad: print("  ", s)
	print("--- SIDE violations (same side both ends): %d ---" % side_bad.size())
	for s in side_bad: print("  ", s)
	if ground_bad.is_empty() and side_bad.is_empty():
		print("ALL GOOD: every portal on the ground; every edge exits one side and arrives opposite.")
	quit()

func _re(s: String, pat: String) -> String:
	var re := RegEx.new(); re.compile(pat)
	var m := re.search(s)
	if m == null: return ""
	if m.get_group_count() >= 2: return m.get_string(1) + "|" + m.get_string(2)
	return m.get_string(1)

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
		var top: int = rows[-1]
		var set := {}
		for r in rows: set[r] = true
		while set.has(top - 1): top -= 1
		out[col] = top
	return out
