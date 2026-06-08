extends SceneTree
# Headless map builder. Generates a fully-painted map .tscn from a layout entry
# in tools/map_layouts.json, reusing the TileSet (with physics polygons already
# configured) from scenes/Levels/map_template.tscn.
#
#   "C:\Program Files\Godot\Godot.exe" --headless --path . \
#       --script res://tools/build_map.gd -- <map_id> [<map_id> ...]
#
# Why a runtime script and not hand-written .tscn: TileMapLayer stores painted
# cells in an opaque PackedInt32Array (tile_data). Letting the engine's own
# set_cell() + PackedScene.pack() + ResourceSaver.save() write it is the only
# robust way to author tiles programmatically.

const TEMPLATE := "res://scenes/Levels/map_template.tscn"
const LAYOUTS := "res://tools/map_layouts.json"
const COUNTRY_SOURCE_ID := 1  # source index of the country tileset in TileSet_lbhrr

const SPAWNER_SCRIPT := "res://scripts/Enemy/enemy_spawner.gd"
const MP_SPAWNER_SCRIPT := "res://scripts/Gameplay/enemy_multiplayer_spawner.gd"
const LADDER_SCENE := "res://scenes/Gameplay/ladder.tscn"
# portal.tscn's collision rect (size 16x29 @ y=1.5) has its BOTTOM at origin_y+16,
# so placing the origin at surface_y-16 rests the portal foot on the ground top.
const PORTAL_BOTTOM_OFFSET := 16
# Enemies sit feet-on-surface. Their sprite is drawn above the node origin, so the
# origin must be nudged DOWN past the grass-top row by this much for the visible
# feet to rest on the grass (tuned against the rendered result).
const ENEMY_SURFACE_NUDGE := 4
# A ladder's top pokes this far ABOVE its upper platform so it's visible/grabbable.
const LADDER_POKE := 8.0

# Decoration prop stamps in the props atlas (source 2). {ax,ay,w,h} in tile cells;
# the prop's BOTTOM row is placed just above the target surface row.
const PROP_DEFS := {
	"bigtree":   {"ax": 0,  "ay": 0,  "w": 7, "h": 8},
	"smalltree": {"ax": 8,  "ay": 1,  "w": 4, "h": 7},
	"house":     {"ax": 13, "ay": 1,  "w": 7, "h": 7},
	"bush":      {"ax": 2,  "ay": 11, "w": 4, "h": 1},
}
const PROPS_SOURCE_ID := 2

# Atlas (col,row) picks in the country-village tileset — solid grass-topped body.
const GRASS_L := Vector2i(17, 5)
const GRASS_M := Vector2i(18, 5)
const GRASS_R := Vector2i(19, 5)
const DIRT_L := Vector2i(17, 6)
const DIRT_M := Vector2i(18, 6)
const DIRT_R := Vector2i(19, 6)


var _ran := false

# Run on the FIRST processed frame, not in _init(): autoload singletons
# (MapManager, ResourceManager, ...) only finish their _ready after the first
# frame. portal.gd / killzone.gd reference those autoloads, so building in
# _init() loads them with compile errors and set("target_map_id") silently
# no-ops. (Same pattern as test/run_tests.gd.)
func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	_run()
	return true


func _run() -> void:
	var ids := OS.get_cmdline_user_args()
	if ids.is_empty():
		push_error("Usage: build_map.gd -- <map_id> [<map_id> ...]")
		quit(1)
		return

	var f := FileAccess.open(LAYOUTS, FileAccess.READ)
	if f == null:
		push_error("Cannot open %s" % LAYOUTS)
		quit(1)
		return
	var layouts: Dictionary = JSON.parse_string(f.get_as_text())
	f.close()

	var failures := 0
	for map_id in ids:
		if not layouts.has(map_id):
			push_error("No layout '%s' in map_layouts.json" % map_id)
			failures += 1
			continue
		if not _build(map_id, layouts[map_id]):
			failures += 1
	quit(failures)


func _build(map_id: String, layout: Dictionary) -> bool:
	# paint_existing: load the EXISTING map and only (re)paint its ground, keeping
	# its portals / enemies / boss untouched. Otherwise build fresh from template.
	var paint_existing: bool = bool(layout.get("paint_existing", false))
	var tile: int = int(layout.get("tile", 16))
	var root: Node2D

	if paint_existing:
		var src_path := "res://scenes/Levels/%s.tscn" % map_id
		var src: PackedScene = load(src_path)
		if src == null:
			push_error("Cannot load existing map %s" % src_path)
			return false
		root = src.instantiate()  # never added to tree -> no _ready() side effects
	else:
		var template: PackedScene = load(TEMPLATE)
		if template == null:
			push_error("Cannot load template %s" % TEMPLATE)
			return false
		root = template.instantiate()
		root.name = _to_pascal(map_id)
		# --- Root MapBase config (fresh maps only) ---------------------------
		root.set("display_name", layout.get("display_name", ""))
		root.set("bgm_path", layout.get("bgm_path", ""))
		root.set("camera_top_padding", int(layout.get("camera_top_padding", 400)))
		root.set("camera_bottom_padding", int(layout.get("camera_bottom_padding", 80)))

	# Expand a compact procedural "tower" spec into a tall, multi-level set of
	# platforms + auto-connected ladders (MapleStory-style verticality).
	if layout.has("generate"):
		var gen := _gen_layout(layout["generate"], map_id)
		layout["platforms"] = gen["platforms"]
		layout["ladders"] = gen["ladders"]

	# --- Paint terrain onto the "Mid" TileMapLayer ---------------------------
	var mid: TileMapLayer = root.get_node("TileMap/Mid")
	mid.clear()
	for p in layout.get("platforms", []):
		_paint_platform(mid, int(p.x), int(p.y), int(p.w), int(p.get("depth", 1)))

	# Fresh maps get their spawn/portals/spawners built from scratch; existing
	# maps keep their authored content but get decoration, ladders, and their
	# portals/enemies repositioned onto the freshly-painted multi-tier ground.
	if paint_existing:
		_decorate_and_populate(root, layout, tile)
	else:
		_build_gameplay_nodes(root, layout, tile)
		# Brand-new generated maps also get cave decoration + dense enemies.
		var plats: Array = layout.get("platforms", [])
		if layout.has("generate"):
			_paint_decor(root, layout, plats, tile)
		if layout.has("populate"):
			var sp := int(layout.get("generate", {}).get("enemy_spacing", 6))
			var mx := int(layout.get("generate", {}).get("max_enemies", 45))
			_populate_from_list(root, plats, tile, layout["populate"], sp, mx)

	# --- Killzone plane (move only when the layout specifies one) -------------
	if layout.has("killzone_y"):
		var killzone: Node2D = root.get_node("Killzone")
		killzone.position = Vector2(0, int(layout.get("killzone_y")) * tile)

	# --- Pack & save ---------------------------------------------------------
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		push_error("pack() failed for %s: %d" % [map_id, err])
		return false
	var out := "res://scenes/Levels/%s.tscn" % map_id
	err = ResourceSaver.save(packed, out)
	if err != OK:
		push_error("save() failed for %s: %d" % [map_id, err])
		return false

	var painted := mid.get_used_cells().size()
	print("OK  %s  -> %s  (%d tiles painted, used_rect=%s, mode=%s)" % [
		map_id, out, painted, str(mid.get_used_rect()),
		"paint" if paint_existing else "fresh"])
	return true


# Build the spawn marker, portals (+ arrival markers) and enemy spawners for a
# FRESH map (template mode). paint_existing maps already have these authored.
func _build_gameplay_nodes(root: Node2D, layout: Dictionary, tile: int) -> void:
	# --- Spawn marker --------------------------------------------------------
	var spawn: Marker2D = root.get_node("PlayerSpawn")
	var sp: Dictionary = layout.get("spawn", {"x": 2, "y": 0})
	spawn.position = Vector2(int(sp.x) * tile, int(sp.y) * tile)

	# --- Portals -------------------------------------------------------------
	var portal_scene: PackedScene = load("res://scenes/Gameplay/portal.tscn")
	# Reconfigure the template's first portal, then add any extras.
	var existing_portal: Node = root.get_node_or_null("PortalToTargetMap")
	var arrival_marker: Node = root.get_node_or_null("CurrentMap_TargetMap_Portal_Spawn")
	var portals: Array = layout.get("portals", [])
	for i in portals.size():
		var pd: Dictionary = portals[i]
		# Rest the portal's foot on the ground: x centered on the tile column,
		# y so the collision bottom (origin+16) lands on the supporting surface.
		var surface_row := _surface_row_at(layout.get("platforms", []), int(pd.x))
		if surface_row < 0:
			surface_row = int(pd.get("y", 0)) + 1  # fallback to explicit y
		var pos := Vector2(
			int(pd.x) * tile + tile / 2.0,
			surface_row * tile - PORTAL_BOTTOM_OFFSET)
		var portal: Node
		if i == 0 and existing_portal != null:
			portal = existing_portal
		else:
			portal = portal_scene.instantiate()
			portal.name = "Portal%d" % i
			root.add_child(portal)
			portal.owner = root
		portal.set("target_map_id", pd.get("target_map_id", "town"))
		portal.set("target_spawn_point_name", pd.get("target_spawn_point_name", ""))
		portal.position = pos
		# Arrival marker that other maps' portals target.
		var arr_name: String = pd.get("arrival_name", "")
		if arr_name != "":
			var marker: Marker2D
			if i == 0 and arrival_marker != null:
				marker = arrival_marker
				marker.name = arr_name
			else:
				marker = Marker2D.new()
				marker.name = arr_name
				root.add_child(marker)
				marker.owner = root
			marker.position = spawn.position

	# --- Enemy spawners ------------------------------------------------------
	# Each layout "spawners" entry becomes a real EnemySpawner: a Node2D with
	# enemy_spawner.gd, child Marker2D spawn locations, a child MultiplayerSpawner,
	# enemy_scene set, and spawn_container -> the map's Enemies node. (Bare
	# Marker2D nodes under Enemies do NOT spawn anything.)
	var enemies_node: Node = root.get_node("Enemies")
	var spawners: Array = layout.get("spawners", [])
	for i in spawners.size():
		_build_spawner(root, enemies_node, spawners[i], i, tile)

	# Ladders (also available to fresh maps for reachable tiers).
	for ld in layout.get("ladders", []):
		_build_ladder(root, int(ld.x), int(ld.top), int(ld.bottom), tile)


func _paint_platform(layer: TileMapLayer, x: int, y: int, w: int, depth: int) -> void:
	for c in w:
		var col := x + c
		var top := GRASS_M
		if c == 0:
			top = GRASS_L
		elif c == w - 1:
			top = GRASS_R
		layer.set_cell(Vector2i(col, y), COUNTRY_SOURCE_ID, top)
		for d in range(1, depth):
			var body := DIRT_M
			if c == 0:
				body = DIRT_L
			elif c == w - 1:
				body = DIRT_R
			layer.set_cell(Vector2i(col, y + d), COUNTRY_SOURCE_ID, body)


# Topmost grass-top row of any platform whose span covers `col`, or -1 if none.
func _surface_row_at(platforms: Array, col: int) -> int:
	var best := -1
	for p in platforms:
		var x := int(p.x)
		if col >= x and col < x + int(p.w):
			var y := int(p.y)
			if best < 0 or y < best:
				best = y
	return best


# Procedurally build a tall staggered platform tower + connecting ladders from a
# compact spec. Deterministic per map (seeded) so rebuilds are stable. Returns
# {platforms, ladders}; platforms[0] is the full-width main ground.
func _gen_layout(spec: Dictionary, map_id: String) -> Dictionary:
	match str(spec.get("shape", "tower")):
		"stairs": return _gen_stairs(spec, map_id)
		"pyramid": return _gen_pyramid(spec, map_id)
		"cliffs": return _gen_cliffs(spec, map_id)
		_: return _gen_tower(spec, map_id)


# Append a platform and a ladder from it down to an overlapping platform in
# `below` (or the main ground). Shared by every archetype.
func _connect(platforms: Array, ladders: Array, plat: Dictionary, below: Array, main: Dictionary) -> void:
	platforms.append(plat)
	var target = _overlapping(below, int(plat.x), int(plat.w))
	if target == null:
		target = main
	var lo: int = maxi(int(plat.x), int(target.x))
	var hi: int = mini(int(plat.x) + int(plat.w), int(target.x) + int(target.w))
	var lx: int = (lo + hi) / 2 if hi > lo else int(plat.x) + int(plat.w) / 2
	ladders.append({"x": lx, "top": int(plat.y), "bottom": int(target.y)})


func _main_plat(spec: Dictionary) -> Dictionary:
	return {"x": int(spec.get("main_x", -36)), "y": int(spec.get("main_y", 2)),
		"w": int(spec.get("main_w", 72)), "depth": int(spec.get("main_depth", 4))}


# TOWER: symmetric staggered platforms in zones per level (a balanced climb).
func _gen_tower(spec: Dictionary, map_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = hash(map_id)
	var main := _main_plat(spec)
	var mx := int(main.x); var mw := int(main.w); var my := int(main.y)
	var lh := int(spec.get("level_height", 3)); var levels := int(spec.get("levels", 5))
	var ppl := int(spec.get("platforms_per_level", 2))
	var pw_min := int(spec.get("pw_min", 10)); var pw_max := int(spec.get("pw_max", 16))
	var platforms: Array = [main]; var ladders: Array = []
	var below: Array = [main]; var inset := 3
	for lvl in range(1, levels + 1):
		var row := my - lvl * lh; var this_level: Array = []
		var zone_w := int((mw - inset * 2) / ppl)
		for z in range(ppl):
			var pw: int = clampi(rng.randi_range(pw_min, pw_max), 4, zone_w - 1)
			var px := mx + inset + z * zone_w + rng.randi_range(0, maxi(1, zone_w - pw - 1))
			var plat := {"x": px, "y": row, "w": pw, "depth": 1}
			_connect(platforms, ladders, plat, below, main)
			this_level.append(plat)
		below = this_level
	return {"platforms": platforms, "ladders": ladders}


# STAIRS: a switchback staircase zig-zagging up the map (Stairway-to-the-Sky).
func _gen_stairs(spec: Dictionary, map_id: String) -> Dictionary:
	var main := _main_plat(spec)
	var mx := int(main.x); var mw := int(main.w); var my := int(main.y)
	var lh := int(spec.get("level_height", 2)); var levels := int(spec.get("levels", 8))
	var sw := int(spec.get("step_w", 12))
	var platforms: Array = [main]; var ladders: Array = []
	var x := mx + 3; var dir := 1; var prev := main
	for k in range(levels):
		var row := my - (k + 1) * lh
		var nx := x + dir * (sw - 3)
		if nx + sw > mx + mw - 2 or nx < mx + 2:
			dir = -dir
			nx = x + dir * (sw - 3)
		x = clampi(nx, mx + 2, mx + mw - 2 - sw)
		var plat := {"x": x, "y": row, "w": sw, "depth": 1}
		_connect(platforms, ladders, plat, [prev], main)
		prev = plat
	return {"platforms": platforms, "ladders": ladders}


# PYRAMID: wide centred platforms that narrow as they rise (a ziggurat).
func _gen_pyramid(spec: Dictionary, map_id: String) -> Dictionary:
	var main := _main_plat(spec)
	var mx := int(main.x); var mw := int(main.w); var my := int(main.y)
	var lh := int(spec.get("level_height", 3)); var levels := int(spec.get("levels", 5))
	var platforms: Array = [main]; var ladders: Array = []
	var prev := main; var step := int(mw / (levels + 1))
	for lvl in range(1, levels + 1):
		var w: int = maxi(8, mw - lvl * step)
		var x := mx + (mw - w) / 2
		var plat := {"x": x, "y": my - lvl * lh, "w": w, "depth": 1}
		# Two ladders (left & right of centre) so the wide tiers aren't single-file.
		platforms.append(plat)
		var lo: int = maxi(x, int(prev.x)); var hi: int = mini(x + w, int(prev.x) + int(prev.w))
		var c: int = (lo + hi) / 2
		ladders.append({"x": maxi(lo + 1, c - w / 4), "top": int(plat.y), "bottom": int(prev.y)})
		ladders.append({"x": mini(hi - 1, c + w / 4), "top": int(plat.y), "bottom": int(prev.y)})
		prev = plat
	return {"platforms": platforms, "ladders": ladders}


# CLIFFS: asymmetric ledges jutting from alternating walls at jittered heights
# (a natural cave). Distinct from the even zones of TOWER.
func _gen_cliffs(spec: Dictionary, map_id: String) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = hash(map_id)
	var main := _main_plat(spec)
	var mx := int(main.x); var mw := int(main.w); var my := int(main.y)
	var lh := int(spec.get("level_height", 3)); var levels := int(spec.get("levels", 5))
	var pw_min := int(spec.get("pw_min", 9)); var pw_max := int(spec.get("pw_max", 16))
	var platforms: Array = [main]; var ladders: Array = []
	var below: Array = [main]
	for lvl in range(1, levels + 1):
		var base_row := my - lvl * lh; var this_level: Array = []
		for side in range(2):  # one ledge hugging each wall
			var pw: int = rng.randi_range(pw_min, pw_max)
			var row: int = base_row + rng.randi_range(-1, 1)
			var x: int = (mx + 2 + rng.randi_range(0, 4)) if side == 0 \
				else (mx + mw - pw - 2 - rng.randi_range(0, 4))
			var plat := {"x": x, "y": row, "w": pw, "depth": 1}
			_connect(platforms, ladders, plat, below, main)
			this_level.append(plat)
		if lvl % 2 == 0:  # a centre ledge every other level
			var cw: int = rng.randi_range(pw_min, pw_max)
			var cx: int = mx + (mw - cw) / 2 + rng.randi_range(-3, 3)
			var cplat := {"x": cx, "y": base_row, "w": cw, "depth": 1}
			_connect(platforms, ladders, cplat, below, main)
			this_level.append(cplat)
		below = this_level
	return {"platforms": platforms, "ladders": ladders}


func _overlapping(cands: Array, px: int, pw: int):
	for c in cands:
		if px < int(c.x) + int(c.w) and px + pw > int(c.x):
			return c
	return null


# --- paint_existing: decorate + reposition authored content ------------------
# Adds background decoration, ladders between tiers, and moves the map's existing
# portals + enemies onto the freshly-painted multi-tier ground.
func _decorate_and_populate(root: Node2D, layout: Dictionary, tile: int) -> void:
	var platforms: Array = layout.get("platforms", [])
	# Remove ladders from a previous build so re-runs don't stack duplicates.
	for c in root.get_children():
		if str(c.name).begins_with("Ladder_"):
			root.remove_child(c)
			c.free()
	# Purge enemy clones from a previous build so density doesn't compound.
	var en := root.get_node_or_null("Enemies")
	if en != null:
		for e in en.get_children():
			if str(e.name).begins_with("Clone_"):
				en.remove_child(e)
				e.free()
	_paint_decor(root, layout, platforms, tile)
	for ld in layout.get("ladders", []):
		_build_ladder(root, int(ld.x), int(ld.top), int(ld.bottom), tile)
	for pd in layout.get("portals", []):
		_reposition_portal(root, pd, platforms, tile)
	_distribute_enemies(root, platforms, tile, layout)


# Paint non-colliding background decoration on two layers:
#  - Background  (z -3): darkened rock backfill auto-sized to the platform bbox
#    -> recedes behind the platforms, showing through the gaps as a cave wall.
#  - Background2 (z -2): full-colour prop stamps (trees / house / bushes).
# Both have collision disabled so they're purely visual.
func _paint_decor(root: Node2D, layout: Dictionary, platforms: Array, tile: int) -> void:
	var decor: Dictionary = layout.get("decor", {})
	var back: TileMapLayer = root.get_node_or_null("TileMap/Background")
	var props: TileMapLayer = root.get_node_or_null("TileMap/Background2")

	# Auto rock backfill covering the whole platform tower (grown by 1 tile).
	if back != null and not platforms.is_empty():
		back.clear()
		back.collision_enabled = false
		var tint: Array = decor.get("backfill_tint", [0.4, 0.38, 0.5])
		back.modulate = Color(tint[0], tint[1], tint[2])
		var a: Array = decor.get("backfill_tile", [18, 6])
		var ac := Vector2i(int(a[0]), int(a[1]))
		var minx := 9999; var maxx := -9999; var miny := 9999; var maxy := -9999
		for p in platforms:
			minx = mini(minx, int(p.x)); maxx = maxi(maxx, int(p.x) + int(p.w))
			miny = mini(miny, int(p.y)); maxy = maxi(maxy, int(p.y) + int(p.get("depth", 1)))
		for r in range(miny - 1, maxy + 1):
			for c in range(minx - 1, maxx + 1):
				back.set_cell(Vector2i(c, r), COUNTRY_SOURCE_ID, ac)

	if props != null:
		props.clear()
		props.collision_enabled = false
		props.modulate = Color(1, 1, 1)
		var main_row := int(platforms[0].y) if not platforms.is_empty() else 2
		# Big props anchored on the main ground (row known even when generated).
		for gp in decor.get("ground_props", []):
			_stamp_prop(props, {"kind": gp.kind, "x": int(gp.x), "row": main_row}, tile)
		# Scatter a small prop on alternating upper platforms for greenery.
		var scatter: String = decor.get("scatter", "")
		if scatter != "":
			for i in range(1, platforms.size()):
				if i % 2 == 0:
					var p: Dictionary = platforms[i]
					_stamp_prop(props, {"kind": scatter,
						"x": int(p.x) + int(p.w) / 2 - 2, "row": int(p.y)}, tile)
		# Explicit props with an absolute row (manual layouts).
		for pr in decor.get("props", []):
			_stamp_prop(props, pr, tile)


# Stamp a multi-tile prop from the props atlas; bottom row rests just above
# `row` (a surface row). Missing atlas tiles are created so they render.
func _stamp_prop(layer: TileMapLayer, pr: Dictionary, _tile: int) -> void:
	var d: Dictionary = PROP_DEFS.get(pr.kind, {})
	if d.is_empty():
		return
	var source := layer.tile_set.get_source(PROPS_SOURCE_ID) as TileSetAtlasSource
	if source == null:
		return
	var base_col := int(pr.x)
	var base_row := int(pr.row)  # surface row the prop stands on
	for j in int(d.h):
		for i in int(d.w):
			var ac := Vector2i(int(d.ax) + i, int(d.ay) + j)
			if not source.has_tile(ac):
				if not Rect2i(Vector2i(), source.get_atlas_grid_size()).has_point(ac):
					continue
				source.create_tile(ac)
			layer.set_cell(Vector2i(base_col + i, base_row - int(d.h) + j),
				PROPS_SOURCE_ID, ac)


# Build a climbable Ladder connecting an upper platform (top_row) to a lower one
# (bottom_row) at column x. The ladder POKES a few px above the upper platform
# (visible/grabbable) and HANGS DOWN to the lower platform's surface so players
# and bots can jump onto it from below. Players AND bots use it (bot_nav_graph
# builds ladder edges). y grows downward, so top_row < bottom_row.
func _build_ladder(root: Node2D, x_col: int, top_row: int, bottom_row: int, tile: int) -> void:
	var zone_top := float(top_row * tile) - LADDER_POKE      # poke above upper platform
	var zone_bottom := float(bottom_row * tile)              # reach the lower surface
	var h := zone_bottom - zone_top
	# Built from scratch (not instanced) so the resized child nodes serialize:
	# instance-child overrides are dropped by PackedScene.pack().
	var ladder := Area2D.new()
	ladder.set_script(load("res://scripts/Gameplay/ladder.gd"))
	ladder.collision_layer = 0
	ladder.collision_mask = 2
	ladder.name = "Ladder_%d_%d" % [x_col + 100, top_row + 100]
	root.add_child(ladder)
	ladder.owner = root
	ladder.position = Vector2(x_col * tile + tile / 2.0, zone_top)

	var cs := CollisionShape2D.new()
	var shp := RectangleShape2D.new()
	shp.size = Vector2(14, h)
	cs.shape = shp
	cs.position = Vector2(0, h / 2.0)
	cs.name = "CollisionShape2D"
	ladder.add_child(cs)
	cs.owner = root

	var np := NinePatchRect.new()
	var atlas := AtlasTexture.new()
	atlas.atlas = load("res://assets/sprites/world_tileset.png")
	atlas.region = Rect2(145, 52, 14, 12)
	np.texture = atlas
	np.patch_margin_top = 2
	np.patch_margin_bottom = 2
	np.axis_stretch_vertical = NinePatchRect.AXIS_STRETCH_MODE_TILE
	np.offset_left = -7
	np.offset_right = 7
	np.offset_top = 0
	np.offset_bottom = h
	np.name = "NinePatchRect"
	ladder.add_child(np)
	np.owner = root


# Move a named portal (and its co-located arrival marker) onto a clear ledge,
# foot resting on the surface. Optionally rename a legacy portal node.
func _reposition_portal(root: Node2D, pd: Dictionary, platforms: Array, tile: int) -> void:
	var portal: Node = root.get_node_or_null(pd.get("portal", ""))
	if portal == null and pd.has("rename"):
		portal = root.get_node_or_null(pd["rename"])  # already renamed on a prior run
	if portal == null:  # not present -> create a brand-new portal (e.g. a new link)
		portal = load("res://scenes/Gameplay/portal.tscn").instantiate()
		portal.name = pd.get("rename", pd.get("portal", "PortalNew"))
		root.add_child(portal)
		portal.owner = root
	if pd.has("target_map_id"):
		portal.set("target_map_id", pd["target_map_id"])
	if pd.has("target_spawn_point_name"):
		portal.set("target_spawn_point_name", pd["target_spawn_point_name"])
	var x_col := int(pd.x)
	var surf := _surface_row_at(platforms, x_col)
	if surf < 0:
		surf = 2
	var sx := x_col * tile + tile / 2.0
	portal.position = Vector2(sx, surf * tile - PORTAL_BOTTOM_OFFSET)
	if pd.has("rename"):
		portal.name = pd["rename"]
	var arr_name: String = pd.get("arrival", "")
	if arr_name != "":
		var arrival: Node = root.get_node_or_null(arr_name)
		if arrival == null:
			arrival = Marker2D.new()
			arrival.name = arr_name
			root.add_child(arrival)
			arrival.owner = root
		(arrival as Node2D).position = Vector2(sx + tile * 2.0, surf * tile - tile)


# Populate every platform with enemies, feet on the ground. Generates a slot per
# `enemy_spacing` tiles of platform width, then CLONES the map's existing enemy
# instances (cycling their types) until every slot is filled -> dense, MapleStory-
# style crowds. A boss map (boss_center / single enemy) just centers the boss.
func _distribute_enemies(root: Node2D, platforms: Array, tile: int, layout: Dictionary) -> void:
	var container := root.get_node_or_null("Enemies")
	if container == null or platforms.is_empty():
		return
	var enemies: Array = []
	for e in container.get_children():
		if e is Node2D:
			enemies.append(e)
	if enemies.is_empty():
		return

	var p0: Dictionary = platforms[0]
	if layout.get("boss_center", false) or enemies.size() == 1:
		enemies[0].position = Vector2((int(p0.x) + int(p0.w) / 2.0) * tile,
			int(p0.y) * tile + ENEMY_SURFACE_NUDGE)
		# Any remaining (adds) spread along the main ground.
		for i in range(1, enemies.size()):
			var fx: float = int(p0.x) + int(p0.w) * (i / float(enemies.size() + 1))
			enemies[i].position = Vector2(fx * tile, int(p0.y) * tile + ENEMY_SURFACE_NUDGE)
		return

	var spacing: int = int(layout.get("generate", {}).get("enemy_spacing", 6))
	var max_total: int = int(layout.get("generate", {}).get("max_enemies", 60))
	var slots: Array = _build_slots(platforms, tile, spacing, max_total)

	# Clone existing instances (by scene, cycling types) until every slot is filled.
	var types: Array = enemies.duplicate()
	while enemies.size() < slots.size():
		var src: Node = types[enemies.size() % types.size()]
		var path: String = src.scene_file_path
		var clone: Node = (load(path).instantiate() if path != "" else src.duplicate())
		clone.name = "Clone_%d" % enemies.size()  # prefix so re-runs can purge them
		container.add_child(clone)
		clone.owner = root
		enemies.append(clone)

	for i in enemies.size():
		if i < slots.size():
			enemies[i].position = slots[i]
		else:  # surplus originals -> tuck a second mob onto a slot for extra density
			enemies[i].position = slots[i % slots.size()] + Vector2(tile, 0)


# One enemy slot per `spacing` tiles of platform width (>=1 per platform so every
# tier is populated), feet on the surface. Shared by clone- and fresh-population.
func _build_slots(platforms: Array, tile: int, spacing: int, max_total: int) -> Array:
	var slots: Array = []
	for p in platforms:
		var cnt: int = clampi(int(p.w) / spacing, 1, 16)
		for k in cnt:
			var fx: float = int(p.x) + int(p.w) * (k + 0.5) / cnt
			slots.append(Vector2(fx * tile, int(p.y) * tile + ENEMY_SURFACE_NUDGE))
			if slots.size() >= max_total:
				return slots
	return slots


# Populate a FRESH map: instantiate enemies from `paths` (cycling) onto every
# platform slot. Used by brand-new generated maps that have no authored enemies.
func _populate_from_list(root: Node2D, platforms: Array, tile: int, paths: Array,
		spacing: int, max_total: int) -> void:
	var container := root.get_node_or_null("Enemies")
	if container == null or platforms.is_empty() or paths.is_empty():
		return
	var slots: Array = _build_slots(platforms, tile, spacing, max_total)
	for i in slots.size():
		var path: String = paths[i % paths.size()]
		if not ResourceLoader.exists(path):
			continue
		var e: Node = load(path).instantiate()
		e.name = "Mob_%d" % i
		container.add_child(e)
		e.owner = root
		(e as Node2D).position = slots[i]


# Build one EnemySpawner (Node2D + enemy_spawner.gd) with child markers and a
# child MultiplayerSpawner, mirroring ember_meadows' GoblinSpawner.
func _build_spawner(root: Node2D, enemies_node: Node, sp: Dictionary, idx: int, tile: int) -> void:
	var enemy_path: String = sp.get("enemy", "")
	if enemy_path == "" or not ResourceLoader.exists(enemy_path):
		push_error("Spawner %d: missing/invalid enemy scene '%s'" % [idx, enemy_path])
		return
	var enemy_scene: PackedScene = load(enemy_path)

	var spawner := Node2D.new()
	spawner.set_script(load(SPAWNER_SCRIPT))
	spawner.name = "%sSpawner%d" % [_to_pascal(enemy_path.get_file().get_basename()), idx]
	root.add_child(spawner)
	spawner.owner = root

	# Spawn-location markers (children of the spawner).
	var locs: Array[Marker2D] = []
	var loc_list: Array = sp.get("locations", [])
	for j in loc_list.size():
		var ld: Dictionary = loc_list[j]
		var m := Marker2D.new()
		m.name = "EnemySpawnLocation%d" % j
		spawner.add_child(m)
		m.owner = root
		m.position = Vector2(int(ld.x) * tile, int(ld.y) * tile)
		locs.append(m)

	# Child MultiplayerSpawner so enemies replicate to clients.
	var mp := MultiplayerSpawner.new()
	mp.set_script(load(MP_SPAWNER_SCRIPT))
	mp.name = "MultiplayerSpawner"
	spawner.add_child(mp)
	mp.owner = root
	var uid_id := ResourceLoader.get_resource_uid(enemy_path)
	var uid_text := ResourceUID.id_to_text(uid_id) if uid_id != ResourceUID.INVALID_ID else enemy_path
	mp.set("_spawnable_scenes", PackedStringArray([uid_text]))
	mp.spawn_path = NodePath("../../Enemies")
	mp.set("enemy_spawner", spawner)

	# Spawner exports (set AFTER children exist so NodePaths resolve in-scene).
	spawner.set("enemy_scene", enemy_scene)
	spawner.set("spawn_locations", locs)
	spawner.set("spawn_container", enemies_node)
	spawner.set("pool_size", int(sp.get("pool_size", 5)))
	spawner.set("respawn_delay", float(sp.get("respawn_delay", 3.0)))


func _to_pascal(s: String) -> String:
	var out := ""
	for part in s.split("_"):
		if part.length() > 0:
			out += part[0].to_upper() + part.substr(1)
	return out
