extends SceneTree
# Renders a generated map to a PNG via a SubViewport (deterministic size, no
# dependence on the OS window honoring a resize). Run WITH a real driver:
#   Godot.exe --path . --rendering-driver opengl3 \
#       --script res://tools/render_map.gd -- <map_id>

var _started := false

func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	_go()
	return false


func _go() -> void:
	var ids := OS.get_cmdline_user_args()
	var map_id: String = ids[0] if ids.size() > 0 else "meadow_path"
	var ps: PackedScene = load("res://scenes/Levels/%s.tscn" % map_id)
	var inst: Node2D = ps.instantiate()

	# Probe the painted area first (instantiate twice is cheap; reuse this one).
	var tmp_mid: TileMapLayer = inst.get_node("TileMap/Mid")
	var used: Rect2i = tmp_mid.get_used_rect()
	# Include the decoration layers so tall props/ladders aren't clipped.
	for layer_name in ["TileMap/Background", "TileMap/Background2"]:
		var bg := inst.get_node_or_null(layer_name)
		if bg is TileMapLayer and (bg as TileMapLayer).get_used_cells().size() > 0:
			used = used.merge((bg as TileMapLayer).get_used_rect())
	var ts := Vector2(tmp_mid.tile_set.tile_size)
	var world := Rect2(Vector2(used.position) * ts, Vector2(used.size) * ts).grow(48.0)

	# Optional focus crop: -- <map_id> focus <cx_tile> <cy_tile> <half_tiles>
	if ids.size() >= 5 and ids[1] == "focus":
		var c := Vector2(int(ids[2]) * ts.x, int(ids[3]) * ts.y)
		var half := int(ids[4]) * ts.x
		world = Rect2(c - Vector2(half, half), Vector2(half * 2, half * 2))

	var W := 1100
	var H := int(round(W * world.size.y / world.size.x))
	var vp := SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	get_root().add_child(vp)
	vp.add_child(inst)

	var cam := Camera2D.new()
	cam.position = world.get_center()
	cam.zoom = Vector2(W / world.size.x, W / world.size.x)
	inst.add_child(cam)
	cam.make_current()

	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await process_frame
	await RenderingServer.frame_post_draw

	var img := vp.get_texture().get_image()
	var suffix := "_focus" if (ids.size() >= 5 and ids[1] == "focus") else ""
	var out := "res://docs/render_%s%s.png" % [map_id, suffix]
	img.save_png(out)
	print("rendered %s -> %s (%dx%d)" % [map_id, out, W, H])
	quit(0)
