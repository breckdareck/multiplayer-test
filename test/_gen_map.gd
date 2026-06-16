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

func _init() -> void:
	for m in [_open(), _tower(), _cliffs()]:
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
	var width := 40; var bottom := 88
	var floor_y := bottom - 6
	var ground := {}; var plat := {}
	for x in range(width):
		for y in range(floor_y, bottom + 1): ground[Vector2i(x, y)] = true
	for y in range(6, floor_y):
		for wx in [0, 1, width - 2, width - 1]: ground[Vector2i(wx, y)] = true
	var left := true; var ly := floor_y - 4
	while ly > 12:
		var x0: int; var x1: int
		if left: x0 = 2; x1 = int(width * 0.66)
		else: x0 = int(width * 0.34); x1 = width - 2
		for x in range(x0, x1):
			ground[Vector2i(x, ly)] = true; ground[Vector2i(x, ly + 1)] = true
		left = not left; ly -= 5
	_shelf(plat, {}, 9, [[14, 26]])
	return {"name": "tower", "ground": ground, "plat": plat, "width": width, "bottom": bottom}

func _cliffs() -> Dictionary:
	var width := 150; var bottom := 40
	var ground := {}; var surf := []
	for x in range(width): surf.append(FLOOR_Y)
	for pl in [[24, 46, 9], [60, 86, 5], [98, 124, 13]]:
		for x in range(pl[0], pl[1]): surf[x] = FLOOR_Y - pl[2]
	for x in range(width):
		for y in range(surf[x], bottom + 1): ground[Vector2i(x, y)] = true
	var plat := {}
	_shelf(plat, surf, FLOOR_Y - 16, [[48, 60]])
	_shelf(plat, surf, FLOOR_Y - 8, [[86, 98]])
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
	text = _inject_playable(text, m)
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

	# Snap every spawn marker to exactly 1 tile above the ground surface at its column
	# (ruins-clone offset: root = tile*16 - 218,285), so monsters never spawn in the air.
	var surf := {}
	for cell in m["ground"]:
		if not surf.has(cell.x) or cell.y < surf[cell.x]: surf[cell.x] = cell.y
	var w := int(m["width"])
	var markers := ""; var locs := []; var idx := 0
	for i in range(10):
		var col := int(w * (i + 1) / 11.0)
		if not surf.has(col): continue
		markers += '\n\n[node name="M%d" type="Marker2D" parent="SlimeSpawner0"]\nposition = Vector2(%d, %d)' % [idx, col * 16 - 218, (surf[col] - 1) * 16 - 285]
		locs.append('NodePath("M%d")' % idx)
		idx += 1
	var blk := '\n\n[node name="SlimeSpawner0" type="Node2D" parent="." node_paths=PackedStringArray("spawn_locations", "spawn_container")]'
	blk += '\nscript = ExtResource("gen_spw")\nenemy_scene = ExtResource("gen_slime")'
	blk += '\nspawn_locations = [%s]\nspawn_container = NodePath("../Enemies")\npool_size = 8' % ", ".join(locs)
	blk += markers
	blk += '\n\n[node name="MultiplayerSpawner" type="MultiplayerSpawner" parent="SlimeSpawner0" node_paths=PackedStringArray("enemy_spawner")]'
	blk += '\n_spawnable_scenes = PackedStringArray("uid://q6iqwsi8meq4")\nspawn_path = NodePath("../../Enemies")'
	blk += '\nscript = ExtResource("gen_msp")\nenemy_spawner = NodePath("..")'
	text += blk

	# Reposition PlayerSpawn onto the floor (left side).
	var ps := text.find('[node name="PlayerSpawn"')
	if ps != -1:
		var spawn_pos := 'position = Vector2(%d, %d)' % [80, (FLOOR_Y - 2) * 16]
		var posln := text.find("position = ", ps)
		var nxt := text.find("\n[node ", ps)
		if posln != -1 and (nxt == -1 or posln < nxt):
			text = text.substr(0, posln) + spawn_pos + text.substr(text.find("\n", posln))
		else:
			var eol := text.find("\n", ps)
			text = text.substr(0, eol) + "\n" + spawn_pos + text.substr(eol)
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
