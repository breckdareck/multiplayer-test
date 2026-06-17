extends SceneTree
## Load-check + inspect the 4 new battlefield/ash maps: confirm each .tscn loads,
## then count enemy spawners / enemy instances and report Mid-layer tile bounds.
func _init() -> void:
	for m in ["old_battlefield", "mustering_fields", "ashvigil", "cinderwaste"]:
		var path := "res://scenes/Levels/%s.tscn" % m
		var ps: PackedScene = ResourceLoader.load(path)
		if ps == null:
			print(m, ": LOAD FAIL")
			continue
		var root: Node = ps.instantiate()
		var spawners := 0
		var enemy_instances := 0
		var en := root.get_node_or_null("Enemies")
		if en != null:
			for c in en.get_children():
				enemy_instances += 1
		# Count EnemySpawner nodes anywhere under the root.
		for n in _walk(root):
			var scr = n.get_script()
			if scr != null and str(scr.resource_path).ends_with("enemy_spawner.gd"):
				spawners += 1
		var rect := "n/a"
		var mid := root.get_node_or_null("TileMap/Mid")
		if mid != null:
			rect = str(mid.get_used_rect())
		print("%s: OK | spawners=%d enemy_instances=%d mid_used_rect=%s" % [m, spawners, enemy_instances, rect])
		root.free()
	quit()

func _walk(n: Node) -> Array:
	var out: Array = [n]
	for c in n.get_children():
		out.append_array(_walk(c))
	return out
