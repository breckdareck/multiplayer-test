extends SceneTree
# Headless smoke test for a generated map. Loads + instantiates the scene with
# autoloads live (first-frame), adds it to the tree so MapBase._ready() runs,
# and asserts the structural invariants the add-map skill requires.
#
#   Godot.exe --headless --path . --script res://tools/verify_map.gd -- <map_id>

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return true
	_ran = true
	var ids := OS.get_cmdline_user_args()
	var fails := 0
	for map_id in ids:
		fails += _verify(map_id)
	quit(1 if fails > 0 else 0)
	return true


func _verify(map_id: String) -> int:
	var path := "res://scenes/Levels/%s.tscn" % map_id
	var fails := 0
	print("\n== verify %s ==" % map_id)

	var ps: PackedScene = load(path)
	if ps == null:
		print("  FAIL: cannot load %s" % path); return 1
	var inst: Node = ps.instantiate()
	if inst == null:
		print("  FAIL: cannot instantiate"); return 1
	get_root().add_child(inst)  # fires _ready -> MapBase auto camera bounds

	# Required nodes (per add-map skill)
	for req in ["Players", "Enemies", "GlobalDropHandler", "PlayerSpawn",
			"Projectiles", "ItemDrops", "TileMap/Mid", "Killzone"]:
		if inst.get_node_or_null(req) == null:
			print("  FAIL: missing required node '%s'" % req); fails += 1

	# Tiles painted + collision present on Mid
	var mid: TileMapLayer = inst.get_node_or_null("TileMap/Mid")
	if mid:
		var cells := mid.get_used_cells().size()
		if cells == 0:
			print("  FAIL: Mid has no painted cells"); fails += 1
		else:
			print("  ok: %d cells, used_rect=%s" % [cells, str(mid.get_used_rect())])
			# Confirm at least one painted tile carries a collision polygon.
			var ts := mid.tile_set
			var c0: Vector2i = mid.get_used_cells()[0]
			var sid := mid.get_cell_source_id(c0)
			var ac := mid.get_cell_atlas_coords(c0)
			var src := ts.get_source(sid) as TileSetAtlasSource
			var td := src.get_tile_data(ac, 0)
			if td and td.get_collision_polygons_count(0) > 0:
				print("  ok: collision polygon present on painted tile %s" % str(c0))
			else:
				print("  FAIL: painted tile %s has no collision polygon" % str(c0)); fails += 1

	# Camera bounds auto-computed by MapBase._ready
	if inst.get("camera_limit_right") != null:
		var l: int = inst.get("camera_limit_left")
		var r: int = inst.get("camera_limit_right")
		if r > l and r < 10000000:
			print("  ok: camera bounds auto [%d..%d]" % [l, r])
		else:
			print("  WARN: camera bounds not auto-computed (l=%d r=%d)" % [l, r])

	# Portal wiring
	var portal := inst.get_node_or_null("PortalToTargetMap")
	if portal:
		var tgt = portal.get("target_map_id")
		if tgt == null or str(tgt) == "":
			print("  FAIL: portal target_map_id unset"); fails += 1
		else:
			print("  ok: portal -> '%s' (spawn '%s')" % [tgt, portal.get("target_spawn_point_name")])

	# Enemy spawners (a bare Marker2D under Enemies spawns nothing; require a real
	# EnemySpawner with enemy_scene + spawn_locations + spawn_container + MP child).
	var spawners: Array[Node] = []
	for n in inst.get_children():
		if n is Node2D and n.has_method("_setup_spawner"):
			spawners.append(n)
	if spawners.is_empty():
		print("  note: no EnemySpawner nodes on this map")
	for s in spawners:
		var has_scene: bool = s.get("enemy_scene") != null
		var locs: Array = s.get("spawn_locations")
		var cont = s.get("spawn_container")
		var mp := s.get_node_or_null("MultiplayerSpawner")
		var nlocs: int = locs.size() if locs != null else 0
		if has_scene and nlocs > 0 and cont != null and mp != null:
			print("  ok: spawner '%s' -> %d locations, container=%s" % [s.name, nlocs, cont.name])
		else:
			print("  FAIL: spawner '%s' misconfigured (scene=%s locs=%d container=%s mp=%s)" % [
				s.name, has_scene, nlocs, cont != null, mp != null]); fails += 1

	# In MAP_SCENES?
	if not MapManager.MAP_SCENES.has(map_id):
		print("  WARN: '%s' not yet registered in MapManager.MAP_SCENES" % map_id)
	else:
		print("  ok: registered in MAP_SCENES")

	inst.queue_free()
	print("  => %s" % ("PASS" if fails == 0 else "%d FAILURE(S)" % fails))
	return fails
