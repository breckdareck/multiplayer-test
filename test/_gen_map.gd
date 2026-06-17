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
	# CREATIVE PASS proof: rebuild mines as a real cave to confirm the per-map terrain direction.
	for cfg in _wave_rest():
		if cfg["name"] != "mines": continue
		_emit(_build_cave(cfg))
		print("WROTE cave ", cfg["name"])
	quit()

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
	var d := {
		"bgwall": bgwall, "rock_top": true,
		"name": cfg["name"], "real": true, "ground": ground, "plat": plat, "slopes": slopes,
		"monsters": cfg.get("monsters", []), "portals": cfg.get("portals", []),
		"safe_rows": [], "ladders": ladders, "player_spawn": Vector2i(11, base_r - 9),
		"display_name": cfg["display_name"], "bgm": cfg["bgm"], "width": width, "bottom": bottom,
		"ceiling_below": base_r - 16, "no_trees": true, "no_village_bg": true,
	}
	if cfg.has("npcs"): d["npcs"] = cfg["npcs"]
	if cfg.has("bosses"): d["bosses"] = cfg["bosses"]
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
	text = _replace_layer(text, "Mid", _mid_b64(picks, slopes, rocktop))
	text = _replace_layer(text, "Platform", _plat_b64(plat))
	text = _replace_layer(text, "Background", _layer_b64(deco, 2))
	var bgwall: Dictionary = m.get("bgwall", {})
	text = _replace_layer(text, "Background2", _layer_b64(bgwall, 1) if not bgwall.is_empty() else "")
	text = text.replace('display_name = "The Ruins"', 'display_name = "%s"' % m.get("display_name", "Gen " + str(m["name"])))
	if m.has("bgm"): text = text.replace('bgm_path = "res://assets/music/emberwilds_ruins.ogg"', 'bgm_path = "%s"' % m["bgm"])
	text = _strip_clone_clutter(text)
	if m.get("no_village_bg", false): text = _remove_node(text, "VillageBackground")
	text = _inject_playable(text, m)
	if not slopes.is_empty(): text = _inject_slopes(text)
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
	var img := Image.create(int(m["width"]) * 16, (int(m["bottom"]) + 2) * 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.13, 0.16, 0.22, 1.0))
	for cell in deco:
		var t = deco[cell]
		img.blend_rect(props, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	for cell in picks:
		if slopes.has(cell): continue
		var t = picks[cell]
		img.blend_rect(sheet, Rect2i(t[0] * 16, t[1] * 16, 16, 16), Vector2i(cell.x * 16, cell.y * 16))
	if not slopes.is_empty():
		var slope_img := Image.new(); slope_img.load("res://assets/sprites/grass_slopes.png"); slope_img.convert(Image.FORMAT_RGBA8)
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
func _mid_b64(picks: Dictionary, slopes: Dictionary, rocktop: Dictionary = {}) -> String:
	var l := TileMapLayer.new()
	for cell in picks:
		if slopes.has(cell) or rocktop.has(cell): continue
		l.set_cell(cell, 1, Vector2i(picks[cell][0], picks[cell][1]))
	for cell in slopes:
		l.set_cell(cell, SLOPE_SRC, slopes[cell])
	for cell in rocktop:                              # rock-top surface tiles (source SLOPE_SRC)
		l.set_cell(cell, SLOPE_SRC, Vector2i(rocktop[cell][0], rocktop[cell][1]))
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
