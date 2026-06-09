extends SceneTree

# Headless dumper for the World Map's static data catalog.
#
# Scans every level scene off-tree (no _ready side effects), reads its portal
# connections and the enemies it spawns (EnemySpawner.enemy_scene + any directly
# placed EnemyBase, e.g. a boss), pulls each enemy's level + drop table from its
# EnemyData, and writes resources/.. config/world_map_data.json. The world map UI
# loads this at runtime for its hover tooltips (avg level, enemies+levels, drops%).
#
# This is the single source for the world map's content data; the connection
# graph is derived from the SAME portals the live game uses, so it can't drift
# from the actual map wiring. Re-run after changing maps/enemies/drops:
#   "C:\Program Files\Godot\Godot.exe" --headless --path . \
#       --script res://tools/dump_world_map.gd --log-file tools/dump.log

const OUT := "res://config/world_map_data.json"
const SKIP := ["main_menu", "map_template", "village_background", "village_background_dark"]

## item name -> {icon: <texture res path>, level: int}; built from resources/Items.
var _item_index: Dictionary = {}


func _initialize() -> void:
	_item_index = _build_item_index()
	var maps := {}
	var dir := DirAccess.open("res://scenes/Levels")
	if dir == null:
		push_error("cannot open scenes/Levels"); quit(); return
	var files := dir.get_files()
	files.sort()
	for f in files:
		if not f.ends_with(".tscn"):
			continue
		var mid := f.get_basename()
		if mid in SKIP:
			continue
		var ps = load("res://scenes/Levels/%s" % f)
		if ps == null:
			push_warning("skip (load failed): %s" % f); continue
		var inst = ps.instantiate()

		var connections := []
		for p in inst.find_children("*", "Portal", true, false):
			var tm = p.get("target_map_id")
			if tm != null and tm != "" and not (tm in connections):
				connections.append(tm)

		var enemies := []
		var seen := {}
		# Pooled enemies: each EnemySpawner names the scene it will spawn.
		for sp in inst.find_children("*", "EnemySpawner", true, false):
			var escn = sp.get("enemy_scene")
			if escn == null:
				continue
			_add_enemy_from_scene(escn, enemies, seen)
		# Directly placed enemies (bosses are authored as live EnemyBase nodes).
		for eb in inst.find_children("*", "EnemyBase", true, false):
			_add_enemy_from_data(eb.get("enemy_data"), enemies, seen)

		var levels := []
		for e in enemies:
			levels.append(e["level"])
		levels.sort()
		var avg := 0
		if not levels.is_empty():
			var total := 0
			for lv in levels:
				total += lv
			avg = int(round(float(total) / levels.size()))

		var dname = inst.get("display_name")
		maps[mid] = {
			"display_name": dname if (dname != null and dname != "") else mid,
			"avg_level": avg,
			"min_level": (levels[0] if not levels.is_empty() else 0),
			"max_level": (levels[-1] if not levels.is_empty() else 0),
			"is_town": enemies.is_empty(),
			"connections": connections,
			"enemies": enemies,
		}
		inst.free()

	var payload := {
		"generated_note": "Auto-dumped via tools/dump_world_map.gd. Re-run after map/enemy/drop changes.",
		"maps": maps,
	}
	var fa := FileAccess.open(OUT, FileAccess.WRITE)
	fa.store_string(JSON.stringify(payload, "\t"))
	fa.close()
	print("wrote %s : %d maps (%d items indexed)" % [OUT, maps.size(), _item_index.size()])
	quit()


## Scan resources/Items recursively, mapping each ItemData's name -> icon + level
## so drop entries can carry an icon thumbnail and the item's level.
func _build_item_index() -> Dictionary:
	var idx := {}
	_scan_items("res://resources/Items", idx)
	return idx


func _scan_items(path: String, idx: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := "%s/%s" % [path, name]
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_items(full, idx)
		elif name.ends_with(".tres"):
			var res = load(full)
			if res is ItemData and res.name != "":
				idx[res.name] = {
					"icon": (res.icon.resource_path if res.icon != null else ""),
					"level": res.item_level,
				}
		name = dir.get_next()
	dir.list_dir_end()


func _add_enemy_from_scene(escn: PackedScene, out: Array, seen: Dictionary) -> void:
	var einst = escn.instantiate()
	_add_enemy_from_data(einst.get("enemy_data"), out, seen)
	einst.free()


func _add_enemy_from_data(ed, out: Array, seen: Dictionary) -> void:
	if ed == null:
		return
	var name_key: String = ed.monster_name
	if name_key == "" or seen.has(name_key):
		return
	seen[name_key] = true
	var drops := []
	for d in ed.item_drops:
		var meta: Dictionary = _item_index.get(d.item_name, {})
		drops.append({
			"item": d.item_name,
			"chance": d.drop_chance,
			"min": d.min_amount,
			"max": d.max_amount,
			"ilvl": meta.get("level", 0),
			"icon": meta.get("icon", ""),
		})
	out.append({
		"name": ed.monster_name,
		"level": ed.monster_level,
		"is_boss": ed.is_boss,
		"sf": (ed.sprite_frames.resource_path if ed.sprite_frames != null else ""),
		"drops": drops,
	})
