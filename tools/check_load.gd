extends SceneTree
## Smoke-load every world map to confirm the portal rewrite didn't corrupt any .tscn.
func _init() -> void:
	for m in ["lanterns_rest", "near_wilds", "meadow_path", "ember_meadows", "ruins", "three_terraces", "old_battlefield", "thornroot", "dust_warren", "mines", "emberwatch", "deep_woods", "keep", "mustering_fields", "emberscar", "cinderwaste", "ashvigil", "weave", "warlord"]:
		var r := ResourceLoader.load("res://scenes/Levels/%s.tscn" % m)
		print(m, ": ", "OK" if r != null else "LOAD FAIL")
	quit()
