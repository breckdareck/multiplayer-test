extends SceneTree
## Structurally-distinct maps (no slope tiles, so flat/stepped):
##   open / tower / cliffs. Solid ground -> Mid; drop-down platforms -> Platform
##   (one-way physics_layer_1); decorations -> Background2 (no collision).
## Clones ruins.tscn (which carries the Platform layer + updated TileSet).

const FLOOR_Y := 26
const ROCK_BAND := 2
const TEMPLATE := "res://scenes/Levels/ruins.tscn"
const SHEET := "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/country village tileset.png"
const SHEET2 := "res://assets/sprites/Country-village_asset_pack/1_Tileset & props/Country_village_props.png"
const TUFTS := [[2,11], [3,11], [4,11], [5,11], [6,11]]
const TREE1 := [Vector2i(3,7), [[0,2,5],[1,0,6],[2,0,6],[3,0,6],[4,0,6],[5,1,5],[6,2,4],[7,1,4]]]
const TREE2 := [Vector2i(9,7), [[2,8,10],[3,7,10],[4,7,11],[5,7,11],[6,7,11],[7,8,10]]]

const UP := Vector2i(0,-1); const DOWN := Vector2i(0,1); const LEFT := Vector2i(-1,0); const RIGHT := Vector2i(1,0)
const DIRS = [Vector2i(-1,-1), Vector2i(0,-1), Vector2i(1,-1), Vector2i(-1,0),
              Vector2i(1,0), Vector2i(-1,1), Vector2i(0,1), Vector2i(1,1)]
const LOOKUP := {
	24:[[18,5]], 16:[[17,5]], 8:[[19,5]], 248:[[18,5]], 208:[[17,5]], 104:[[19,5]],
	240:[[17,5]], 232:[[19,5]], 214:[[17,6]], 107:[[19,6]], 31:[[18,6]],
	22:[[2,8]], 11:[[6,8]], 255:[[18,6]],
}
const PLAT := {"L":[17,9], "M":[18,9], "R":[19,9]}
## Hand-placed tower ladders [upper_branch_row, lower_platform_row, column] (tile coords),
## matching the approved climb. Each hangs from the upper branch with its bottom dangling
## ~1.5 tiles above the lower platform.
const TOWER_LADDERS := [
	[11, 17, 33], [25, 31, 7], [25, 31, 23], [31, 42, 18],
	[31, 37, 35], [37, 42, 30], [46, 51, 6], [46, 51, 18],
]
## Cliffs rope/ladder climbers up to the safe shelves: [upper_row, lower_row, col, type].
const CLIFFS_LADDERS := [
	[14, 21, 29, "rope"],     # mesa-1 shelf -> mesa 1
	[11, 17, 45, "ladder"],   # peak shelf -> peak
	[16, 22, 59, "rope"],     # mesa-3 shelf -> mesa 3
]

func _init() -> void:
	# Only cliffs this pass — gen_open and the now hand-finished gen_tower must NOT be
	# regenerated/clobbered. Swap this list to regen a different map.
	for m in [_cliffs()]:
		_emit(m)
		print("WROTE gen_", m["name"], "  ", m["width"], "x", m["bottom"])
	quit()

func _open() -> Dictionary:
	var width := 150; var bottom := 40
	var ground := {}; var surf := []
	for x in range(width):
		var h := FLOOR_Y - int(round(0.6 * sin(x * 0.04)))    # nearly flat floor
		surf.append(h)
		for y in range(h, bottom + 1): ground[Vector2i(x, y)] = true
	var plat := {}
	_shelf(plat, surf, FLOOR_Y - 6, [[8, 68], [80, 142]])
	_shelf(plat, surf, FLOOR_Y - 11, [[20, 96]])
	_shelf(plat, surf, FLOOR_Y - 16, [[44, 118]])
	return {"name": "open", "ground": ground, "plat": plat, "width": width, "bottom": bottom}

func _tower() -> Dictionary:
	# Forest-of-Ellinia style: an ORGANIC vertical climb of branch platforms at varied
	# lengths / heights / offsets (seeded RNG, so it reads as a canopy, not a grid). A
	# meandering ascent "spine" you can follow up, dressed with overlapping canopy
	# clumps and dead-end side off-shoots for fullness. No solid walls — branches float
	# in the dark. Tall gaps are left clear for a rope/ladder (wired next pass). NB: this
	# sheet has no curved/sloped branch tiles, so branches are flat segments, not arcs.
	var width := 54
	var bottom := 55
	var floor_y := bottom - 4
	var ground := {}
	var plat := {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 98765431    # change this int for a differently-shaped tower

	# Solid forest floor at the base.
	for x in range(width):
		for y in range(floor_y, bottom + 1): ground[Vector2i(x, y)] = true

	var cur_x := rng.randi_range(4, 12)
	var cur_y := floor_y - rng.randi_range(4, 6)
	while cur_y > 9:
		# Main branch: WIDE enough to fight on, with varied length + meandering position.
		var ln := rng.randi_range(16, 26)
		var x0 := clampi(cur_x, 2, width - 3 - ln)
		_seg(plat, x0, x0 + ln, cur_y)
		# Side off-shoot: a smaller ledge to ONE SIDE at the SAME LEVEL as the branch (a few
		# tiles of horizontal gap, so you hop across to it). Same level = never vertically
		# adjacent to (or a jump-tease above) another platform.
		if rng.randf() < 0.35:
			var sl := rng.randi_range(6, 10)
			var sdir := 1 if rng.randf() < 0.5 else -1
			var sbase := (x0 + ln) if sdir > 0 else (x0 - sl)
			var sx := clampi(sbase + sdir * rng.randi_range(1, 5), 2, width - 3 - sl)
			var _oy := rng.randi_range(0, 2)   # consumed (not used): keeps the approved layout seed-stable
			_seg(plat, sx, sx + sl, cur_y)      # off-shoot at the SAME level as its branch
		# Choose the next (higher) branch: shift sideways by a real amount (biased away
		# from the walls) so two branches are never stacked directly on top of each other.
		var dy := rng.randi_range(4, 6)
		var ny := cur_y - dy
		var dir := 0
		if x0 < int(width * 0.35): dir = 1
		elif x0 > int(width * 0.55): dir = -1
		else: dir = 1 if rng.randf() < 0.5 else -1
		var nx := clampi(x0 + dir * rng.randi_range(11, 20), 2, width - 9)
		# NO between-branch ledges: the gaps (4-6 tiles) are too small to give a tiny platform
		# >=3 clear tiles from BOTH neighbours, so any one reads as touching/too-close. The
		# climb is the ladders; canopy variety comes from the same-level side off-shoots.
		cur_x = nx
		cur_y = ny
	return {"name": "tower", "ground": ground, "plat": plat, "width": width, "bottom": bottom}

func _seg(plat: Dictionary, x0: int, x1: int, y: int) -> void:
	for x in range(x0, x1):
		var role := "M"
		if x == x0: role = "L"
		elif x == x1 - 1: role = "R"
		plat[Vector2i(x, y)] = role

func _cliffs() -> Dictionary:
	# Solid raised mesas with STEPPED sides — a horizontal cliff-hop. Each rise/fall is a
	# staircase of 1-tile steps (a 1-block jump clears each), so NOTHING floats against a
	# cliff face. WIDE flat tops to fight on. A one-way shelf sits >=3 tiles above the peak,
	# reached by a ladder that hangs from the SHELF platform itself (not a solid face).
	var width := 64
	var bottom := 32
	var ground := {}
	var plat := {}
	var base_r := FLOOR_Y    # 26
	# Per-column target surface height; the surface walks 1 tile/column toward it, so every
	# transition between plateaus is a jumpable staircase.
	var targets := []
	for x in range(width): targets.append(base_r)
	for seg in [[16, 34, base_r - 5], [34, 50, base_r - 9], [50, 64, base_r - 4]]:
		for x in range(seg[0], mini(seg[1], width)): targets[x] = seg[2]
	var surf := []
	var cur := base_r
	for x in range(width):
		if cur < targets[x]: cur += 1
		elif cur > targets[x]: cur -= 1
		surf.append(cur)
	for x in range(width):
		for y in range(surf[x], bottom + 1): ground[Vector2i(x, y)] = true
	# Three one-way shelves, one above each mesa (each >=3 tiles clear) — safe vantage spots
	# you reach by jumping to a rope/ladder that hangs from the shelf and climbing up.
	_shelf(plat, surf, base_r - 12, [[24, 34]])   # over mesa 1
	_shelf(plat, surf, base_r - 15, [[40, 50]])   # over the peak
	_shelf(plat, surf, base_r - 10, [[55, 63]])   # over mesa 3
	return {"name": "cliffs", "ground": ground, "plat": plat, "width": width, "bottom": bottom}

func _shelf(plat: Dictionary, surf, ty: int, segments: Array) -> void:
	for seg in segments:
		for px in range(seg[0], seg[1]):
			if typeof(surf) == TYPE_DICTIONARY or ty < surf[px] - 2:
				var role := "M"
				if px == seg[0]: role = "L"
				elif px == seg[1] - 1: role = "R"
				plat[Vector2i(px, ty)] = role

func _emit(m: Dictionary) -> void:
	var ground: Dictionary = m["ground"]; var plat: Dictionary = m["plat"]
	var depth := {}; var q := []
	for cell in ground:
		for d in [UP, DOWN, LEFT, RIGHT]:
			if not ground.has(cell + d): depth[cell] = 1; q.append(cell); break
	var head := 0
	while head < q.size():
		var c = q[head]; head += 1
		for d in [UP, DOWN, LEFT, RIGHT]:
			var n = c + d
			if ground.has(n) and not depth.has(n): depth[n] = depth[c] + 1; q.append(n)
	var black := {}
	for cell in ground:
		if depth.get(cell, 999) > 1 + ROCK_BAND: black[cell] = true

	# Mid (solid ground) tiles.
	var picks := {}
	for cell in ground:
		if black.has(cell): picks[cell] = _black_tile(cell, black)
		else:
			var bits := 0
			for i in range(8):
				if ground.has(cell + DIRS[i]): bits |= (1 << i)
			picks[cell] = _pick(bits, cell)

	# Decoration scatter (Background2): tufts/barrels/crates on grass-top + platform surfaces.
	var rng := RandomNumberGenerator.new(); rng.seed = abs(int(str(m["name"]).hash()))
	var deco := {}
	for cell in picks:
		if picks[cell][1] == 5: _try_tuft(deco, cell, ground, plat, rng)
	for cell in plat:
		_try_tuft(deco, cell, ground, plat, rng)

	# Trees: only on ground that is LEVEL across the whole trunk+canopy width.
	var surf_top := {}
	for cell in picks:
		if picks[cell][1] == 5 and (not surf_top.has(cell.x) or cell.y < surf_top[cell.x]):
			surf_top[cell.x] = cell.y
	var tx := 6
	while tx < int(m["width"]) - 6:
		var placed := false
		for tree in [TREE1, TREE2]:
			if surf_top.has(tx) and _tree_fits(tree, tx, surf_top[tx], ground, plat, surf_top):
				_place_tree(deco, tree, tx, surf_top[tx]); tx += rng.randi_range(11, 20); placed = true; break
		if not placed: tx += 3

	# Build the three layers and splice them into the cloned scene.
	var f := FileAccess.open(TEMPLATE, FileAccess.READ); var text := f.get_as_text(); f.close()
	var hnl := text.find("\n")                                    # strip cloned scene UID
	var ure := RegEx.new(); ure.compile(' uid="[^"]*"')
	text = ure.sub(text.substr(0, hnl), "", false) + text.substr(hnl)
	text = _replace_layer(text, "Mid", _layer_b64(picks, 1))
	text = _replace_layer(text, "Platform", _plat_b64(plat))
	text = _replace_layer(text, "Background", _layer_b64(deco, 2))
	text = _replace_layer(text, "Background2", "")
	text = text.replace('display_name = "The Ruins"', 'display_name = "Gen %s"' % m["name"])
	text = _strip_clone_clutter(text)
	text = _inject_playable(text, m)
	if m["name"] == "tower": text = _inject_ladders(text, TOWER_LADDERS)
	if m["name"] == "cliffs": text = _inject_ladders(text, CLIFFS_LADDERS)
	var w := FileAccess.open("res://scenes/Levels/gen_%s.tscn" % m["name"], FileAccess.WRITE)
	w.store_string(text); w.close()

	# Preview PNG (ground+platform from the tileset, decorations from the props sheet).
	var sheet := Image.new(); sheet.load(SHEET); sheet.convert(Image.FORMAT_RGBA8)
	var props := Image.new(); props.load(SHEET2); props.convert(Image.FORMAT_RGBA8)
	var img := Image.create(int(m["width"]) * 16, (int(m["bottom"]) + 2) * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.16, 0.22, 1.0))
	for cell in deco:
		var t = deco[cell]
		img.blend_rect(props, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in picks:
		var t = picks[cell]
		img.blend_rect(sheet, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in plat:
		var t = PLAT[plat[cell]]
		img.blend_rect(sheet, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	img.save_png("res://_gen_%s.png" % m["name"])

## Add a new-style enemy spawner (pool + spawn_tick model) and put the spawn point
## on the floor. Keeps the cloned ruins' Players/Enemies/GlobalDropHandler.
func _inject_playable(text: String, m: Dictionary) -> String:
	# Drop any EnemySpawner inherited from the cloned template (ruins now has its own,
	# converted spawners) so only the one we inject remains.
	text = _strip_clone_spawners(text)
	# ext_resources for the spawner scripts + slime, after the header; bump load_steps.
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 3))
	var ext := '\n[ext_resource type="Script" path="res://scripts/Enemy/enemy_spawner.gd" id="gen_spw"]'
	ext += '\n[ext_resource type="Script" path="res://scripts/Gameplay/enemy_multiplayer_spawner.gd" id="gen_msp"]'
	ext += '\n[ext_resource type="PackedScene" uid="uid://q6iqwsi8meq4" path="res://scenes/NPC/slime.tscn" id="gen_slime"]'
	text = header + ext + text.substr(nl)

	# Spawn spots: sample the base ground floor AND every wide platform floor, so enemies
	# populate the whole map (a tower's upper floors, not just the base). Markers live in
	# root space; the cloned TileMap sits at (-119,-269), so tile (col,row) -> world
	# (col*16-119, row*16-269); centre x (+8) and sit 1 tile above the surface.
	var surf := {}
	for cell in m["ground"]:
		if not surf.has(cell.x) or cell.y < surf[cell.x]: surf[cell.x] = cell.y
	var base_y := 0
	for v in surf.values(): base_y = maxi(base_y, v)
	var w := int(m["width"])
	var spots := []
	if m["name"] == "cliffs":
		# Cliffs: a slime on every FLAT stretch of ground (each mesa top + base), never on a
		# staircase step, and NOT on the one-way shelves (those stay safe vantage spots).
		for col in range(3, w - 3, 3):
			if surf.has(col) and surf[col] == surf.get(col - 1, -1) and surf[col] == surf.get(col + 1, -1):
				spots.append(Vector2i(col, surf[col]))
	else:
		# Tower/open: base floor + every wide platform floor.
		for col in range(4, w - 4, 4):
			if surf.get(col, -999) >= base_y - 1:             # on the base floor, not a side wall
				spots.append(Vector2i(col, base_y))
		var rows := {}                                        # platform floors grouped by row
		for cell in m["plat"]:
			if not rows.has(cell.y): rows[cell.y] = []
			rows[cell.y].append(cell.x)
		for r in rows:
			var xs = rows[r]; xs.sort()
			if xs.size() < 5: continue                        # skip tiny stepping stones
			var c: int = xs[0] + 2
			while c <= xs[xs.size() - 1] - 1:
				spots.append(Vector2i(c, r)); c += 7
	var markers := ""; var locs := []; var idx := 0
	for s in spots:
		markers += '\n\n[node name="M%d" type="Marker2D" parent="SlimeSpawner0"]\nposition = Vector2(%d, %d)' % [idx, s.x * 16 - 111, (s.y - 1) * 16 - 269]
		locs.append('NodePath("M%d")' % idx)
		idx += 1
	var blk := '\n\n[node name="SlimeSpawner0" type="Node2D" parent="." node_paths=PackedStringArray("spawn_locations", "spawn_container")]'
	blk += '\nscript = ExtResource("gen_spw")\nenemy_scene = ExtResource("gen_slime")'
	blk += '\nspawn_locations = [%s]\nspawn_container = NodePath("../Enemies")\npool_size = %d' % [", ".join(locs), maxi(idx, 1)]
	blk += markers
	blk += '\n\n[node name="MultiplayerSpawner" type="MultiplayerSpawner" parent="SlimeSpawner0" node_paths=PackedStringArray("enemy_spawner")]'
	blk += '\n_spawnable_scenes = PackedStringArray("uid://q6iqwsi8meq4")\nspawn_path = NodePath("../../Enemies")'
	blk += '\nscript = ExtResource("gen_msp")\nenemy_spawner = NodePath("..")'
	text += blk

	# Reposition PlayerSpawn onto the floor (left side), same (-119,-269) clone offset.
	var ps := text.find('[node name="PlayerSpawn"')
	if ps != -1:
		var spawn_pos := 'position = Vector2(%d, %d)' % [5 * 16 - 119, (FLOOR_Y - 2) * 16 - 269]
		var posln := text.find("position = ", ps)
		var nxt := text.find("\n[node ", ps)
		if posln != -1 and (nxt == -1 or posln < nxt):
			text = text.substr(0, posln) + spawn_pos + text.substr(text.find("\n", posln))
		else:
			var eol := text.find("\n", ps)
			text = text.substr(0, eol) + "\n" + spawn_pos + text.substr(eol)

	# Drop the Killzone well below the map's lowest tile (the clone's plane sits too high
	# for short maps, which would kill players standing on low ground).
	var kz := text.find('name="Killzone"')
	if kz != -1:
		var kpos := text.find("position = Vector2(", kz)
		var knl := text.find("\n[node ", kz)
		if kpos != -1 and (knl == -1 or kpos < knl):
			var comma := text.find(",", kpos + 'position = Vector2('.length())
			var ke := text.find(")", comma)
			text = text.substr(0, comma + 1) + " %d" % ((int(m["bottom"]) + 5) * 16 - 269) + text.substr(ke)
	return text

func _layer_b64(cells: Dictionary, src: int) -> String:
	var l := TileMapLayer.new()
	for cell in cells: l.set_cell(cell, src, Vector2i(cells[cell][0], cells[cell][1]))
	var b := Marshalls.raw_to_base64(l.tile_map_data); l.free(); return b

func _plat_b64(plat: Dictionary) -> String:
	var l := TileMapLayer.new()
	for cell in plat:
		var t = PLAT[plat[cell]]
		l.set_cell(cell, 1, Vector2i(t[0], t[1]))
	var b := Marshalls.raw_to_base64(l.tile_map_data); l.free(); return b

func _try_tuft(deco: Dictionary, cell: Vector2i, ground: Dictionary, plat: Dictionary, rng: RandomNumberGenerator) -> void:
	var above := Vector2i(cell.x, cell.y - 1)
	if ground.has(above) or plat.has(above) or deco.has(above): return
	var roll := rng.randf()
	if roll < 0.34: deco[above] = TUFTS[rng.randi_range(0, TUFTS.size() - 1)]
	elif roll < 0.355: deco[above] = [8, 11]
	elif roll < 0.365:
		var ar := Vector2i(above.x + 1, above.y)
		if not ground.has(ar) and not plat.has(ar) and not deco.has(ar):
			deco[above] = [10, 11]; deco[ar] = [11, 11]

func _black_tile(cell: Vector2i, black: Dictionary) -> Array:
	var t := not black.has(cell + UP); var b := not black.has(cell + DOWN)
	var l := not black.has(cell + LEFT); var r := not black.has(cell + RIGHT)
	if t and l: return [3, 6]
	if t and r: return [5, 6]
	if b and l: return [3, 8]
	if b and r: return [5, 8]
	if t: return [4, 6]
	if b: return [4, 8]
	if l: return [3, 7]
	if r: return [5, 7]
	return [4, 7]

func _pick(bits: int, cell: Vector2i) -> Array:
	if LOOKUP.has(bits):
		var opts = LOOKUP[bits]
		return opts[(cell.x * 7 + cell.y * 3) % opts.size()]
	var best := -1; var bestd := 99
	for k in LOOKUP:
		var d := _ham(bits, k)
		if d < bestd: bestd = d; best = k
	return LOOKUP[best][0]

func _ham(a: int, b: int) -> int:
	var x := a ^ b; var c := 0
	while x > 0: c += x & 1; x >>= 1
	return c

func _tree_fits(tree: Array, tx: int, gy: int, ground: Dictionary, plat: Dictionary, surf_top: Dictionary) -> bool:
	var bc: int = tree[0].x
	var minc := 99; var maxc := -99
	for spec in tree[1]:
		minc = min(minc, spec[1]); maxc = max(maxc, spec[2])
	for c in range(minc, maxc + 1):
		if surf_top.get(tx + c - bc, -999) != gy: return false   # ground must be level
	var br: int = tree[0].y
	for spec in tree[1]:
		for c in range(spec[1], spec[2] + 1):
			var p := Vector2i(tx + c - bc, gy - 1 + spec[0] - br)
			if ground.has(p) or plat.has(p): return false
	return true

func _place_tree(deco: Dictionary, tree: Array, tx: int, gy: int) -> void:
	var bc: int = tree[0].x; var br: int = tree[0].y
	for spec in tree[1]:
		for c in range(spec[1], spec[2] + 1):
			deco[Vector2i(tx + c - bc, gy - 1 + spec[0] - br)] = [c, spec[0]]

## Scoped to ONE node's block: replaces that layer's tile_map_data, or INSERTS one
## if the layer is empty (so an empty layer never steals the next layer's data).
func _replace_layer(text: String, layer_name: String, b64: String) -> String:
	var ni := text.find('name="%s" type="TileMapLayer"' % layer_name)
	if ni == -1: return text
	var node_start := text.find("\n", ni) + 1
	var node_end := text.find("\n[", node_start)
	if node_end == -1: node_end = text.length()
	var key := 'tile_map_data = PackedByteArray("'
	var di := text.find(key, node_start)
	if di != -1 and di < node_end:
		var s := di + key.length(); var e := text.find('"', s)
		return text.substr(0, s) + b64 + text.substr(e)
	# Empty layer: insert a tile_map_data line right after the node header.
	return text.substr(0, node_start) + 'tile_map_data = PackedByteArray("%s")\n' % b64 + text.substr(node_start)

## Remove EnemySpawner nodes carried over from the cloned template (their Marker2D +
## MultiplayerSpawner direct children too), so only the freshly-injected spawner remains.
func _strip_clone_spawners(text: String) -> String:
	var nre := RegEx.new(); nre.compile('\\[node name="([^"]+)"([^\\]]*)\\]')
	var ms := nre.search_all(text)
	var spawner_names := {}
	for i in ms.size():
		var hend := ms[i].get_end()
		var bend = text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
		if text.substr(hend, bend - hend).find("enemy_scene = ExtResource(") != -1:
			spawner_names[ms[i].get_string(1)] = true
	var spans := []
	for i in ms.size():
		var nm := ms[i].get_string(1)
		var parent := _attr(ms[i].get_string(2), "parent")
		if spawner_names.has(nm) or spawner_names.has(parent):
			var bend = text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
			spans.append([ms[i].get_start(), bend])
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for sp in spans: text = text.substr(0, sp[0]) + text.substr(sp[1])
	return text

func _attr(s: String, key: String) -> String:
	var re := RegEx.new(); re.compile('(?:^|[^A-Za-z_])%s="([^"]*)"' % key)
	var m := re.search(s)
	return m.get_string(1) if m else ""

## Replace the cloned ruins ladders/ropes with the approved TOWER_LADDERS — real
## climbable ladder.gd Area2D nodes, reusing the clone's ladder script + sprite. Each
## hangs from the upper branch (world tile (col,row) -> (col*16-119, row*16-269)) with
## its bottom dangling ~1.5 tiles above the platform below.
func _inject_ladders(text: String, specs: Array) -> String:
	var lid := _find_ext_id(text, "res://scripts/Gameplay/ladder.gd")
	var lat := _find_atlas_under(text, "Ladders")
	var rat := _find_atlas_under(text, "Ropes")
	if lid == "" or lat == "":
		print("  ladder wiring skipped (lid=", lid, " lat=", lat, ")"); return text
	if rat == "": rat = lat
	text = _clear_children(text, "Ladders")
	text = _clear_children(text, "Ropes")
	var shapes := ""; var nodes := ""
	for i in specs.size():
		var L = specs[i]
		var is_rope: bool = L.size() > 3 and L[3] == "rope"
		var parent := "Ropes" if is_rope else "Ladders"   # ropes thinner, hang under Ropes
		var hw := 2 if is_rope else 7
		var sw := 4 if is_rope else 10
		var atl := rat if is_rope else lat
		var x: int = L[2] * 16 - 111
		var top_y: int = L[0] * 16 - 269 - 1     # poke only 1px above the upper platform
		var bottom_y: int = L[1] * 16 - 269 - 24
		var h: int = bottom_y - top_y
		var cy: int = int((top_y + bottom_y) / 2.0)
		var half: int = int(h / 2.0)
		var sid := "RectShape_C%d" % i
		shapes += '\n[sub_resource type="RectangleShape2D" id="%s"]\nsize = Vector2(%d, %d)\n' % [sid, sw, h]
		nodes += '\n[node name="C%d" type="Area2D" parent="%s"]\nposition = Vector2(%d, %d)\ncollision_layer = 0\ncollision_mask = 2\nscript = ExtResource("%s")\n' % [i, parent, x, cy, lid]
		nodes += '\n[node name="CollisionShape2D" type="CollisionShape2D" parent="%s/C%d"]\nshape = SubResource("%s")\n' % [parent, i, sid]
		nodes += '\n[node name="NinePatchRect" type="NinePatchRect" parent="%s/C%d"]\noffset_left = %d.0\noffset_top = %d.0\noffset_right = %d.0\noffset_bottom = %d.0\ntexture = SubResource("%s")\npatch_margin_top = 2\npatch_margin_bottom = 2\naxis_stretch_vertical = 1\n' % [parent, i, -hw, -half, hw, half, atl]
	var fn := text.find("\n[node ")
	text = text.substr(0, fn) + "\n" + shapes + text.substr(fn)
	var lsre := RegEx.new(); lsre.compile("load_steps=(\\d+)")
	var lm := lsre.search(text)
	if lm:
		text = text.substr(0, lm.get_start()) + "load_steps=%d" % (int(lm.get_string(1)) + specs.size()) + text.substr(lm.get_end())
	return text + "\n" + nodes

## Remove every node whose parent is `parent` or a descendant path of it.
func _clear_children(text: String, parent: String) -> String:
	var nre := RegEx.new(); nre.compile('\\[node name="([^"]+)"([^\\]]*)\\]')
	var ms := nre.search_all(text)
	var spans := []
	for i in ms.size():
		var p := _attr(ms[i].get_string(2), "parent")
		if p == parent or p.begins_with(parent + "/"):
			var bend = text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
			spans.append([ms[i].get_start(), bend])
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for s in spans: text = text.substr(0, s[0]) + text.substr(s[1])
	return text

func _find_ext_id(text: String, path: String) -> String:
	var i := text.find('path="%s"' % path)
	if i == -1: return ""
	var ls := text.rfind("[ext_resource", i); var le := text.find("]", i)
	if ls == -1 or le == -1: return ""
	return _attr(text.substr(ls, le - ls + 1), "id")

func _find_atlas_under(text: String, container: String) -> String:
	var li := text.find('name="%s" type="Node2D"' % container)
	if li == -1: return ""
	var key := 'texture = SubResource("'
	var ti := text.find(key, li)
	if ti == -1: return ""
	var s := ti + key.length()
	return text.substr(s, text.find('"', s) - s)

## Strip clutter inherited from the cloned template that doesn't belong in a fresh map:
## the crate StaticBodies under "Platforms" (the generated map uses the Platform tile
## layer instead), and the cloned portals + their *_Portal_Spawn markers (they point at
## the TEMPLATE's neighbours, not this map's).
func _strip_clone_clutter(text: String) -> String:
	text = _clear_children(text, "Platforms")
	var portal_id := _find_ext_id(text, "res://scenes/Gameplay/portal.tscn")
	var nre := RegEx.new(); nre.compile('\\[node name="([^"]+)"([^\\]]*)\\]')
	var ms := nre.search_all(text)
	var remove := {}
	for m in ms:
		var nm := m.get_string(1); var attrs := m.get_string(2)
		if (portal_id != "" and attrs.find('instance=ExtResource("%s")' % portal_id) != -1) or nm.ends_with("_Portal_Spawn"):
			remove[nm] = true
	var spans := []
	for i in ms.size():
		var nm := ms[i].get_string(1); var parent := _attr(ms[i].get_string(2), "parent")
		if remove.has(nm) or remove.has(parent):
			var bend = text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
			spans.append([ms[i].get_start(), bend])
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for s in spans: text = text.substr(0, s[0]) + text.substr(s[1])
	return text
