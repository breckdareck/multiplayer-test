extends SceneTree
## Increase enemy density in mines: grow each spawner's marker count to TARGET and bump pool_size
## (pool_size = the map-cap contribution = how many spawn; markers = where, picked at random).
## New markers get a placeholder position; run fix_spawns.gd afterward to place them on surfaces.
const MAP := "res://scenes/Levels/meadow_path.tscn"
const TARGET := 9
const NAMES := ["slime", "bunny"]
const POOL := {"slime": 9, "bunny": 9}

func _init() -> void:
	var f := FileAccess.open(MAP, FileAccess.READ); var text := f.get_as_text(); f.close()
	# Process spawners last-to-first so earlier header offsets stay valid.
	var entries := []
	for nm in NAMES:
		var hs := text.find('[node name="Spawn_%s"' % nm)
		if hs != -1: entries.append([hs, nm])
	entries.sort_custom(func(a, b): return a[0] > b[0])

	for e in entries:
		var nm: String = e[1]
		var spawner := "Spawn_" + nm
		var hs: int = e[0]
		# Count existing markers for this spawner.
		var existing := 0
		while text.find('[node name="M%d" type="Marker2D" parent="%s"]' % [existing, spawner]) != -1:
			existing += 1
		# 1. spawn_locations array -> M0..M(TARGET-1)
		var sl := text.find("spawn_locations = [", hs)
		var locs := []
		for i in TARGET: locs.append('NodePath("M%d")' % i)
		text = text.substr(0, sl) + "spawn_locations = [" + ", ".join(locs) + "]" + text.substr(text.find("]", sl) + 1)
		# 2. pool_size
		var ps := text.find("pool_size = ", hs)
		text = text.substr(0, ps) + "pool_size = %d" % POOL[nm] + text.substr(text.find("\n", ps))
		# 3. add the missing markers just before this spawner's MultiplayerSpawner node
		if existing < TARGET:
			var msp := text.find('[node name="MultiplayerSpawner" type="MultiplayerSpawner" parent="%s"]' % spawner)
			var mk := ""
			for i in range(existing, TARGET):
				mk += '[node name="M%d" type="Marker2D" parent="%s"]\nposition = Vector2(0, 0)\n\n' % [i, spawner]
			text = text.substr(0, msp) + mk + text.substr(msp)

	var w := FileAccess.open(MAP, FileAccess.WRITE); w.store_string(text); w.close()
	print("OK markers->", TARGET, " per spawner; pools=", POOL)
	quit()
