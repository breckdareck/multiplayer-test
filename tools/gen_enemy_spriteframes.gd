# Builds an enemy SpriteFrames (.tres) from a single grid spritesheet by slicing
# uniform cells and auto-detecting how many real frames each row has (trailing
# blank cells are ignored via an alpha scan). Pillow isn't available in this repo,
# so geometry is detected with Godot's own Image API.
#
# REPORT mode (no --anims): prints each row's detected frame count so you can map
# rows -> animations. Run this FIRST, after VIEWING the sheet, to see the layout:
#   godot --headless --path . --script res://tools/gen_enemy_spriteframes.gd -- \
#       --sheet res://assets/sprites/MiniBeastmens/MiniBeastmens/Outline/MiniBearWarrior-Sheet.png \
#       --cell 40x32
#
# GENERATE mode (--anims given): writes the SpriteFrames. --anims is a comma list
# of animation names mapped, in order, to the rows in --rows (or to the auto-
# detected non-empty rows, top->bottom, if --rows is omitted). Suffix a name with
# '*' to make it LOOP (idle/patrol/run). Names must match what the enemy scene's
# state nodes play (idle / patrol / death required; hit optional; attack state
# uses 'slash_attack' in current templates, or attack_1/attack_2 if you wire them).
#   godot --headless --path . --script res://tools/gen_enemy_spriteframes.gd -- \
#       --sheet res://.../Outline/MiniBearWarrior-Sheet.png --cell 40x32 \
#       --out res://resources/Enemies/BearWarrior/SF_BearWarrior.tres \
#       --rows 0,1,3,4,5,6 --anims "idle*,patrol*,attack_1,attack_2,hit,death" --speed 10
extends SceneTree


func _initialize() -> void:
	var a := _parse_args()
	var sheet: String = a.get("sheet", "")
	if sheet == "":
		printerr("Missing --sheet res://path/to/Sheet.png")
		quit(1); return
	var cw: int = a.get("cell_w", 0)
	var ch: int = a.get("cell_h", 0)
	if cw <= 0 or ch <= 0:
		printerr("Missing/invalid --cell WxH (e.g. --cell 40x32)")
		quit(1); return

	var img := Image.load_from_file(ProjectSettings.globalize_path(sheet))
	if img == null:
		printerr("Could not load image: %s" % sheet)
		quit(1); return
	var cols: int = img.get_width() / cw
	var rows: int = img.get_height() / ch

	# Per-row frame count = leading run of non-blank cells (left-packed sheets).
	var row_frames: Array = []
	for r in rows:
		var n := 0
		for c in cols:
			if _cell_has_content(img, c * cw, r * ch, cw, ch):
				n += 1
			else:
				break
		row_frames.append(n)

	print("=== %s : %dx%d px, cell %dx%d => %d cols x %d rows ===" % [
		sheet.get_file(), img.get_width(), img.get_height(), cw, ch, cols, rows])
	for r in rows:
		print("  row %d (y=%d): %d frame(s)%s" % [r, r * ch, row_frames[r],
			"  [BLANK]" if row_frames[r] == 0 else ""])

	var anims_raw: String = a.get("anims", "")
	if anims_raw == "":
		print("\nREPORT only (no --anims). Map rows to animation names and re-run.")
		quit(0); return

	# Resolve the rows each animation maps to.
	var anim_names: Array = Array(anims_raw.split(",", false))
	var rows_arg: String = a.get("rows", "")
	var target_rows: Array = []
	if rows_arg != "":
		for s in rows_arg.split(",", false):
			target_rows.append(int(s))
	else:
		for r in rows:
			if row_frames[r] > 0:
				target_rows.append(r)
	if target_rows.size() != anim_names.size():
		printerr("Mismatch: %d animation name(s) but %d row(s). Pass --rows explicitly (e.g. --rows 0,1,3,4,5,6 to skip blank/unused rows)." % [anim_names.size(), target_rows.size()])
		quit(1); return

	var out: String = a.get("out", "")
	if out == "":
		printerr("Missing --out res://resources/Enemies/<Name>/SF_<Name>.tres")
		quit(1); return
	var speed: float = a.get("speed", 10.0)

	var tex: Texture2D = load(sheet)
	if tex == null:
		printerr("Could not load sheet as Texture2D (is it imported?): %s" % sheet)
		quit(1); return

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	for i in anim_names.size():
		var raw: String = anim_names[i].strip_edges()
		var loop := raw.ends_with("*")
		var name := raw.trim_suffix("*")
		var r: int = target_rows[i]
		var frames: int = row_frames[r]
		if frames <= 0:
			printerr("Row %d (animation '%s') has 0 frames — check --rows/--cell." % [r, name])
			quit(1); return
		sf.add_animation(name)
		sf.set_animation_speed(name, speed)
		sf.set_animation_loop(name, loop)
		for c in frames:
			var at := AtlasTexture.new()
			at.atlas = tex
			at.region = Rect2(c * cw, r * ch, cw, ch)
			sf.add_frame(name, at)
		print("  + %-14s row %d  %2d frame(s)  loop=%s" % [name, r, frames, loop])

	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var err := ResourceSaver.save(sf, out)
	if err != OK:
		printerr("Failed to save %s (err %d)" % [out, err])
		quit(1); return
	print("Saved %s" % out)
	quit(0)


func _cell_has_content(img: Image, x0: int, y0: int, w: int, h: int) -> bool:
	var x_end: int = mini(x0 + w, img.get_width())
	var y_end: int = mini(y0 + h, img.get_height())
	for y in range(y0, y_end):
		for x in range(x0, x_end):
			if img.get_pixel(x, y).a > 0.0:
				return true
	return false


func _parse_args() -> Dictionary:
	var out := {}
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		var key: String = args[i]
		var val: String = args[i + 1] if i + 1 < args.size() else ""
		match key:
			"--sheet": out["sheet"] = val; i += 2
			"--out": out["out"] = val; i += 2
			"--anims": out["anims"] = val; i += 2
			"--rows": out["rows"] = val; i += 2
			"--speed": out["speed"] = float(val); i += 2
			"--cell":
				var wh := val.to_lower().split("x")
				if wh.size() == 2:
					out["cell_w"] = int(wh[0]); out["cell_h"] = int(wh[1])
				i += 2
			_: i += 1
	return out
