extends SceneTree
func _initialize() -> void:
	for id in ["mines","keep","emberscar","weave","warlord"]:
		var p := "res://scenes/Levels/%s.tscn" % id
		var ps = load(p)
		if ps == null:
			print("FAIL load: ", id); continue
		var inst = ps.instantiate()
		if inst == null:
			print("FAIL instantiate: ", id); continue
		var en = inst.get_node_or_null("Enemies")
		var pl = inst.get_node_or_null("Players")
		var gdh = inst.get_node_or_null("GlobalDropHandler")
		print("OK %-10s name='%s' enemies=%d players=%s gdh=%s" % [
			id, inst.display_name, (en.get_child_count() if en else -1),
			pl != null, gdh != null])
		inst.free()
	quit()
