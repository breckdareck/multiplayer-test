extends SceneTree
## Headless smoke test for MapBase auto side walls.
## Run: godot --headless --path . --script res://tools/smoke_side_walls.gd
## NOTE: full level scenes can't be instantiated in --script mode (their
## scripts reference autoloads), so the runtime check uses a synthetic map
## and the lanterns_rest wiring is checked textually.

func _init() -> void:
	process_frame.connect(_run, CONNECT_ONE_SHOT)


func _run() -> void:
	var failures := 0

	# --- 1. Synthetic map: known tile extent -> known wall positions ---
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(16, 16)
	var source := TileSetAtlasSource.new()
	var tex := PlaceholderTexture2D.new()
	tex.size = Vector2(16, 16)
	source.texture = tex
	source.create_tile(Vector2i(0, 0))
	tile_set.add_source(source, 0)

	var map := Node2D.new()
	map.set_script(load("res://scripts/Gameplay/map_base.gd"))
	map.side_walls_auto = true
	map.side_wall_margin = 4.0
	var mid := TileMapLayer.new()
	mid.name = "Mid"
	mid.tile_set = tile_set
	mid.set_cell(Vector2i(-3, 0), 0, Vector2i(0, 0))
	mid.set_cell(Vector2i(5, 0), 0, Vector2i(0, 0))
	map.add_child(mid)
	root.add_child(map)

	var walls: Node = map.get_node_or_null("SideWalls")
	if walls == null:
		print("FAIL: SideWalls node not created")
		failures += 1
	else:
		if not (walls is StaticBody2D) or walls.collision_layer != 1:
			print("FAIL: SideWalls wrong type/layer: ", walls)
			failures += 1
		var shapes := walls.get_children()
		if shapes.size() != 2:
			print("FAIL: expected 2 colliders, got ", shapes.size())
			failures += 1
		else:
			# Mid extent: x in [-48, 96]; margin 4 -> walls at -52 and 100.
			var left: CollisionShape2D = shapes[0]
			var right: CollisionShape2D = shapes[1]
			if left.position.x != -52.0 or left.shape.normal != Vector2.RIGHT:
				print("FAIL: left wall pos/normal: ", left.position, " ", left.shape.normal)
				failures += 1
			if right.position.x != 100.0 or right.shape.normal != Vector2.LEFT:
				print("FAIL: right wall pos/normal: ", right.position, " ", right.shape.normal)
				failures += 1

	# --- 2. Default-on: walls created without touching the flag; opt-out works ---
	for flag_off in [false, true]:
		var map2 := Node2D.new()
		map2.set_script(load("res://scripts/Gameplay/map_base.gd"))
		if flag_off:
			map2.side_walls_auto = false
		var mid2 := TileMapLayer.new()
		mid2.name = "Mid"
		mid2.tile_set = tile_set
		mid2.set_cell(Vector2i(0, 0), 0, Vector2i(0, 0))
		map2.add_child(mid2)
		root.add_child(map2)
		var has_walls := map2.get_node_or_null("SideWalls") != null
		if flag_off and has_walls:
			print("FAIL: SideWalls created despite side_walls_auto = false")
			failures += 1
		if not flag_off and not has_walls:
			print("FAIL: SideWalls not created by default")
			failures += 1

	# --- 3. No legacy Barrier tile layers remain in any level scene ---
	var dir := DirAccess.open("res://scenes/Levels")
	for file in dir.get_files():
		if not file.ends_with(".tscn"):
			continue
		var scene_text := FileAccess.get_file_as_string("res://scenes/Levels/" + file)
		if scene_text.contains("name=\"Barrier\""):
			print("FAIL: legacy Barrier layer still present in ", file)
			failures += 1

	if failures == 0:
		print("SMOKE PASS: walls at expected positions; default on; opt-out works; no Barrier layers")
	quit(1 if failures > 0 else 0)
