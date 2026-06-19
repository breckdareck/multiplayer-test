extends SceneTree
## Structurally-distinct maps (no slope tiles, so flat/stepped):
##   open / tower / cliffs. Solid ground -> Mid; drop-down platforms -> Platform
##   (one-way physics_layer_1); decorations -> Background2 (no collision).
## Clones ruins.tscn (which carries the Platform layer + updated TileSet).

const FLOOR_Y := 26
const ROCK_BAND := 2
const PORTAL_SPAWN_BUFFER := 14    # no enemy spawns within this many tiles of a portal edge
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
## Slope tiles live in their own atlas source (grass_slopes.png) injected as sources/3 by
## _inject_slopes. 2:1 ramps: each 1-tile rise spans 2 columns (a low half + a high half),
## so you walk straight up instead of jumping a staircase. Trapezoid collision per tile.
const SLOPE_SRC := 3
const BRIDGE_SRC := 5    # bridge_tiles.png injected as sources/5 by _inject_bridge (solid planks)
const WATER_SRC := 6     # water_tiles.png injected as sources/6 by _inject_water (surface walkable, body deco)
const COLUMN_SRC := 7    # stone_columns.png injected as sources/7 by _inject_columns (decorative, no collision)
const SLOPE_UR_LOW := Vector2i(0, 0)    # up-right ramp, low (left) half
const SLOPE_UR_HIGH := Vector2i(1, 0)   # up-right ramp, high (right) half
const SLOPE_UL_HIGH := Vector2i(2, 0)   # down-right ramp, high (left) half
const SLOPE_UL_LOW := Vector2i(3, 0)    # down-right ramp, low (right) half
## Hand-placed tower ladders [upper_branch_row, lower_platform_row, column] (tile coords),
## matching the approved climb. Each hangs from the upper branch with its bottom dangling
## ~1.5 tiles above the lower platform.
const TOWER_LADDERS := [
	[11, 17, 33], [25, 31, 7], [25, 31, 23], [31, 42, 18],
	[31, 37, 35], [37, 42, 30], [46, 51, 6], [46, 51, 18],
]
## Cliffs rope/ladder climbers up to the safe shelves: [upper_row, lower_row, col, type].
const CLIFFS_LADDERS := [
	[14, 22, 27, "rope"],     # mesa-1 shelf -> mesa 1
	[11, 19, 43, "ladder"],   # peak shelf -> peak
	[16, 22, 58, "rope"],     # mesa-3 shelf -> mesa 3
]

func _init() -> void:
	# Five new gap-filler maps for the hybrid world (2026-06-17), each on a DISTINCT archetype
	# (open tiers / cave / cliffs / tower / dark-open) so the road stops feeling same-y. Portals
	# are wired separately by tools/rebuild_portals.gd, so the configs omit them.
	var _args := OS.get_cmdline_user_args()
	var wave := _wave_fix()
	if "--terraces" in _args: wave = _wave_terraces_demo()
	elif "--gorge" in _args: wave = _wave_gorge_demo()
	elif "--shaft" in _args: wave = _wave_shaft_demo()
	elif "--causeway" in _args: wave = _wave_causeway_demo()
	elif "--warren" in _args: wave = _wave_warren_demo()
	elif "--hall" in _args: wave = _wave_hall_demo()
	for cfg in wave:
		var m: Dictionary
		match str(cfg.get("arch", "field")):
			"open": m = _build_open(cfg)
			"cave": m = _build_cave(cfg)
			"cliffs": m = _build_cliffs(cfg)
			"tower": m = _build_tower(cfg)
			"terraces": m = _build_terraces(cfg)
			"gorge": m = _build_gorge(cfg)
			"shaft": m = _build_shaft(cfg)
			"causeway": m = _build_causeway(cfg)
			"warren": m = _build_warren(cfg)
			"hall": m = _build_hall(cfg)
			_: m = _build_field(cfg)
		_emit(m)
		print("WROTE ", cfg["name"], " [", cfg.get("arch", "field"), "]")
	quit()

## Roster-balance pass (2026-06-19): regenerate off-band maps with the SAME terrain
## (same arch/seed/amp/width) but a level-appropriate roster, so each map's enemies fit its
## band. Enemy LEVELS are unchanged (shared EnemyData) — only WHICH enemies are placed; loot
## follows the tier automatically. Re-run rebuild_portals.gd afterwards (regen drops portals).
func _wave_fix() -> Array:
	return [
		# --- outer ring (low) ---
		{"name": "tinderfields", "arch": "open", "seed": 2101, "amp": 2, "width": 84,
			"display_name": "Tinderfields", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8], ["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8], ["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8]]},
		{"name": "bramble_downs", "arch": "open", "seed": 1501, "amp": 2, "width": 96,
			"display_name": "Bramble Downs", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8], ["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8], ["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 8]]},
		{"name": "brackenway", "arch": "cliffs", "seed": 2201, "width": 84,
			"display_name": "Brackenway", "bgm": "res://assets/music/emberwilds_near_wilds.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8], ["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 8], ["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 8]]},
		# --- spokes (mid) ---
		{"name": "mirefen", "arch": "cave", "seed": 2301, "width": 96,
			"display_name": "Mirefen", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 8], ["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 8], ["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 8]]},
		{"name": "the_reliquary", "arch": "cave", "seed": 2501, "width": 100,
			"display_name": "The Reliquary", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/cat_robber.tscn", "uid://dl6nk8ypor2fd", 8], ["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8], ["res://scenes/NPC/Minifolks/mithril_hare.tscn", "uid://dvymxl60snfn8", 8]]},
		{"name": "wolfsreach", "arch": "cliffs", "seed": 2601, "width": 96,
			"display_name": "Wolfsreach", "bgm": "res://assets/music/emberwilds_dust_warren.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/mithril_hare.tscn", "uid://dvymxl60snfn8", 8], ["res://scenes/NPC/Beastmen/deer_druid.tscn", "uid://b7uy8wgb0j1t3", 8], ["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 8]]},
		{"name": "the_undercroft", "arch": "cave", "seed": 1601, "width": 104,
			"display_name": "The Undercroft", "bgm": "res://assets/music/emberwilds_mines.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/deer_druid.tscn", "uid://b7uy8wgb0j1t3", 8], ["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 9], ["res://scenes/NPC/Beastmen/rabbit_wizard.tscn", "uid://dppxdoxl4kf2k", 8]]},
		# --- core (high) ---
		{"name": "mustering_fields", "seed": 1201, "amp": 2, "width": 110,
			"display_name": "The Mustering Fields", "bgm": "res://assets/music/emberwilds_keep.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/panda_warrior.tscn", "uid://dolpinlm1tsc0", 9], ["res://scenes/NPC/Minifolks/shadow_fox.tscn", "uid://c6qy8yi07kf2x", 8], ["res://scenes/NPC/Minifolks/runed_boar.tscn", "uid://tbl7yfcl3xwe", 8]]},
		{"name": "the_scorchline", "arch": "tower", "seed": 1801, "width": 52,
			"display_name": "The Scorchline", "bgm": "res://assets/music/emberwilds_emberscar.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/shadow_fox.tscn", "uid://c6qy8yi07kf2x", 8], ["res://scenes/NPC/Minifolks/runed_boar.tscn", "uid://tbl7yfcl3xwe", 8], ["res://scenes/NPC/fire_slime.tscn", "uid://bvjs3vxpdjkfj", 8]]},
		{"name": "cinderwaste", "seed": 1401, "amp": 4, "width": 120,
			"display_name": "The Cinderwaste", "bgm": "res://assets/music/emberwilds_emberscar.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/ember_fox.tscn", "uid://bichmn1gb8cd2", 8], ["res://scenes/NPC/Minifolks/wild_boar.tscn", "uid://oarco6h8le8s", 8], ["res://scenes/NPC/Minifolks/celestial_hare.tscn", "uid://cywi7283fngxu", 8]]},
	]

## Spoke-balance maps (2026-06-18): two mid maps so each town is 4 maps from Emberwatch (4/4/4).
## The Reliquary (deep old-world vault on the Lantern's "delve" spoke) + Wolfsreach (wolf crags on
## the Wickmoor "overland" spoke). monsters: [[scene_path, uid, pool], ...].
func _wave_v4() -> Array:
	return [
		{"name": "the_reliquary", "arch": "cave", "seed": 2501, "width": 100,
			"display_name": "The Reliquary", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/fox_swordsman.tscn", "uid://cdl2mfbs8qlub", 8], ["res://scenes/NPC/stone_slime.tscn", "uid://d2ciakulevex6", 8], ["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8]]},
		{"name": "wolfsreach", "arch": "cliffs", "seed": 2601, "width": 96,
			"display_name": "Wolfsreach", "bgm": "res://assets/music/emberwilds_dust_warren.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 9], ["res://scenes/NPC/Minifolks/mithril_hare.tscn", "uid://dvymxl60snfn8", 8], ["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 8]]},
	]

## Radial-world fill maps (2026-06-18): 2 low outer-ring fields (open/cliffs) + 2 mid spoke maps
## (cave/cliffs) for the Sleepywood wheel. Towns (Wickmoor/Hollowmere) are CLONED from
## lanterns_rest, not generated. monsters: [[scene_path, uid, pool], ...].
func _wave_v3() -> Array:
	return [
		{"name": "tinderfields", "arch": "open", "seed": 2101, "amp": 2, "width": 84,
			"display_name": "Tinderfields", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8], ["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 7], ["res://scenes/NPC/slime.tscn", "uid://q6iqwsi8meq4", 7]]},
		{"name": "brackenway", "arch": "cliffs", "seed": 2201, "width": 84,
			"display_name": "Brackenway", "bgm": "res://assets/music/emberwilds_near_wilds.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8], ["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 7], ["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 7]]},
		{"name": "mirefen", "arch": "cave", "seed": 2301, "width": 96,
			"display_name": "Mirefen", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 8], ["res://scenes/NPC/stone_slime.tscn", "uid://d2ciakulevex6", 8], ["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 8]]},
		{"name": "stonereach", "arch": "cliffs", "seed": 2401, "width": 96,
			"display_name": "Stonereach", "bgm": "res://assets/music/emberwilds_dust_warren.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/cat_robber.tscn", "uid://dl6nk8ypor2fd", 8], ["res://scenes/NPC/Minifolks/dust_fox.tscn", "uid://bleuqetjvkn5m", 8], ["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8]]},
	]

## The 5 hybrid-world gap-fillers, each tagged with the archetype it should be BUILT on so no
## two adjacent maps read the same. monsters: [[scene_path, uid, pool], ...].
func _wave_v2() -> Array:
	return [
		{"name": "bramble_downs", "arch": "open", "seed": 1501, "amp": 2, "width": 96,
			"display_name": "Bramble Downs", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8], ["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 7], ["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 7], ["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 8]]},
		{"name": "the_undercroft", "arch": "cave", "seed": 1601, "width": 104,
			"display_name": "The Undercroft", "bgm": "res://assets/music/emberwilds_mines.ogg",
			"monsters": [["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 9], ["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8], ["res://scenes/NPC/Beastmen/rabbit_wizard.tscn", "uid://dppxdoxl4kf2k", 8]]},
		{"name": "bandit_bluffs", "arch": "cliffs", "seed": 1701, "width": 92,
			"display_name": "Bandit Bluffs", "bgm": "res://assets/music/emberwilds_dust_warren.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/cat_robber.tscn", "uid://dl6nk8ypor2fd", 8], ["res://scenes/NPC/Beastmen/fox_swordsman.tscn", "uid://cdl2mfbs8qlub", 8], ["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 8]]},
		{"name": "the_scorchline", "arch": "tower", "seed": 1801, "width": 52,
			"display_name": "The Scorchline", "bgm": "res://assets/music/emberwilds_emberscar.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/lion_knight.tscn", "uid://dqirvq2t4dhx6", 8], ["res://scenes/NPC/Minifolks/runed_boar.tscn", "uid://tbl7yfcl3xwe", 8], ["res://scenes/NPC/fire_slime.tscn", "uid://bvjs3vxpdjkfj", 8]]},
		{"name": "the_unraveling", "arch": "open", "dark": true, "seed": 1901, "amp": 2, "width": 90,
			"display_name": "The Unraveling", "bgm": "res://assets/music/emberwilds_weave.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/celestial_hare.tscn", "uid://cywi7283fngxu", 9], ["res://scenes/NPC/astral_slime.tscn", "uid://5oi0b5vosx3q", 8]]},
	]

## The 4 maps added for branching (2026-06-17). Outdoor rolling fields; ashvigil is a calm safe
## hub (no monsters). Portals are wired separately by tools/rebuild_portals.gd, so omit them here.
func _wave_new() -> Array:
	return [
		{"name": "old_battlefield", "seed": 1101, "amp": 3, "width": 110,
			"display_name": "The Old Battlefield", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 9], ["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 9], ["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 9]]},
		{"name": "mustering_fields", "seed": 1201, "amp": 2, "width": 110,
			"display_name": "The Mustering Fields", "bgm": "res://assets/music/emberwilds_keep.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/lion_knight.tscn", "uid://dqirvq2t4dhx6", 9], ["res://scenes/NPC/Beastmen/panda_warrior.tscn", "uid://dolpinlm1tsc0", 9], ["res://scenes/NPC/Beastmen/bear_warrior.tscn", "uid://dreol0pnnwvme", 9]]},
		{"name": "ashvigil", "seed": 1301, "amp": 1, "width": 64,
			"display_name": "Ashvigil", "bgm": "res://assets/music/emberwilds_deep_woods.ogg",
			"monsters": []},
		{"name": "cinderwaste", "seed": 1401, "amp": 4, "width": 120,
			"display_name": "The Cinderwaste", "bgm": "res://assets/music/emberwilds_emberscar.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/ember_fox.tscn", "uid://bichmn1gb8cd2", 9], ["res://scenes/NPC/fire_slime.tscn", "uid://bvjs3vxpdjkfj", 9], ["res://scenes/NPC/Minifolks/runed_boar.tscn", "uid://tbl7yfcl3xwe", 9]]},
	]

## First-pass themed FIELD map from a compact config: rolling floor + auto safe platforms
## (one near each end + one every ~38 tiles) with ropes, plus the config's roster / portals /
## metadata / optional npcs+bosses. Distinct terrain (cave/mesa/float/arena) is layered in
## per the review pass; this nails the functional backbone for every map uniformly.
func _build_field(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var bottom := FLOOR_Y + 16
	var base_r := FLOOR_Y
	var ground := {}; var plat := {}; var slopes := {}
	var surf := _rolling_floor(width, bottom, base_r, int(cfg.get("amp", 2)), int(cfg["seed"]), ground, slopes)
	var safe_row := base_r - 7
	var safe_segs := [[6, 17]]
	var sx := 42
	while sx < width - 26:
		safe_segs.append([sx, sx + 11]); sx += 38
	safe_segs.append([width - 18, width - 7])
	_shelf(plat, surf, safe_row, safe_segs)
	var ladders := []
	for seg in safe_segs:
		var c: int = clampi(int((seg[0] + seg[1]) / 2.0), 0, width - 1)
		ladders.append([safe_row, int(surf[c]), c, "rope"])
	var d := {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [safe_row], "ladders": ladders, "player_spawn": Vector2i(11, safe_row - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
	return d

## CAVE archetype (mines): rolling floor + a solid rolling CEILING ~12 tiles above it, so the
## play space is an enclosed chamber. Stalactites hang from the ceiling, stalagmites rise from
## the floor; the thick rock goes black-core dark. Safe ledges sit in the chamber.
func _build_cave(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 9
	var ground := {}; var plat := {}; var slopes := {}
	var fsurf := _rolling_floor(width, bottom, base_r, 0, int(cfg["seed"]), ground, slopes)   # flat floor
	var rng := RandomNumberGenerator.new(); rng.seed = int(cfg["seed"]) + 7
	# High spiky ceiling — keeps headroom above the top ledge tier (no ceiling-bonk).
	var ceil_r := base_r - 22
	for x in range(width):
		ceil_r = clampi(ceil_r + rng.randi_range(-1, 1), base_r - 24, base_r - 20)
		for y in range(0, ceil_r + 1): ground[Vector2i(x, y)] = true            # solid ceiling
		if rng.randf() < 0.18:                                                   # stalactite (short)
			for y in range(ceil_r + 1, ceil_r + 1 + rng.randi_range(1, 2)): ground[Vector2i(x, y)] = true
		if rng.randf() < 0.08:                                                   # stalagmite
			for y in range(fsurf[x] - rng.randi_range(1, 2), fsurf[x]): ground[Vector2i(x, y)] = true
	# Enemy ledge tiers — SOLID rock (so they take the rock-top surface, not green platform
	# tiles). 5 rows apart for jump headroom; placed outside the portal buffers.
	var ledges := []
	for tr in [base_r - 14, base_r - 9, base_r - 4]:
		var lx := rng.randi_range(PORTAL_SPAWN_BUFFER + 2, PORTAL_SPAWN_BUFFER + 8)
		while lx < width - PORTAL_SPAWN_BUFFER - 3:
			var lw := rng.randi_range(3, 6)
			for cx in range(lx, lx + lw): ground[Vector2i(cx, tr)] = true
			ledges.append([lx + int(lw / 2.0), tr])
			lx += lw + rng.randi_range(6, 11)
	# Enemy-free rock ledges inside the portal-buffer zones (left + right) — safe spawn / AFK.
	var safe_r := base_r - 8
	for sx in [8, width - 14]:
		for cx in range(sx, sx + 6): ground[Vector2i(cx, safe_r)] = true
	# Climbers: a ladder off the left spawn ledge + a rope from each enemy ledge to the floor.
	var ladders := [[safe_r, int(fsurf[11]), 11, "ladder"]]
	for lg in ledges:
		var lc: int = clampi(int(lg[0]), 0, width - 1)
		ladders.append([int(lg[1]), int(fsurf[lc]), lc, "rope"])
	# Background: solid black behind the whole chamber (your 4,7 tile), no village backdrop.
	var bgwall := {}
	for x in range(width):
		for y in range(bottom + 1):
			var cell := Vector2i(x, y)
			if not ground.has(cell): bgwall[cell] = [4, 7]
	# Explicit spawn spots so enemies sit on the rock ledges + chamber floor (the generic floor
	# sampler would read the cave CEILING as the surface and spawn enemies up there instead).
	var spawn_spots := []
	for lg in ledges: spawn_spots.append(Vector2i(int(lg[0]), int(lg[1])))
	var fcx := PORTAL_SPAWN_BUFFER + 4
	while fcx < width - PORTAL_SPAWN_BUFFER - 4:
		spawn_spots.append(Vector2i(fcx, int(fsurf[fcx]))); fcx += 10
	var d := {
		"bgwall": bgwall, "rock_top": true, "spawn_spots": spawn_spots,
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [], "ladders": ladders, "player_spawn": Vector2i(11, base_r - 9),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
		"ceiling_below": base_r - 16, "no_trees": true, "no_village_bg": true, "no_deco": true,
	}
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
	return d

## OPEN archetype (Henesys field): rolling floor + a left enemy-free spawn perch + THREE tiers
## of floating one-way fighting shelves linked bottom-to-top by ropes/ladders. `dark` renders it
## as bare rock over a black void (the astral / wound theme) instead of grassy field.
func _build_open(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 14
	var ground := {}; var plat := {}; var slopes := {}
	var surf := _rolling_floor(width, bottom, base_r, int(cfg.get("amp", 2)), int(cfg["seed"]), ground, slopes)
	# Left safe perch (its own row so it never overlaps a fighting tier): spawn + AFK/heal spot.
	var safe_row := base_r - 4
	_shelf(plat, surf, safe_row, [[6, 15]])
	# Three fighting tiers floating above the field, scaled to the map width.
	var l1 := base_r - 7; var l2 := base_r - 11; var l3 := base_r - 16
	var a: int = int(width * 0.20); var b: int = int(width * 0.49)
	var c: int = int(width * 0.55); var dd: int = width - 8
	_shelf(plat, surf, l1, [[a, b], [c, dd]])
	_shelf(plat, surf, l2, [[int(width * 0.16), int(width * 0.62)]])
	_shelf(plat, surf, l3, [[int(width * 0.32), int(width * 0.78)]])
	# Climbers: spawn-perch rope, floor -> L1 (x2), L1 -> L2, L2 -> L3.
	var ladders := [
		[safe_row, int(surf[10]), 10, "rope"],
		[l1, int(surf[a + 6]), a + 6, "ladder"],
		[l1, int(surf[dd - 6]), dd - 6, "rope"],
		[l2, l1, int(width * 0.30), "rope"],
		[l3, l2, int(width * 0.46), "ladder"],
	]
	var d := {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [safe_row], "ladders": ladders, "player_spawn": Vector2i(10, safe_row - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}
	if cfg.get("dark", false):                       # astral void treatment
		d["rock_top"] = true; d["no_trees"] = true; d["no_village_bg"] = true; d["no_deco"] = true
		var bgwall := {}
		for x in range(width):
			for y in range(bottom + 1):
				var cell := Vector2i(x, y)
				if not ground.has(cell): bgwall[cell] = [4, 7]
		d["bgwall"] = bgwall
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	return d

## Demo wave: a single standalone Terraces test map (scratch file gen_terraces.tscn), so we can
## eyeball the archetype before wiring it into the real world. Run: generator -- --terraces
func _wave_terraces_demo() -> Array:
	return [
		{"name": "gen_terraces", "arch": "terraces", "seed": 3001, "width": 88,
			"display_name": "Terraces (test)", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8],
				["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8],
				["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8]]},
	]

## TERRACES archetype: a flat base floor + an orderly ASCENDING STAIRCASE of wide one-way shelves,
## each shifted sideways and linked to the one below by a rope/ladder. Every gap is >1 tile, so you
## always CLIMB — never a blind jump. Top shelf is the SAFE/AFK tier (no spawns). Clean grind lanes.
func _build_terraces(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 10
	var ground := {}; var plat := {}; var slopes := {}
	var surf := []; surf.resize(width)
	for x in range(width):
		surf[x] = base_r
		for y in range(base_r, bottom + 1):
			ground[Vector2i(x, y)] = true
	# Left SAFE perch: enemy-free spawn + AFK spot, off the enemy floor (3 tiles up).
	var safe_row := base_r - 3
	_shelf(plat, surf, safe_row, [[2, 12]])
	var step := 4
	var t1 := base_r - step; var t2 := base_r - 2 * step; var t3 := base_r - 3 * step; var t4 := base_r - 4 * step
	_shelf(plat, surf, t1, [[int(width * 0.18), int(width * 0.58)]])
	_shelf(plat, surf, t2, [[int(width * 0.30), int(width * 0.80)]])
	_shelf(plat, surf, t3, [[int(width * 0.12), int(width * 0.58)]])
	_shelf(plat, surf, t4, [[int(width * 0.40), int(width * 0.86)]])   # top tier (has mobs)
	var ladders := [
		[safe_row, base_r, 5, "rope"],               # spawn perch -> floor (climb down to grind)
		[t1, base_r, int(width * 0.22), "rope"],     # floor -> T1
		[t2, t1, int(width * 0.42), "rope"],         # T1 -> T2
		[t3, t2, int(width * 0.45), "ladder"],       # T2 -> T3
		[t4, t3, int(width * 0.50), "rope"],         # T3 -> T4 (safe)
	]
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [safe_row], "ladders": ladders, "player_spawn": Vector2i(5, safe_row - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}

## Demo wave: a single standalone Gorge test map (gen_gorge.tscn). Run: generator -- --gorge
func _wave_gorge_demo() -> Array:
	return [
		{"name": "gen_gorge", "arch": "gorge", "seed": 3101, "width": 92,
			"display_name": "Gorge (test)", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8],
				["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8],
				["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8]]},
	]

## GORGE archetype: two solid rims split by a deep chasm, crossed by a WOODEN BRIDGE at walk
## level (solid plank tiles, source BRIDGE_SRC). Left rim has the safe spawn perch; right rim has
## a vantage shelf (also has mobs) reached by rope. Enemies on both rims + bridge + vantage. The void under the
## bridge is dark bgwall so the depth reads. New-tile pipeline: _inject_bridge adds the plank source.
func _build_gorge(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 12
	var ground := {}; var plat := {}; var slopes := {}; var bridge := {}; var bgwall := {}
	var surf := []; surf.resize(width)
	for x in range(width): surf[x] = base_r
	var left_end := int(width * 0.34)        # left rim = cols [0, left_end)
	var right_start := int(width * 0.66)     # right rim = cols [right_start, width)
	for x in range(0, left_end):
		for y in range(base_r, bottom + 1): ground[Vector2i(x, y)] = true
	for x in range(right_start, width):
		for y in range(base_r, bottom + 1): ground[Vector2i(x, y)] = true
	# Wooden bridge across the chasm at walk level (solid). L / mid / R plank tiles.
	for x in range(left_end, right_start):
		var tx := 1
		if x == left_end: tx = 0
		elif x == right_start - 1: tx = 2
		bridge[Vector2i(x, base_r)] = [tx, 0]
	# Dark void under the bridge (depth).
	for x in range(left_end, right_start):
		for y in range(base_r + 1, bottom + 1): bgwall[Vector2i(x, y)] = [4, 7]
	# Left safe spawn perch + right vantage shelf (both enemy-free).
	var perch := base_r - 3
	_shelf(plat, surf, perch, [[3, 12]])
	var vant := base_r - 6
	_shelf(plat, surf, vant, [[int(width * 0.74), int(width * 0.94)]])
	var ladders := [
		[perch, base_r, 5, "rope"],                          # perch -> left rim floor
		[vant, base_r, int(width * 0.80), "rope"],           # right rim floor -> vantage shelf
	]
	# Explicit spawns: left rim, bridge, right rim (skips the perch/vantage safe shelves).
	var spawn_spots := []
	var c := 4
	while c < left_end - 2: spawn_spots.append(Vector2i(c, base_r)); c += 6
	c = left_end + 3
	while c < right_start - 2: spawn_spots.append(Vector2i(c, base_r)); c += 7   # on the bridge
	c = right_start + 2
	while c < width - 3: spawn_spots.append(Vector2i(c, base_r)); c += 6
	c = int(width * 0.76)                                          # mobs on the top vantage shelf too
	while c < int(width * 0.92): spawn_spots.append(Vector2i(c, vant)); c += 6
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"bridge": bridge, "bgwall": bgwall, "no_village_bg": true,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [perch], "ladders": ladders, "spawn_spots": spawn_spots,
		"player_spawn": Vector2i(5, perch - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}

## Demo wave: a single standalone Shaft test map (gen_shaft.tscn). Run: generator -- --shaft
func _wave_shaft_demo() -> Array:
	return [
		{"name": "gen_shaft", "arch": "shaft", "seed": 3201, "width": 30,
			"display_name": "Shaft (test)", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8],
				["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8],
				["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8]]},
	]

## SHAFT / ROPEWORKS archetype: a tall, NARROW, enclosed rock shaft (solid walls both sides) with
## alternating one-way ledges rising up the centre, each linked to the one below by a ROPE (the
## ascent is rope-dominant — ledges are >1 tile apart). Left bottom is the safe spawn perch; every
## other ledge (incl. the top) has mobs. Dark rock void behind (rock_top + bgwall).
func _build_shaft(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var bottom := 55
	var floor_y := bottom - 4
	var wall := 3
	var ground := {}; var plat := {}
	for x in range(width):
		for y in range(floor_y, bottom + 1): ground[Vector2i(x, y)] = true   # floor
	for x in range(0, wall):
		for y in range(6, bottom + 1): ground[Vector2i(x, y)] = true          # left wall
	for x in range(width - wall, width):
		for y in range(6, bottom + 1): ground[Vector2i(x, y)] = true          # right wall
	# Alternating ledges rising up the shaft, overlapping in the centre. ledge0 = RIGHT (away from
	# the left spawn perch), then alternate L/R.
	var ledges := []
	var r := floor_y - 5; var idx := 0
	while r > 10:
		var x0: int; var x1: int
		if idx % 2 == 0: x0 = int(width * 0.40); x1 = width - wall    # right ledge
		else: x0 = wall; x1 = int(width * 0.60)                       # left ledge
		_seg(plat, x0, x1, r)
		ledges.append([x0, x1, r])
		r -= 5; idx += 1
	# Ropes: floor -> ledge0, then each ledge -> the one below it (centre-overlap column).
	var ladders := []
	if ledges.size() > 0:
		var b0 = ledges[0]
		ladders.append([int(b0[2]), floor_y, int((b0[0] + b0[1]) / 2.0), "rope"])
	for i in range(1, ledges.size()):
		var up = ledges[i]; var lo = ledges[i - 1]
		var ov0: int = maxi(int(up[0]), int(lo[0])); var ov1: int = mini(int(up[1]), int(lo[1]))
		var col: int = int((ov0 + ov1) / 2.0) if ov0 <= ov1 else int((up[0] + up[1]) / 2.0)
		ladders.append([int(up[2]), int(lo[2]), col, "rope"])
	# Left safe spawn perch (enemy-free) + rope down to the floor.
	var perch := floor_y - 3
	_seg(plat, wall, wall + 7, perch)
	ladders.append([perch, floor_y, wall + 2, "rope"])
	var bgwall := {}
	for x in range(width):
		for y in range(bottom + 1):
			var cell := Vector2i(x, y)
			if not ground.has(cell): bgwall[cell] = [4, 7]
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": {},
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [perch], "ladders": ladders, "player_spawn": Vector2i(wall + 2, perch - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
		"bgwall": bgwall, "rock_top": true, "no_trees": true, "no_village_bg": true, "no_deco": true,
	}

## Demo wave: a single standalone Causeway test map (gen_causeway.tscn). Run: generator -- --causeway
func _wave_causeway_demo() -> Array:
	return [
		{"name": "gen_causeway", "arch": "causeway", "seed": 3301, "width": 88,
			"display_name": "Causeway (test)", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 8],
				["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 8],
				["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 8]]},
	]

## CAUSEWAY archetype: a long WALKABLE strip over water. The middle is shallow water-SURFACE tiles
## (solid/walkable — no swim, no damage), with scenic deep water-BODY behind/below (Background2, no
## collision). Shores at both ends; a couple low stepping platforms + a left safe spawn perch. Water
## is pure scenery. New-tile pipeline: _inject_water adds the water source (collision on surface only).
func _build_causeway(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 8
	# Mostly GROUND with a central water GAP the BRIDGE spans end-to-end. Water is BACKGROUND
	# only (Background2, behind the bridge) — pure scenery, never walked on.
	var sh_l := int(width * 0.30)        # left ground shore  = [0, sh_l)
	var sh_r := int(width * 0.66)        # right ground shore = [sh_r, width); gap = [sh_l, sh_r)
	var ground := {}; var plat := {}; var water_body := {}; var bridge := {}
	for x in range(0, sh_l):
		for y in range(base_r, bottom + 1): ground[Vector2i(x, y)] = true        # left shore
	for x in range(sh_r, width):
		for y in range(base_r, bottom + 1): ground[Vector2i(x, y)] = true        # right shore
	for x in range(sh_l, sh_r):                                                   # bridge across the WHOLE gap
		var tx := 1
		if x == sh_l: tx = 0
		elif x == sh_r - 1: tx = 2
		bridge[Vector2i(x, base_r)] = [tx, 0]
	for x in range(sh_l, sh_r):                                                   # water = background scenery in the gap
		water_body[Vector2i(x, base_r)] = [0, 0]                                  # surface (sheet row 0, anim base)
		for y in range(base_r + 1, bottom + 1): water_body[Vector2i(x, y)] = [0, 1]   # deep body (sheet row 1, anim base)
	# Left safe spawn perch + one ranged platform above the bridge.
	var perch := base_r - 3
	_seg(plat, 2, 8, perch)
	var p1 := base_r - 5
	_seg(plat, int(width * 0.40), int(width * 0.58), p1)
	var ladders := [
		[perch, base_r, 4, "rope"],
		[p1, base_r, int(width * 0.46), "rope"],
	]
	# Explicit spawns: left shore, the bridge, right shore, platform.
	var spawn_spots := []
	var c := 4
	while c < sh_l - 1: spawn_spots.append(Vector2i(c, base_r)); c += 5
	c = sh_l + 2
	while c < sh_r - 2: spawn_spots.append(Vector2i(c, base_r)); c += 6
	c = sh_r + 2
	while c < width - 3: spawn_spots.append(Vector2i(c, base_r)); c += 5
	spawn_spots.append(Vector2i(int(width * 0.48), p1))
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": {},
		"water_body": water_body, "bridge": bridge, "no_village_bg": true,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [perch], "ladders": ladders, "spawn_spots": spawn_spots,
		"player_spawn": Vector2i(4, perch - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}

## Demo wave: a single standalone Warren test map (gen_warren.tscn). Run: generator -- --warren
func _wave_warren_demo() -> Array:
	return [
		{"name": "gen_warren", "arch": "warren", "seed": 3401, "width": 60,
			"display_name": "Warren (test)", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 8],
				["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 8],
				["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 8]]},
	]

## WARREN archetype: a solid rock mass carved into a maze of small ROOMS. A lower row of rooms is
## linked by horizontal TUNNELS (walk through); two upper dead-end POCKETS are reached only by a
## ROPE up a carved shaft. Leftmost lower room is the safe spawn (no mobs); every other room has
## mobs. Dark rock (rock_top + bgwall). No new tiles.
func _build_warren(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var top := 8
	var bottom := 36
	var floor_lo := 30
	var floor_hi := 18
	var ground := {}; var plat := {}
	var empty := {}
	var lower := [[4, 18], [23, 37], [42, 56]]    # rooms A, B, C (share floor_lo)
	for rm in lower:
		for x in range(rm[0], rm[1]):
			for y in range(floor_lo - 5, floor_lo): empty[Vector2i(x, y)] = true
	for gx in [[18, 23], [37, 42]]:               # tunnels between adjacent lower rooms
		for x in range(gx[0], gx[1]):
			for y in range(floor_lo - 2, floor_lo): empty[Vector2i(x, y)] = true
	var upper := [[10, 24], [36, 50]]             # rooms D, E (dead-end pockets, floor_hi)
	for rm in upper:
		for x in range(rm[0], rm[1]):
			for y in range(floor_hi - 5, floor_hi): empty[Vector2i(x, y)] = true
	for sx in [[13, 15], [45, 47]]:               # vertical rope shafts (A->D, C->E)
		for x in range(sx[0], sx[1]):
			for y in range(floor_hi, floor_lo): empty[Vector2i(x, y)] = true
	for x in range(width):                        # fill solid rock except carved cavities
		for y in range(top, bottom + 1):
			var cell := Vector2i(x, y)
			if not empty.has(cell): ground[cell] = true
	var ladders := [
		[floor_hi, floor_lo, 13, "rope"],         # A -> D
		[floor_hi, floor_lo, 45, "rope"],         # C -> E
	]
	# Explicit spawns: rooms B, C (lower) + D, E (upper). Room A = safe spawn (no spots).
	var spawn_spots := []
	for cx in [28, 33]: spawn_spots.append(Vector2i(cx, floor_lo))
	for cx in [46, 51]: spawn_spots.append(Vector2i(cx, floor_lo))
	for cx in [14, 20]: spawn_spots.append(Vector2i(cx, floor_hi))
	for cx in [40, 46]: spawn_spots.append(Vector2i(cx, floor_hi))
	var bgwall := {}
	for x in range(width):
		for y in range(bottom + 1):
			var cell := Vector2i(x, y)
			if not ground.has(cell): bgwall[cell] = [4, 7]
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": {},
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [], "ladders": ladders, "spawn_spots": spawn_spots,
		"player_spawn": Vector2i(8, floor_lo - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
		"bgwall": bgwall, "rock_top": true, "no_trees": true, "no_village_bg": true, "no_deco": true,
	}

## Demo wave: a single standalone Hall/Ruins test map (gen_hall.tscn). Run: generator -- --hall
func _wave_hall_demo() -> Array:
	return [
		{"name": "gen_hall", "arch": "hall", "seed": 3501, "width": 72,
			"display_name": "Hall (test)", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 8],
				["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 8],
				["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8]]},
	]

## Place one decorative column of width `w` from L/M/R column tiles (background dict). `broken` tops
## it with the jagged broken piece (ruined pillar) instead of a capital.
func _place_column(columns: Dictionary, px: int, w: int, top_row: int, base_row: int, broken: bool) -> void:
	var topp := 3 if broken else 0
	for i in range(w):
		var x := px + i
		var ec := 0 if i == 0 else (2 if i == w - 1 else 1)   # L / M / R
		columns[Vector2i(x, top_row)] = [ec, topp]
		for y in range(top_row + 1, base_row): columns[Vector2i(x, y)] = [ec, 1]   # shaft
		columns[Vector2i(x, base_row)] = [ec, 2]                                    # base


## HALL / RUINS archetype: an open walkable floor framed by DECORATIVE stone columns (background,
## non-colliding — you walk straight past them), with broken upper LEDGES between the columns reached
## by ropes. Left safe spawn perch; mobs on the floor + the ledges. Uses the new column tiles.
func _build_hall(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 8
	var ground := {}; var plat := {}; var columns := {}
	for x in range(width):
		for y in range(base_r, bottom + 1): ground[Vector2i(x, y)] = true        # open floor
	# Decorative columns (Background, non-colliding), built from L/M/R tiles so they vary in width.
	# Mix of full (capital-topped) and broken (ruined, shorter) columns for the ruins look.
	var base_row := base_r - 1
	_place_column(columns, 8, 3, base_r - 13, base_row, false)    # full, 3-thick
	_place_column(columns, 22, 2, base_r - 9, base_row, true)     # broken, 2-thick (shorter)
	_place_column(columns, 34, 2, base_r - 13, base_row, false)   # full, 2-thick
	_place_column(columns, 48, 3, base_r - 10, base_row, true)    # broken, 3-thick
	_place_column(columns, 62, 2, base_r - 13, base_row, false)   # full, 2-thick
	# Broken upper ledges between the columns (one-way), reached by rope.
	var led := base_r - 7
	_seg(plat, 14, 30, led)
	_seg(plat, 38, 56, led)
	# Left safe spawn perch.
	var perch := base_r - 3
	_seg(plat, 2, 8, perch)
	var ladders := [
		[perch, base_r, 4, "rope"],
		[led, base_r, 18, "rope"],
		[led, base_r, 44, "rope"],
	]
	# Explicit spawns: the floor + the two upper ledges (not the perch).
	var spawn_spots := []
	var c := 12
	while c < width - 4: spawn_spots.append(Vector2i(c, base_r)); c += 7
	for cx in [20, 26]: spawn_spots.append(Vector2i(cx, led))
	for cx in [42, 50]: spawn_spots.append(Vector2i(cx, led))
	return {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": {},
		"columns": columns, "no_village_bg": true, "no_trees": true,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [perch], "ladders": ladders, "spawn_spots": spawn_spots,
		"player_spawn": Vector2i(5, perch - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}

## CLIFFS archetype: a left-to-right chain of solid mesas at varied heights, joined by 2:1 grass
## ramps you walk straight up (no jumping steps). A one-way vantage shelf floats over each wide
## mesa (enemy-free), reached by a rope/ladder. Seeded so each map's skyline differs.
func _build_cliffs(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var base_r := FLOOR_Y
	var bottom := base_r + 8
	var ground := {}; var plat := {}; var slopes := {}
	var rng := RandomNumberGenerator.new(); rng.seed = int(cfg["seed"])
	var surf := []; surf.resize(width)
	for i in range(width): surf[i] = base_r
	# Plan: base flat, then alternating up-mesa / down-step until the width is roughly spent.
	var plan := [["flat", base_r, rng.randi_range(8, 11)]]
	var cur := base_r; var est := int(plan[0][2])
	while est < width - 12:
		var up := base_r - rng.randi_range(3, 7)
		var uf := rng.randi_range(8, 13)
		plan.append(["ramp", up]); plan.append(["flat", up, uf])
		est += absi(cur - up) * 2 + uf; cur = up
		var down := base_r - rng.randi_range(0, 3)
		var df := rng.randi_range(6, 11)
		plan.append(["ramp", down]); plan.append(["flat", down, df])
		est += absi(cur - down) * 2 + df; cur = down
	plan.append(["flat", base_r - rng.randi_range(0, 2), 999])   # fill the right edge
	# Execute the plan into surf/slopes, recording each ELEVATED flat mesa span [start, end, row].
	var mesas := []
	var x := 0; cur = base_r
	for step in plan:
		if x >= width: break
		if step[0] == "flat":
			cur = int(step[1])
			var sx := x
			for _i in range(int(step[2])):
				if x >= width: break
				surf[x] = cur; x += 1
			if cur < base_r: mesas.append([sx, x - 1, cur])
		else:
			var target := int(step[1])
			var goup := target < cur
			for _s in range(absi(cur - target)):
				if x + 1 >= width: break
				if goup:
					var row := cur - 1
					slopes[Vector2i(x, row)] = SLOPE_UR_LOW
					slopes[Vector2i(x + 1, row)] = SLOPE_UR_HIGH
					surf[x] = row; surf[x + 1] = row; cur = row
				else:
					slopes[Vector2i(x, cur)] = SLOPE_UL_HIGH
					slopes[Vector2i(x + 1, cur)] = SLOPE_UL_LOW
					surf[x] = cur; surf[x + 1] = cur; cur += 1
				x += 2
	for col in range(width):
		for y in range(surf[col], bottom + 1): ground[Vector2i(col, y)] = true
	# A vantage shelf + climber over every wide mesa; all vantages stay enemy-free.
	var ladders := []; var safe_rows := []
	var pspawn := Vector2i(5, base_r - 1)
	for i in mesas.size():
		var mz = mesas[i]
		if mz[1] - mz[0] + 1 < 5: continue
		var srow: int = int(mz[2]); var shelf_row: int = srow - 6
		var s0: int = mz[0] + 1; var s1: int = mz[1] - 1
		_shelf(plat, surf, shelf_row, [[s0, s1]])
		var lc: int = int((s0 + s1) / 2.0)
		ladders.append([shelf_row, srow, lc, "rope" if i % 2 == 0 else "ladder"])
		safe_rows.append(shelf_row)
		if pspawn.x == 5: pspawn = Vector2i(lc, shelf_row - 1)   # spawn on the first vantage
	var d := {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": safe_rows, "ladders": ladders, "player_spawn": pspawn,
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
	}
	if cfg.get("dark", false): d["rock_top"] = true; d["no_trees"] = true
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	return d

## TOWER archetype (Forest-of-Ellinia): an organic vertical climb of floating branch platforms
## at varied lengths / heights, linked bottom-to-top by ropes; a solid base floor (the spawn)
## with a dark void behind the canopy. Top branch is the enemy-free perch. Seeded per map.
func _build_tower(cfg: Dictionary) -> Dictionary:
	var width: int = int(cfg["width"])
	var bottom := 55
	var floor_y := bottom - 4
	var ground := {}; var plat := {}
	var rng := RandomNumberGenerator.new(); rng.seed = int(cfg["seed"])
	for x in range(width):
		for y in range(floor_y, bottom + 1): ground[Vector2i(x, y)] = true
	var branches := []                                # [x0, x1, row], bottom-up
	var cur_x := rng.randi_range(4, 12)
	var cur_y := floor_y - rng.randi_range(4, 6)
	while cur_y > 9:
		var ln := rng.randi_range(16, 26)
		var x0 := clampi(cur_x, 2, width - 3 - ln)
		_seg(plat, x0, x0 + ln, cur_y)
		branches.append([x0, x0 + ln - 1, cur_y])
		if rng.randf() < 0.35:                         # same-level side off-shoot for fullness
			var sl := rng.randi_range(6, 10)
			var sdir := 1 if rng.randf() < 0.5 else -1
			var sbase := (x0 + ln) if sdir > 0 else (x0 - sl)
			var sx := clampi(sbase + sdir * rng.randi_range(1, 5), 2, width - 3 - sl)
			var _oy := rng.randi_range(0, 2)
			_seg(plat, sx, sx + sl, cur_y)
		var dy := rng.randi_range(4, 6)
		var ny := cur_y - dy
		var dir := 0
		if x0 < int(width * 0.35): dir = 1
		elif x0 > int(width * 0.55): dir = -1
		else: dir = 1 if rng.randf() < 0.5 else -1
		cur_x = clampi(x0 + dir * rng.randi_range(11, 20), 2, width - 9)
		cur_y = ny
	# Ropes: base floor -> branch 0, then each lower branch -> the one above it.
	var ladders := []
	if branches.size() > 0:
		var b0 = branches[0]
		ladders.append([int(b0[2]), floor_y, int((b0[0] + b0[1]) / 2.0), "rope"])
	for i in range(1, branches.size()):
		var up = branches[i]; var lo = branches[i - 1]
		var ov0: int = maxi(int(up[0]), int(lo[0])); var ov1: int = mini(int(up[1]), int(lo[1]))
		var col: int = int((ov0 + ov1) / 2.0) if ov0 <= ov1 else clampi(int((up[0] + up[1]) / 2.0), int(up[0]), int(up[1]))
		ladders.append([int(up[2]), int(lo[2]), col, "rope"])
	var safe_rows := []
	if branches.size() > 0: safe_rows.append(int(branches[branches.size() - 1][2]))
	var bgwall := {}
	for x in range(width):
		for y in range(bottom + 1):
			var cell := Vector2i(x, y)
			if not ground.has(cell): bgwall[cell] = [4, 7]
	var d := {
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": {},
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": safe_rows, "ladders": ladders, "player_spawn": Vector2i(int(width / 2.0), floor_y - 1),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
		"bgwall": bgwall, "rock_top": true, "no_trees": true, "no_village_bg": true, "no_deco": true,
	}
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	return d

func _wave1() -> Array:
	return [
		{"name": "meadow_path", "seed": 22, "amp": 2, "width": 70,
			"display_name": "Slime Meadow", "bgm": "res://assets/music/emberwilds_meadow_path.ogg",
			"monsters": [["res://scenes/NPC/slime.tscn", "uid://q6iqwsi8meq4", 8], ["res://scenes/NPC/Minifolks/bunny.tscn", "uid://c06qbiant345e", 6]],
			"portals": [["right", "ember_meadows", "EmberMeadows_Meadow_Portal_Spawn", "PortalToEmberMeadows", "Hub_Meadow_Spawn"]]},
		{"name": "ember_meadows", "seed": 33, "amp": 2, "width": 120,
			"display_name": "Ember-Meadows", "bgm": "res://assets/music/emberwilds_ember_meadows.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 5], ["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 4], ["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 4], ["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 6]],
			"portals": [["left", "near_wilds", "NearWilds_EmberMeadows_Portal_Spawn", "PortalToNearWilds", "EmberMeadows_NearWilds_Portal_Spawn"], ["right", "ruins", "Ruins_EmberMeadows_Portal_Spawn", "PortalToRuins", "EmberMeadows_Ruins_Portal_Spawn"], ["mid", "meadow_path", "Hub_Meadow_Spawn", "PortalToMeadow", "EmberMeadows_Meadow_Portal_Spawn"]]},
		{"name": "three_terraces", "seed": 44, "amp": 3, "width": 90,
			"display_name": "Windmill Terraces", "bgm": "res://assets/music/emberwilds_three_terraces.ogg",
			"monsters": [["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 6], ["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 5]],
			"portals": [["right", "ruins", "Ruins_Terraces_Portal_Spawn", "PortalToRuins", "Hub_Terraces_Spawn"]]},
	]

## All remaining real maps. ruins is LAST because it's the clone TEMPLATE — every other map
## clones the original ruins.tscn; regenerating ruins before them would change their template.
func _wave_rest() -> Array:
	return [
		{"name": "deep_woods", "seed": 52, "amp": 2, "width": 120,
			"display_name": "The Deep Woods", "bgm": "res://assets/music/emberwilds_deep_woods.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/bear_warrior.tscn", "uid://dreol0pnnwvme", 6], ["res://scenes/NPC/Minifolks/dark_bunny.tscn", "uid://ce1gj48yfxtud", 6], ["res://scenes/NPC/Beastmen/lion_knight.tscn", "uid://dqirvq2t4dhx6", 6], ["res://scenes/NPC/adamant_crawler.tscn", "uid://co7gditu46kn8", 6]],
			"portals": [["right", "keep", "Keep_DeepWoods_Portal_Spawn", "PortalToKeep", "DeepWoods_Keep_Portal_Spawn"], ["left", "emberwatch", "Emberwatch_DeepWoods_Portal_Spawn", "PortalToEmberwatch", "DeepWoods_Emberwatch_Portal_Spawn"]]},
		{"name": "thornroot", "seed": 281, "amp": 3, "width": 100,
			"display_name": "Thornroot Hollow", "bgm": "res://assets/music/emberwilds_thornroot.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 7], ["res://scenes/NPC/Beastmen/fox_swordsman.tscn", "uid://cdl2mfbs8qlub", 6], ["res://scenes/NPC/stone_slime.tscn", "uid://d2ciakulevex6", 6], ["res://scenes/NPC/Beastmen/cat_robber.tscn", "uid://dl6nk8ypor2fd", 6]],
			"portals": [["left", "ruins", "Ruins_Thornroot_Portal_Spawn", "PortalToRuins", "Thornroot_Ruins_Portal_Spawn"], ["right", "dust_warren", "DustWarren_Thornroot_Portal_Spawn", "Portal1", "Thornroot_DustWarren_Portal_Spawn"]],
			"bosses": [{"scene": "res://scenes/NPC/thornroot_warchief.tscn", "name": "ThornrootWarchief", "props": {"respawnable": "true", "respawn_delay": "300"}}]},
		{"name": "dust_warren", "seed": 361, "amp": 3, "width": 130,
			"display_name": "The Dust Warren", "bgm": "res://assets/music/emberwilds_dust_warren.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/cat_robber.tscn", "uid://dl6nk8ypor2fd", 6], ["res://scenes/NPC/Minifolks/dust_fox.tscn", "uid://bleuqetjvkn5m", 7], ["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 6], ["res://scenes/NPC/Minifolks/mithril_hare.tscn", "uid://dvymxl60snfn8", 6]],
			"portals": [["left", "thornroot", "Thornroot_DustWarren_Portal_Spawn", "PortalToThornroot", "DustWarren_Thornroot_Portal_Spawn"], ["right", "mines", "Mines_DustWarren_Portal_Spawn", "Portal1", "DustWarren_Mines_Portal_Spawn"]]},
		{"name": "mines", "seed": 401, "amp": 3, "width": 150,
			"display_name": "The Drowned Mines", "bgm": "res://assets/music/emberwilds_mines.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/wolf_pathfinder.tscn", "uid://wjbryq6x0qx5", 8], ["res://scenes/NPC/war_goblin.tscn", "uid://cppmohti6r7s0", 6], ["res://scenes/NPC/Beastmen/rabbit_wizard.tscn", "uid://dppxdoxl4kf2k", 6], ["res://scenes/NPC/Beastmen/deer_druid.tscn", "uid://b7uy8wgb0j1t3", 6], ["res://scenes/NPC/Minifolks/mithril_hare.tscn", "uid://dvymxl60snfn8", 6]],
			"portals": [["left", "dust_warren", "DustWarren_Mines_Portal_Spawn", "PortalToDustWarren", "Mines_DustWarren_Portal_Spawn"], ["right", "emberwatch", "Emberwatch_Mines_Portal_Spawn", "PortalToEmberwatch", "Mines_Emberwatch_Portal_Spawn"]]},
		{"name": "keep", "seed": 571, "amp": 3, "width": 130,
			"display_name": "The Warded Keep", "bgm": "res://assets/music/emberwilds_keep.ogg",
			"monsters": [["res://scenes/NPC/Beastmen/bear_warrior.tscn", "uid://dreol0pnnwvme", 6], ["res://scenes/NPC/Beastmen/panda_warrior.tscn", "uid://dolpinlm1tsc0", 5], ["res://scenes/NPC/Minifolks/shadow_fox.tscn", "uid://c6qy8yi07kf2x", 6], ["res://scenes/NPC/Beastmen/lion_knight.tscn", "uid://dqirvq2t4dhx6", 6]],
			"portals": [["right", "emberscar", "Emberscar_Keep_Portal_Spawn", "PortalToEmberscar", "Keep_Emberscar_Portal_Spawn"], ["left", "deep_woods", "DeepWoods_Keep_Portal_Spawn", "PortalToDeepWoods", "Keep_DeepWoods_Portal_Spawn"]]},
		{"name": "emberscar", "seed": 681, "amp": 4, "width": 140,
			"display_name": "The Ember-Scar", "bgm": "res://assets/music/emberwilds_emberscar.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/runed_boar.tscn", "uid://tbl7yfcl3xwe", 7], ["res://scenes/NPC/fire_slime.tscn", "uid://bvjs3vxpdjkfj", 7], ["res://scenes/NPC/Minifolks/ember_fox.tscn", "uid://bichmn1gb8cd2", 7], ["res://scenes/NPC/Minifolks/wild_boar.tscn", "uid://oarco6h8le8s", 6]],
			"portals": [["left", "keep", "Keep_Emberscar_Portal_Spawn", "PortalToKeep", "Emberscar_Keep_Portal_Spawn"], ["right", "weave", "Weave_Emberscar_Portal_Spawn", "PortalToWeave", "Emberscar_Weave_Portal_Spawn"]]},
		{"name": "weave", "seed": 881, "amp": 3, "width": 110,
			"display_name": "The Weave's Edge", "bgm": "res://assets/music/emberwilds_weave.ogg",
			"monsters": [["res://scenes/NPC/Minifolks/celestial_hare.tscn", "uid://cywi7283fngxu", 9], ["res://scenes/NPC/astral_slime.tscn", "uid://5oi0b5vosx3q", 8]],
			"portals": [["left", "emberscar", "Emberscar_Weave_Portal_Spawn", "PortalToEmberscar", "Weave_Emberscar_Portal_Spawn"], ["right", "warlord", "Warlord_Weave_Portal_Spawn", "PortalToWarlord", "Weave_Warlord_Portal_Spawn"]]},
		{"name": "warlord", "seed": 1001, "amp": 0, "width": 80,
			"display_name": "The Sundered Heart", "bgm": "res://assets/music/emberwilds_boss.ogg",
			"monsters": [],
			"portals": [["left", "weave", "Weave_Warlord_Portal_Spawn", "PortalToWeave", "Warlord_Weave_Portal_Spawn"]],
			"bosses": [{"scene": "res://scenes/NPC/eternal_warlord.tscn", "uid": "uid://33dnjn4urvkp", "name": "EternalWarlord", "props": {"respawnable": "true", "respawn_delay": "300"}}]},
		{"name": "ruins", "seed": 131, "amp": 3, "width": 120,
			"display_name": "The Ruins", "bgm": "res://assets/music/emberwilds_ruins.ogg",
			"monsters": [["res://scenes/NPC/goblin_warrior.tscn", "uid://bj7nxg5um1rn6", 6], ["res://scenes/NPC/goblin.tscn", "uid://c0fdrl7mq5ou7", 6], ["res://scenes/NPC/cave_goblin.tscn", "uid://cnes7f1n2altk", 6], ["res://scenes/NPC/Minifolks/tusk_brute.tscn", "uid://b3drshokinfof", 5]],
			"portals": [["right", "ember_meadows", "EmberMeadows_Ruins_Portal_Spawn", "PortalToEmberMeadows", "Ruins_EmberMeadows_Portal_Spawn"], ["left", "thornroot", "Thornroot_Ruins_Portal_Spawn", "PortalToThornroot", "Ruins_Thornroot_Portal_Spawn"], ["mid", "three_terraces", "Hub_Terraces_Spawn", "PortalToTerraces", "Ruins_Terraces_Portal_Spawn"]]},
	]

## Fill `ground` (solid) + `slopes` with a gently rolling floor: broad flat runs at varied
## heights joined by 2:1 grass ramps, within +-amp tiles of base_r. Returns the per-column
## surface row. Shared by every field-type map (open field, near-wilds meadow, etc.).
func _rolling_floor(width: int, bottom: int, base_r: int, amp: int, seed_val: int, ground: Dictionary, slopes: Dictionary) -> Array:
	var surf := []
	surf.resize(width)
	for i in range(width): surf[i] = base_r
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var x := 0
	var cur := base_r
	while x < width:
		var run := rng.randi_range(8, 18)
		for _i in range(run):
			if x >= width: break
			surf[x] = cur; x += 1
		if x + 1 >= width: break
		var target := clampi(cur + rng.randi_range(-amp, amp), base_r - amp, base_r + amp)
		if target == cur:
			target = clampi(cur + (1 if rng.randf() < 0.5 else -1), base_r - amp, base_r + amp)
		var up := target < cur
		for _s in range(absi(cur - target)):
			if x + 1 >= width: break
			if up:
				var row := cur - 1
				slopes[Vector2i(x, row)] = SLOPE_UR_LOW
				slopes[Vector2i(x + 1, row)] = SLOPE_UR_HIGH
				surf[x] = row; surf[x + 1] = row
				cur = row
			else:
				slopes[Vector2i(x, cur)] = SLOPE_UL_HIGH
				slopes[Vector2i(x + 1, cur)] = SLOPE_UL_LOW
				surf[x] = cur; surf[x + 1] = cur
				cur += 1
			x += 2
	for col in range(width):
		for y in range(surf[col], bottom + 1): ground[Vector2i(col, y)] = true
	return surf

## The Near-Wilds (lv 1-9): the gentle grassy first step past the lantern-line. A wide
## rolling meadow, no climbs — just the warped woodland animals roaming the hills.
func _near_wilds() -> Dictionary:
	var width := 120
	var bottom := 36
	var base_r := FLOOR_Y
	var ground := {}
	var plat := {}
	var slopes := {}
	var surf := _rolling_floor(width, bottom, base_r, 2, 1090901, ground, slopes)
	# Two enemy-free SAFE platforms (heal / AFK) one near each portal; the Main player spawn
	# sits on the left one. Each is reached by a rope down to the meadow floor.
	var safe_row := base_r - 6
	# Safe platforms spread along the long meadow (one near each portal + two in the middle).
	_shelf(plat, surf, safe_row, [[7, 18], [40, 50], [72, 82], [101, 112]])
	var monsters := [
		["res://scenes/NPC/slime.tscn", "uid://q6iqwsi8meq4", 5],
		["res://scenes/NPC/Minifolks/bunny.tscn", "uid://c06qbiant345e", 5],
		["res://scenes/NPC/Minifolks/bird.tscn", "uid://p1gtmn7fct13", 3],
		["res://scenes/NPC/Minifolks/boar.tscn", "uid://betkg72vd7iav", 4],
		["res://scenes/NPC/Minifolks/deer.tscn", "uid://b31vj57j18ae2", 3],
		["res://scenes/NPC/Minifolks/fox.tscn", "uid://sxpgdsdpf5ma", 3],
	]
	# Transplanted from the real near_wilds.tscn: name, music, and the two portals (each with
	# its target map + target spawn-point name + this map's arrival marker). [edge, target_map,
	# target_spawn_point_name, portal_node_name, arrival_marker_name].
	var portals := [
		["left", "lanterns_rest", "LanternsRest_NearWilds_Portal_Spawn", "PortalToLanternsRest", "NearWilds_LanternsRest_Portal_Spawn"],
		["right", "ember_meadows", "EmberMeadows_NearWilds_Portal_Spawn", "PortalToEmberMeadows", "NearWilds_EmberMeadows_Portal_Spawn"],
	]
	# The slime-threat quest sign, re-created as an instance of the standard quest_giver scene
	# (uniform rebuild) with the original quest wiring transplanted. Sits on the left safe pad.
	var npcs := [{
		"scene": "res://scenes/NPC/quest_giver_npc.tscn", "uid": "uid://cqgvnpc7m3kxq",
		"name": "SlimeThreatSign", "col": 16, "row": safe_row,
		"props": {
			"npc_name": '"Slime Threat Sign"',
			"offered_quest_ids": 'PackedStringArray("q_slime_threat_1", "q_slime_threat_2", "q_slime_threat_3", "q_slime_threat_4")',
			"npc_greeting": '"── POSTED NOTICE ──\nSlime infestation reported in this region. Bounty offered for verified culls; see the list below for current targets. Report tallies to the village authority upon return."',
		},
	}]
	return {"name": "near_wilds", "real": true, "ground": ground, "plat": plat, "slopes": slopes, "monsters": monsters, "npcs": npcs,
		"display_name": "The Near-Wilds", "bgm": "res://assets/music/emberwilds_near_wilds.ogg",
		"portals": portals, "safe_rows": [safe_row], "player_spawn": Vector2i(12, safe_row - 1),
		"ladders": [
			[safe_row, int(surf[12]), 12, "rope"], [safe_row, int(surf[45]), 45, "rope"],
			[safe_row, int(surf[77]), 77, "rope"], [safe_row, int(surf[107]), 107, "rope"],
		],
		"width": width, "bottom": bottom}

func _open() -> Dictionary:
	# Henesys-style open field: a wide floor that ROLLS gently (2:1 grass ramps, +-2 tiles)
	# instead of a dead-flat line, with broad flat crests/dips to fight on + plant trees.
	# Long one-way shelves float above (unchanged). Seeded so it reads varied, not patterned.
	var width := 150
	var bottom := 40
	var ground := {}
	var plat := {}
	var slopes := {}
	var base_r := FLOOR_Y
	var surf := []
	surf.resize(width)
	for i in range(width): surf[i] = base_r
	var rng := RandomNumberGenerator.new()
	rng.seed = 6170617    # change this int for a different rolling profile
	var x := 0
	var cur := base_r
	while x < width:
		var run := rng.randi_range(8, 18)                 # broad flat stretch
		for _i in range(run):
			if x >= width: break
			surf[x] = cur; x += 1
		if x + 1 >= width: break
		var target := clampi(cur + rng.randi_range(-2, 2), base_r - 2, base_r + 2)
		if target == cur:                                 # never a flat "ramp"
			target = clampi(cur + (1 if rng.randf() < 0.5 else -1), base_r - 2, base_r + 2)
		var up := target < cur
		for _s in range(absi(cur - target)):
			if x + 1 >= width: break
			if up:
				var row := cur - 1
				slopes[Vector2i(x, row)] = SLOPE_UR_LOW
				slopes[Vector2i(x + 1, row)] = SLOPE_UR_HIGH
				surf[x] = row; surf[x + 1] = row
				cur = row
			else:
				slopes[Vector2i(x, cur)] = SLOPE_UL_HIGH
				slopes[Vector2i(x + 1, cur)] = SLOPE_UL_LOW
				surf[x] = cur; surf[x + 1] = cur
				cur += 1
			x += 2
	for col in range(width):
		for y in range(surf[col], bottom + 1): ground[Vector2i(col, y)] = true
	_shelf(plat, surf, base_r - 6, [[8, 68], [80, 142]])    # L1: row 20 (two segments)
	_shelf(plat, surf, base_r - 11, [[20, 96]])             # L2: row 15
	_shelf(plat, surf, base_r - 16, [[44, 118]])            # L3: row 10
	# Climbable ladders/ropes (these REPLACE the cloned ruins ones via _inject_ladders):
	# floor -> L1 shelves -> L2 -> L3. [upper_row, lower_row, col, type]. Floor climbers read
	# the rolling surf[col] so their bottom dangles ~1.5 tiles above the real floor.
	var ladders := [
		[base_r - 6, surf[14], 14, "ladder"],     # floor -> L1a (left)
		[base_r - 6, surf[60], 60, "rope"],        # floor -> L1a (right)
		[base_r - 6, surf[100], 100, "ladder"],    # floor -> L1b (left)
		[base_r - 6, surf[134], 134, "rope"],      # floor -> L1b (right)
		[base_r - 11, base_r - 6, 30, "rope"],     # L1a -> L2
		[base_r - 11, base_r - 6, 88, "ladder"],   # L1b -> L2
		[base_r - 16, base_r - 11, 54, "rope"],    # L2 -> L3 (left)
		[base_r - 16, base_r - 11, 92, "ladder"],  # L2 -> L3 (right)
	]
	return {"name": "open", "ground": ground, "plat": plat, "slopes": slopes, "ladders": ladders, "width": width, "bottom": bottom}

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
	# Solid raised mesas joined by GENTLE 2:1 grass ramps you walk straight up — no jumping
	# steps. WIDE flat tops to fight on. The ramps are slope tiles (source SLOPE_SRC) with a
	# trapezoid floor collision; everything below them is solid dirt. A one-way shelf sits
	# >=3 tiles above each mesa, reached by a rope/ladder that hangs from the shelf itself.
	var width := 64
	var bottom := 32
	var ground := {}
	var plat := {}
	var slopes := {}                         # slope surface cell -> atlas coord (source SLOPE_SRC)
	var base_r := FLOOR_Y                     # 26
	var surf := []
	surf.resize(width)
	for i in range(width): surf[i] = base_r
	# Plateau plan, left to right: flat runs at chosen heights joined by 2:1 ramps. A ramp
	# spends 2 columns per tile of rise/fall; the slope tiles sit on the HIGHER of the two
	# rows it bridges. ["flat", row, cols] / ["ramp", target_row].
	var plan := [
		["flat", base_r, 12],                # base
		["ramp", base_r - 4],                # up to mesa 1
		["flat", base_r - 4, 12],            # mesa 1 (surf 22)
		["ramp", base_r - 7],                # up to the peak
		["flat", base_r - 7, 10],            # peak (surf 19)
		["ramp", base_r - 4],                # down to mesa 3
		["flat", base_r - 4, 99],            # mesa 3 (fill to the right edge)
	]
	var x := 0
	var cur := base_r
	for step in plan:
		if x >= width: break
		if step[0] == "flat":
			cur = int(step[1])
			for _i in range(int(step[2])):
				if x >= width: break
				surf[x] = cur; x += 1
		else:
			var target := int(step[1])
			var up := target < cur
			for _s in range(absi(cur - target)):
				if x + 1 >= width: break
				if up:
					var row := cur - 1
					slopes[Vector2i(x, row)] = SLOPE_UR_LOW
					slopes[Vector2i(x + 1, row)] = SLOPE_UR_HIGH
					surf[x] = row; surf[x + 1] = row
					cur = row
				else:
					slopes[Vector2i(x, cur)] = SLOPE_UL_HIGH
					slopes[Vector2i(x + 1, cur)] = SLOPE_UL_LOW
					surf[x] = cur; surf[x + 1] = cur
					cur += 1
				x += 2
	# Fill solid dirt from each column's surface row down to the bottom.
	for col in range(width):
		for y in range(surf[col], bottom + 1): ground[Vector2i(col, y)] = true
	# One-way shelves over each flat mesa (each >=3 tiles clear) — safe vantage spots you
	# reach by jumping to a rope/ladder that hangs from the shelf and climbing up.
	_shelf(plat, surf, base_r - 12, [[24, 31]])   # over mesa 1 (surf 22)
	_shelf(plat, surf, base_r - 15, [[40, 47]])   # over the peak (surf 19)
	_shelf(plat, surf, base_r - 10, [[55, 63]])   # over mesa 3 (surf 22)
	return {"name": "cliffs", "ground": ground, "plat": plat, "slopes": slopes, "width": width, "bottom": bottom}

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
	var slopes: Dictionary = m.get("slopes", {})
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
	# Cave maps: force the whole ceiling band to dark rock (no grass-top / trees up there).
	if m.has("ceiling_below"):
		var cb := int(m["ceiling_below"])
		for cell in ground:
			if cell.y < cb: black[cell] = true

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
	if not m.get("no_deco", false):
		for cell in picks:
			if slopes.has(cell): continue
			if picks[cell][1] == 5: _try_tuft(deco, cell, ground, plat, rng)
		for cell in plat:
			_try_tuft(deco, cell, ground, plat, rng)

	# Trees: only on ground that is LEVEL across the whole trunk+canopy width.
	var surf_top := {}
	for cell in picks:
		if slopes.has(cell): continue
		if picks[cell][1] == 5 and (not surf_top.has(cell.x) or cell.y < surf_top[cell.x]):
			surf_top[cell.x] = cell.y
	var tx := 6
	var trees_on: bool = not bool(m.get("no_trees", false))
	while trees_on and tx < int(m["width"]) - 6:
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
	# Cave/rock maps: swap the grass-top surface (17-19,5) for the rock-top tiles (slope source
	# cols 4-6) so the floor is bare rock, not green moss.
	var rocktop := {}
	if m.get("rock_top", false):
		for cell in picks:
			if picks[cell][1] == 5 and picks[cell][0] >= 17 and picks[cell][0] <= 19:
				rocktop[cell] = [picks[cell][0] - 13, 0]
	text = _replace_layer(text, "Mid", _mid_b64(picks, slopes, rocktop, m.get("bridge", {}), m.get("water", {})))
	text = _replace_layer(text, "Platform", _plat_b64(plat))
	var columns: Dictionary = m.get("columns", {})
	if not columns.is_empty():                                     # decorative stone columns (behind everything)
		text = _replace_layer(text, "Background", _layer_b64(columns, COLUMN_SRC))
	else:
		text = _replace_layer(text, "Background", _layer_b64(deco, 2))
	var bgwall: Dictionary = m.get("bgwall", {})
	var water_body: Dictionary = m.get("water_body", {})
	if not water_body.is_empty():                                  # scenic deep water behind the path
		text = _replace_layer(text, "Background2", _layer_b64(water_body, WATER_SRC))
	else:
		text = _replace_layer(text, "Background2", _layer_b64(bgwall, 1) if not bgwall.is_empty() else "")
	text = text.replace('display_name = "The Ruins"', 'display_name = "%s"' % m.get("display_name", "Gen " + str(m["name"])))
	if m.has("bgm"): text = text.replace('bgm_path = "res://assets/music/emberwilds_ruins.ogg"', 'bgm_path = "%s"' % m["bgm"])
	text = _strip_clone_clutter(text)
	if m.get("no_village_bg", false): text = _remove_node(text, "VillageBackground")
	text = _inject_playable(text, m)
	if not slopes.is_empty(): text = _inject_slopes(text)
	if not m.get("bridge", {}).is_empty(): text = _inject_bridge(text)
	if not m.get("water", {}).is_empty() or not m.get("water_body", {}).is_empty(): text = _inject_water(text)
	if not m.get("columns", {}).is_empty(): text = _inject_columns(text)
	if not m.get("portals", []).is_empty(): text = _inject_portals(text, m)
	if not m.get("npcs", []).is_empty(): text = _inject_npcs(text, m)
	if not m.get("bosses", []).is_empty(): text = _inject_bosses(text, m)
	# Always run ladder injection: it grabs the atlas from the cloned Ladders/Ropes, CLEARS the
	# stale cloned ones, then adds this map's set (or none). Clearing inside _inject_ladders
	# (not in _strip_clone_clutter) keeps the atlas reference alive for the lookup.
	var lad_specs: Array = m.get("ladders", [])
	if m["name"] == "tower": lad_specs = TOWER_LADDERS
	elif m["name"] == "cliffs": lad_specs = CLIFFS_LADDERS
	text = _inject_ladders(text, lad_specs)
	# Real maps (m.real) overwrite the live scene; otherwise write a gen_<name> proof.
	var out_name := str(m["name"]) if m.get("real", false) else ("gen_" + str(m["name"]))
	var w := FileAccess.open("res://scenes/Levels/%s.tscn" % out_name, FileAccess.WRITE)
	w.store_string(text); w.close()

	# Preview PNG (ground+platform from the tileset, decorations from the props sheet).
	var sheet := Image.new(); sheet.load(SHEET); sheet.convert(Image.FORMAT_RGBA8)
	var props := Image.new(); props.load(SHEET2); props.convert(Image.FORMAT_RGBA8)
	var slope_img := Image.new(); slope_img.load("res://assets/sprites/grass_slopes.png"); slope_img.convert(Image.FORMAT_RGBA8)
	var img := Image.create(int(m["width"]) * 16, (int(m["bottom"]) + 2) * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.16, 0.22, 1.0))
	for cell in bgwall:                                   # dark void / cave backdrop behind everything
		var bt = bgwall[cell]
		img.blend_rect(sheet, Rect2i(bt[0] * 16, bt[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in deco:
		var t = deco[cell]
		img.blend_rect(props, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in picks:
		if slopes.has(cell): continue
		if rocktop.has(cell):                             # bare rock surface (rock_top maps)
			img.blend_rect(slope_img, Rect2i(rocktop[cell][0] * 16, rocktop[cell][1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
			continue
		var t = picks[cell]
		img.blend_rect(sheet, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in slopes:
		var s: Vector2i = slopes[cell]
		img.blend_rect(slope_img, Rect2i(s.x * 16, s.y * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
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
	# The clone (ruins) is ITSELF generated, so it carries gen_mob/gen_spw/gen_msp ext_resource ids
	# that COLLIDE with the ones we add below — Godot then resolves the spawner to the wrong scene
	# (cinderwaste spawned goblins). Drop the clone's copies before re-adding ours.
	var clone_ext := RegEx.new(); clone_ext.compile('\\n\\[ext_resource[^\\n]*id="gen_(mob\\d+|spw|msp)"\\]')
	text = clone_ext.sub(text, "", true)
	# Monster roster: [[scene_path, uid, pool], ...]. Default = one slime (open/cliffs/tower).
	var roster: Array = m.get("monsters", [["res://scenes/NPC/slime.tscn", "uid://q6iqwsi8meq4", 0]])
	# ext_resources: the two spawner scripts + one PackedScene per enemy; bump load_steps.
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 2 + roster.size()))
	var ext := '\n[ext_resource type="Script" path="res://scripts/Enemy/enemy_spawner.gd" id="gen_spw"]'
	ext += '\n[ext_resource type="Script" path="res://scripts/Gameplay/enemy_multiplayer_spawner.gd" id="gen_msp"]'
	for i in roster.size():
		ext += '\n[ext_resource type="PackedScene" uid="%s" path="%s" id="gen_mob%d"]' % [roster[i][1], roster[i][0], i]
	text = header + ext + text.substr(nl)

	# Spawn spots: sample the base ground floor AND every wide platform floor, so enemies
	# populate the whole map (a tower's upper floors, not just the base). Markers live in
	# root space; the cloned TileMap sits at (-119,-269), so tile (col,row) -> world
	# (col*16-119, row*16-269); centre x (+8) and sit 1 tile above the surface.
	var surf := {}
	for cell in m["ground"]:
		if not surf.has(cell.x) or cell.y < surf[cell.x]: surf[cell.x] = cell.y
	var w := int(m["width"])
	var spots := []
	# Keep enemies from SPAWNING right next to a portal (they can still walk there).
	var lbuf := 0; var rbuf := 0
	for sp in m.get("portals", []):
		if sp[0] == "left": lbuf = PORTAL_SPAWN_BUFFER
		elif sp[0] == "right": rbuf = PORTAL_SPAWN_BUFFER
	if m["name"] == "cliffs":
		# Cliffs: a slime on every FLAT stretch of ground (each mesa top + base), never on a
		# staircase step, and NOT on the one-way shelves (those stay safe vantage spots).
		for col in range(3, w - 3, 3):
			if col < lbuf or col > w - 1 - rbuf: continue
			if surf.has(col) and surf[col] == surf.get(col - 1, -1) and surf[col] == surf.get(col + 1, -1):
				spots.append(Vector2i(col, surf[col]))
	else:
		# Tower/open: a spawn on each flat stretch of the floor (handles rolling hills) +
		# every wide one-way platform floor.
		for col in range(4, w - 4, 4):
			if col < lbuf or col > w - 1 - rbuf: continue
			if surf.has(col) and surf[col] == surf.get(col - 1, -999) and surf[col] == surf.get(col + 1, -999):
				spots.append(Vector2i(col, surf[col]))
		var rows := {}                                        # platform floors grouped by row
		for cell in m["plat"]:
			if not rows.has(cell.y): rows[cell.y] = []
			rows[cell.y].append(cell.x)
		for r in rows:
			var xs = rows[r]; xs.sort()
			if xs.size() < 5: continue                        # skip tiny stepping stones
			if m.get("safe_rows", []).has(r): continue        # safe platforms stay enemy-free
			var c: int = xs[0] + 2
			while c <= xs[xs.size() - 1] - 1:
				spots.append(Vector2i(c, r)); c += 7
	# Builders that place enemies precisely (cave ledges, etc.) override the sampled spots.
	if m.has("spawn_spots"):
		spots = []
		for s in m["spawn_spots"]: spots.append(s)
	# One spawner per enemy, each getting a round-robin share of the spots (so every type is
	# spread across the whole map) plus its own pool_size from the roster.
	var blk := ""
	for i in roster.size():
		var sp_name := "Spawn_%s" % str(roster[i][0]).get_file().get_basename()
		var my := []
		for j in range(spots.size()):
			if j % roster.size() == i: my.append(spots[j])
		if my.is_empty() and not spots.is_empty(): my.append(spots[i % spots.size()])
		var pool: int = int(roster[i][2]) if int(roster[i][2]) > 0 else maxi(my.size(), 1)
		var markers := ""; var locs := []
		for k in my.size():
			var s = my[k]
			markers += '\n\n[node name="M%d" type="Marker2D" parent="%s"]\nposition = Vector2(%d, %d)' % [k, sp_name, s.x * 16 - 111, (s.y - 1) * 16 - 269]
			locs.append('NodePath("M%d")' % k)
		blk += '\n\n[node name="%s" type="Node2D" parent="." node_paths=PackedStringArray("spawn_locations", "spawn_container")]' % sp_name
		blk += '\nscript = ExtResource("gen_spw")\nenemy_scene = ExtResource("gen_mob%d")' % i
		blk += '\nspawn_locations = [%s]\nspawn_container = NodePath("../Enemies")\npool_size = %d' % [", ".join(locs), pool]
		blk += markers
		blk += '\n\n[node name="MultiplayerSpawner" type="MultiplayerSpawner" parent="%s" node_paths=PackedStringArray("enemy_spawner")]' % sp_name
		blk += '\n_spawnable_scenes = PackedStringArray("%s")\nspawn_path = NodePath("../../Enemies")' % roster[i][1]
		blk += '\nscript = ExtResource("gen_msp")\nenemy_spawner = NodePath("..")'
	text += blk

	# Reposition PlayerSpawn onto the floor (left side), same (-119,-269) clone offset.
	var ps := text.find('[node name="PlayerSpawn"')
	if ps != -1:
		var sp_col := 5
		var sp_row: int = int(surf.get(sp_col, FLOOR_Y)) - 2   # read the rolling surface, don't bury/float
		if m.has("player_spawn"):                              # explicit spawn on a safe platform
			sp_col = int(m["player_spawn"].x); sp_row = int(m["player_spawn"].y)
		var spawn_pos := 'position = Vector2(%d, %d)' % [sp_col * 16 - 119, sp_row * 16 - 269]
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

## Mid (solid ground) layer with two sources: autotiled country-village ground (source 1)
## plus explicit slope ramp tiles (source SLOPE_SRC). Slope cells are dropped from the
## autotiled set so the ramp tile isn't overwritten by a flat grass-top.
func _mid_b64(picks: Dictionary, slopes: Dictionary, rocktop: Dictionary = {}, bridge: Dictionary = {}, water: Dictionary = {}) -> String:
	var l := TileMapLayer.new()
	for cell in picks:
		if slopes.has(cell) or rocktop.has(cell): continue
		l.set_cell(cell, 1, Vector2i(picks[cell][0], picks[cell][1]))
	for cell in slopes:
		l.set_cell(cell, SLOPE_SRC, slopes[cell])
	for cell in rocktop:                              # rock-top surface tiles (source SLOPE_SRC)
		l.set_cell(cell, SLOPE_SRC, Vector2i(rocktop[cell][0], rocktop[cell][1]))
	for cell in bridge:                               # solid wooden bridge planks (source BRIDGE_SRC)
		l.set_cell(cell, BRIDGE_SRC, Vector2i(bridge[cell][0], bridge[cell][1]))
	for cell in water:                                # walkable shallow water surface (source WATER_SRC)
		l.set_cell(cell, WATER_SRC, Vector2i(water[cell][0], water[cell][1]))
	var b := Marshalls.raw_to_base64(l.tile_map_data); l.free(); return b

func _plat_b64(plat: Dictionary) -> String:
	var l := TileMapLayer.new()
	for cell in plat:
		var t = PLAT[plat[cell]]
		l.set_cell(cell, 1, Vector2i(t[0], t[1]))
	var b := Marshalls.raw_to_base64(l.tile_map_data); l.free(); return b

## Inject the slope-tile atlas (grass_slopes.png) into the cloned scene's TileSet as
## sources/SLOPE_SRC, with the four 2:1 half-slope tiles and their trapezoid FLOOR collision
## (physics_layer_0, same layer as the solid ground), so the Mid layer's source-SLOPE_SRC
## cells become walkable ramps. Polygons are in centred tile coords (-8..8), matching how
## the country-village tiles declare collision.
func _inject_slopes(text: String) -> String:
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 2))   # +1 ext, +1 sub
	text = header + '\n[ext_resource type="Texture2D" path="res://assets/sprites/grass_slopes.png" id="gen_slopes"]' + text.substr(nl)
	var polys := [
		"PackedVector2Array(-8, 8, 8, 0, 8, 8)",            # 0 ur_low  (up-right, low half)
		"PackedVector2Array(-8, 0, 8, -8, 8, 8, -8, 8)",    # 1 ur_high (up-right, high half)
		"PackedVector2Array(-8, -8, 8, 0, 8, 8, -8, 8)",    # 2 ul_high (down-right, high half)
		"PackedVector2Array(-8, 0, 8, 8, -8, 8)",           # 3 ul_low  (down-right, low half)
	]
	var atlas := '[sub_resource type="TileSetAtlasSource" id="GenSlopeAtlas"]\ntexture = ExtResource("gen_slopes")\ntexture_region_size = Vector2i(16, 16)\n'
	for i in range(polys.size()):
		atlas += '%d:0/0 = 0\n%d:0/0/physics_layer_0/polygon_0/points = %s\n' % [i, i, polys[i]]
	for i in range(4, 7):                                # rock-top tiles: solid full-square floor
		atlas += '%d:0/0 = 0\n%d:0/0/physics_layer_0/polygon_0/points = PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)\n' % [i, i]
	atlas += "\n"
	# Define the atlas BEFORE the TileSet sub_resource that references it — the .tscn parser
	# resolves SubResource() refs in file order. (Match the space+id so we don't hit the
	# "TileSetAtlasSource" sub_resources, whose type string starts with "TileSet" too.)
	var ti := text.find('[sub_resource type="TileSet" id=')
	if ti != -1:
		text = text.substr(0, ti) + atlas + text.substr(ti)
	var sidx := text.find("sources/2 = SubResource(")
	if sidx != -1:
		var seol := text.find("\n", sidx)
		text = text.substr(0, seol) + '\nsources/%d = SubResource("GenSlopeAtlas")' % SLOPE_SRC + text.substr(seol)
	return text

## Re-add a map's portals (rebuild-uniform transplant): a portal instance + an arrival
## Marker2D per neighbour, planted on the new terrain's edge ground. Reuses the cloned
## portal.tscn ext_resource (no load_steps change). Specs: [edge, target_map,
## target_spawn_point_name, portal_node_name, arrival_marker_name].
func _inject_portals(text: String, m: Dictionary) -> String:
	var specs: Array = m.get("portals", [])
	var pid := _find_ext_id(text, "res://scenes/Gameplay/portal.tscn")
	if pid == "":
		print("  portal wiring skipped (portal.tscn ext not found)"); return text
	var surf := {}
	for cell in m["ground"]:
		if not surf.has(cell.x) or cell.y < surf[cell.x]: surf[cell.x] = cell.y
	var w := int(m["width"])
	var blk := ""
	for sp in specs:
		var edge: String = sp[0]
		var col: int = (4 if edge == "left" else (w - 5 if edge == "right" else int(w / 2.0)))
		while not surf.has(col) and col > 0 and col < w - 1: col += (-1 if edge == "right" else 1)
		var srow: int = int(surf.get(col, FLOOR_Y))
		var px: int = col * 16 - 119
		var pg: int = srow * 16 - 269                      # ground surface at the portal column
		blk += '\n[node name="%s" parent="." instance=ExtResource("%s")]' % [sp[3], pid]
		# Portal raised 16px so its collision box sits ON the ground, not buried in it.
		blk += '\nposition = Vector2(%d, %d)\ntarget_map_id = "%s"\ntarget_spawn_point_name = "%s"\n' % [px, pg - 16, sp[1], sp[2]]
		var mx: int = px - 24 if edge == "right" else px + 24
		# Arrival marker raised 12px so the player drops in just above the ground.
		blk += '\n[node name="%s" type="Marker2D" parent="."]\nposition = Vector2(%d, %d)\n' % [sp[4], mx, pg - 12]
	return text + blk

## Re-create a map's NPCs as instances of their scene (uniform rebuild) with the original
## exported properties transplanted. Specs: {scene, uid, name, col, row, props:{key:value}}.
func _inject_npcs(text: String, m: Dictionary) -> String:
	var npcs: Array = m.get("npcs", [])
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + npcs.size()))
	var ext := ""
	for i in npcs.size():
		ext += '\n[ext_resource type="PackedScene" uid="%s" path="%s" id="gen_npc%d"]' % [npcs[i]["uid"], npcs[i]["scene"], i]
	text = header + ext + text.substr(nl)
	var blk := ""
	for i in npcs.size():
		var npc = npcs[i]
		blk += '\n[node name="%s" parent="." instance=ExtResource("gen_npc%d")]' % [npc["name"], i]
		blk += '\nposition = Vector2(%d, %d)' % [int(npc["col"]) * 16 - 119, int(npc["row"]) * 16 - 269]
		for k in npc["props"]:
			blk += '\n%s = %s' % [k, npc["props"][k]]
		blk += '\n'
	return text + blk

## Re-add hard-placed bosses as instances under the Enemies node (respawn on their own timer,
## not the spawn-tick). Specs: {scene, uid?, name, col?, props:{respawnable, respawn_delay}}.
func _inject_bosses(text: String, m: Dictionary) -> String:
	var bosses: Array = m.get("bosses", [])
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + bosses.size()))
	var ext := ""
	for i in bosses.size():
		var u := str(bosses[i].get("uid", ""))
		if u != "":
			ext += '\n[ext_resource type="PackedScene" uid="%s" path="%s" id="gen_boss%d"]' % [u, bosses[i]["scene"], i]
		else:
			ext += '\n[ext_resource type="PackedScene" path="%s" id="gen_boss%d"]' % [bosses[i]["scene"], i]
	text = header + ext + text.substr(nl)
	var surf := {}
	for cell in m["ground"]:
		if not surf.has(cell.x) or cell.y < surf[cell.x]: surf[cell.x] = cell.y
	var w := int(m["width"])
	var blk := ""
	for i in bosses.size():
		var b = bosses[i]
		var col: int = int(b.get("col", int(w / 2.0)))
		var srow: int = int(surf.get(col, FLOOR_Y))
		blk += '\n[node name="%s" parent="Enemies" instance=ExtResource("gen_boss%d")]' % [b["name"], i]
		blk += '\nposition = Vector2(%d, %d)' % [col * 16 - 119, srow * 16 - 269 - 8]
		for k in b.get("props", {}):
			blk += '\n%s = %s' % [k, b["props"][k]]
		blk += '\n'
	return text + blk

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
## Inject bridge_tiles.png as sources/BRIDGE_SRC (3 solid plank tiles, full-square floor
## collision on physics_layer_0). Mirrors _inject_slopes. The clone already carries sources 0-3.
func _inject_bridge(text: String) -> String:
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 2))   # +1 ext, +1 sub
	text = header + '\n[ext_resource type="Texture2D" path="res://assets/sprites/bridge_tiles.png" id="gen_bridge"]' + text.substr(nl)
	var atlas := '[sub_resource type="TileSetAtlasSource" id="GenBridgeAtlas"]\ntexture = ExtResource("gen_bridge")\ntexture_region_size = Vector2i(16, 16)\n'
	for i in range(3):
		atlas += '%d:0/0 = 0\n%d:0/0/physics_layer_0/polygon_0/points = PackedVector2Array(-8, -8, 8, -8, 8, 8, -8, 8)\n' % [i, i]
	atlas += "\n"
	var ti := text.find('[sub_resource type="TileSet" id=')
	if ti != -1:
		text = text.substr(0, ti) + atlas + text.substr(ti)
	var sidx := text.find("sources/3 = SubResource(")
	if sidx == -1: sidx = text.find("sources/2 = SubResource(")
	if sidx != -1:
		var seol := text.find("\n", sidx)
		text = text.substr(0, seol) + '\nsources/%d = SubResource("GenBridgeAtlas")' % BRIDGE_SRC + text.substr(seol)
	return text


## Inject water_tiles.png as sources/WATER_SRC. Tile 0 (surface) gets solid floor collision so it's
## walkable shallows; tiles 1 (body) / 2 (overlay) are decorative (no collision). Mirrors _inject_bridge.
func _inject_water(text: String) -> String:
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 2))
	text = header + '\n[ext_resource type="Texture2D" path="res://assets/sprites/water_tiles.png" id="gen_water"]' + text.substr(nl)
	# Sheet is 4 cols (anim frames) x 3 rows: surface (0,0), body (0,1), overlay (0,2). Each is an
	# ANIMATED tile (4 frames, scrolls horizontally) with NO collision — water is background scenery.
	var atlas := '[sub_resource type="TileSetAtlasSource" id="GenWaterAtlas"]\ntexture = ExtResource("gen_water")\ntexture_region_size = Vector2i(16, 16)\n'
	for ty in range(3):
		atlas += '0:%d/animation_columns = 4\n0:%d/animation_speed = 3.0\n' % [ty, ty]
		for f in range(4): atlas += '0:%d/animation_frame_%d/duration = 1.0\n' % [ty, f]
		atlas += '0:%d/0 = 0\n' % ty
	atlas += "\n"
	var ti := text.find('[sub_resource type="TileSet" id=')
	if ti != -1:
		text = text.substr(0, ti) + atlas + text.substr(ti)
	var sidx := text.find("sources/3 = SubResource(")
	if sidx == -1: sidx = text.find("sources/2 = SubResource(")
	if sidx != -1:
		var seol := text.find("\n", sidx)
		text = text.substr(0, seol) + '\nsources/%d = SubResource("GenWaterAtlas")' % WATER_SRC + text.substr(seol)
	return text


## Inject stone_columns.png as sources/COLUMN_SRC — 4 decorative tiles (capital/shaft/base/broken),
## NO collision (columns are background scenery you walk past). Mirrors _inject_bridge.
func _inject_columns(text: String) -> String:
	var nl := text.find("\n")
	var header := text.substr(0, nl)
	var lm := RegEx.new(); lm.compile("load_steps=(\\d+)")
	var n := int(lm.search(header).get_string(1))
	header = header.replace("load_steps=%d" % n, "load_steps=%d" % (n + 2))
	text = header + '\n[ext_resource type="Texture2D" path="res://assets/sprites/stone_columns.png" id="gen_columns"]' + text.substr(nl)
	var atlas := '[sub_resource type="TileSetAtlasSource" id="GenColumnAtlas"]\ntexture = ExtResource("gen_columns")\ntexture_region_size = Vector2i(16, 16)\n'
	for cr in range(4):                                   # 3 cols (L/M/R) x 4 rows (cap/shaft/base/broken)
		for cc in range(3): atlas += '%d:%d/0 = 0\n' % [cc, cr]
	atlas += "\n"
	var ti := text.find('[sub_resource type="TileSet" id=')
	if ti != -1:
		text = text.substr(0, ti) + atlas + text.substr(ti)
	var sidx := text.find("sources/3 = SubResource(")
	if sidx == -1: sidx = text.find("sources/2 = SubResource(")
	if sidx != -1:
		var seol := text.find("\n", sidx)
		text = text.substr(0, seol) + '\nsources/%d = SubResource("GenColumnAtlas")' % COLUMN_SRC + text.substr(seol)
	return text


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
## Remove a single node block (the node line + its properties, up to the next section).
func _remove_node(text: String, node_name: String) -> String:
	var i := text.find('[node name="%s"' % node_name)
	if i == -1: return text
	var start := text.rfind("\n", i)
	if start == -1: start = i
	var e := text.find("\n[", i + 1)
	if e == -1: e = text.length()
	return text.substr(0, start) + text.substr(e)

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
