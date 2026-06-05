extends SceneTree

## Renders every VfxCatalog effect into a grid and saves a contact-sheet PNG so
## the effects can be eyeballed (geometry validation can't see "looks right").
## Run WINDOWED (headless uses a dummy renderer -> blank image):
##   Godot.exe --path . --script res://tools/render_vfx_sheet.gd
## Output: tools/vfx_preview.png

const COLS := 6
const CELL := Vector2(170, 150)
const MARGIN := Vector2(20, 20)
const FRAME_AT := 0.55  ## sample each anim at ~55% through its frames

func _initialize() -> void:
	var keys: Array = VfxCatalog.CATALOG.keys()
	var rows: int = int(ceil(float(keys.size()) / float(COLS)))
	var win := get_root()
	win.size = Vector2i(
		int(MARGIN.x * 2 + COLS * CELL.x),
		int(MARGIN.y * 2 + rows * CELL.y))

	# Dark backdrop so transparent/bright effects read.
	var bg := ColorRect.new()
	bg.color = Color(0.12, 0.12, 0.15)
	bg.size = win.size
	win.add_child(bg)

	for i in keys.size():
		var key: String = keys[i]
		var def: Dictionary = VfxCatalog.CATALOG[key]
		var col: int = i % COLS
		var row: int = i / COLS
		var cell_origin := MARGIN + Vector2(col * CELL.x, row * CELL.y)

		var holder := Node2D.new()
		holder.position = cell_origin + Vector2(CELL.x * 0.5, CELL.y * 0.45)
		win.add_child(holder)

		var spr := AnimatedSprite2D.new()
		var sf: SpriteFrames = VfxCatalog.get_frames(key)
		if sf != null:
			spr.sprite_frames = sf
			spr.animation = "play"
			var n: int = sf.get_frame_count("play")
			spr.frame = clampi(int(n * FRAME_AT), 0, maxi(0, n - 1))
			spr.scale = Vector2.ONE * float(def.get("scale", 1.0)) * 1.6
			spr.modulate = def.get("modulate", Color.WHITE)
		holder.add_child(spr)

		var label := Label.new()
		label.text = key
		label.add_theme_color_override("font_color", Color(0.9, 0.95, 1.0))
		label.position = cell_origin + Vector2(6, CELL.y - 24)
		win.add_child(label)

	# Let the renderer present a couple frames before grabbing the image.
	await process_frame
	await process_frame
	await process_frame
	await process_frame

	var img: Image = win.get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://tools/vfx_preview.png")
	var err := img.save_png(out)
	print("save_png -> %s : err=%d  (%dx%d)" % [out, err, img.get_width(), img.get_height()])
	quit(0 if err == OK else 1)
