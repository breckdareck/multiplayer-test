extends SceneTree

## Instances the login screen, lets it animate a moment, saves a screenshot.
## Run WINDOWED (headless renders blank):
##   Godot.exe --path . --script res://tools/shot_login.gd

func _initialize() -> void:
	var scn = load("res://scenes/UI/LoginScreen.tscn").instantiate()
	get_root().add_child(scn)
	for i in 50:
		await process_frame
	var img: Image = get_root().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://tools/login_preview.png")
	img.save_png(out)
	print("saved -> %s (%dx%d)" % [out, img.get_width(), img.get_height()])
	quit(0)
