extends SceneTree
func _collect(n, out):
	if "target_map_id" in n and n.target_map_id is String and n.target_map_id != "":
		out[n.target_map_id] = true
	for c in n.get_children(): _collect(c, out)
func _initialize() -> void:
	var targets := {}
	for id in MapManager.MAP_SCENES:
		var ps = load(MapManager.MAP_SCENES[id])
		if ps == null: print("FAIL load ", id); continue
		var inst = ps.instantiate()
		_collect(inst, targets)
		print("OK %-14s display='%s'" % [id, inst.display_name])
		inst.free()
	for t in targets:
		if not MapManager.MAP_SCENES.has(t):
			print("BAD PORTAL TARGET -> '%s' (not a map id)" % t)
	print("portal targets seen: ", targets.keys())
	quit()
