extends SceneTree
func _initialize() -> void:
	var dir := "res://resources/Quests/Endgame/"
	for f in DirAccess.get_files_at(dir):
		if not f.ends_with(".tres"): continue
		var q = load(dir + f)
		if q == null:
			print("FAIL load ", f); continue
		var obj = q.objectives[0] if q.objectives.size() > 0 else {}
		print("OK %-22s L%-3d -> kill %d '%s' (prereq=%s)" % [
			q.quest_id, q.required_level, obj.get("amount",0), obj.get("target","?"), q.prerequisite_quest_id])
	quit()
