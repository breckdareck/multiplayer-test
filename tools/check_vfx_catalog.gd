extends SceneTree

## Validates every VfxCatalog entry: loads the sheet, slices the chosen row, and
## confirms a non-empty "play" animation builds. Run headless:
##   Godot.exe --headless --path . --script res://tools/check_vfx_catalog.gd

func _initialize() -> void:
	var fail := 0
	var total := 0
	for key in VfxCatalog.CATALOG.keys():
		total += 1
		var def: Dictionary = VfxCatalog.CATALOG[key]
		var tex: Texture2D = load(def["path"])
		if tex == null:
			print("  [FAIL] %-16s : texture failed to load (%s)" % [key, def["path"]])
			fail += 1
			continue
		var sf: SpriteFrames = VfxCatalog.get_frames(key)
		if sf == null or not sf.has_animation("play"):
			print("  [FAIL] %-16s : no SpriteFrames built" % key)
			fail += 1
			continue
		var n: int = sf.get_frame_count("play")
		var row: int = int(def.get("row", 0))
		var rows_in_sheet: int = int(tex.get_height() / int(def["fh"]))
		var row_ok: String = "" if row < rows_in_sheet else "  <-- ROW OUT OF RANGE!"
		if row >= rows_in_sheet:
			fail += 1
		print("  [ ok ] %-16s : %2d frames  (%dx%d sheet, %dx%d cell, row %d/%d)%s" % [
			key, n, tex.get_width(), tex.get_height(),
			int(def["fw"]), int(def["fh"]), row, rows_in_sheet - 1, row_ok])

	print("\n%s : %d / %d catalog entries valid" % [
		"PASS" if fail == 0 else "FAIL", total - fail, total])
	quit(1 if fail > 0 else 0)
