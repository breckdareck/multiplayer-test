extends SceneTree
# Boots a live OFFLINE game via the LoginScreen dev fast-path (no backend needed),
# waits for spawn, and screenshots the root viewport (which composites the active
# map's SubViewport + the persistent local UI layer). Produces fresh in-game
# README shots without touching the desktop.
#
#   Godot.exe --path . --script res://tools/shot_ingame.gd -- <disc 0..3>
#   0=Sword 1=Bow 2=Staff 3=Dagger  (default 0)

func _initialize() -> void:
	_run()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var disc := int(args[0]) if args.size() > 0 else 0

	var login: Node = load("res://scenes/UI/LoginScreen.tscn").instantiate()
	get_root().add_child(login)
	for i in 30:
		await process_frame

	# Fire the same offline host-into-combat path the dev sidebar button uses.
	login._on_dev_skip_pressed(disc)

	# Wait for: server start -> map load -> JoinHandshake -> deferred recalc -> camera settle.
	for i in 360:
		await process_frame

	# Single-weapon combat shot.
	await _save("res://README/Gameplay.png")

	# Equip a SECOND weapon (a different discipline) so the dual-kit shows: two
	# screen-edge gauge widgets light up and the 2nd weapon slot fills.
	_equip_secondary(Constants.WeaponType.BOW)
	for i in 120:
		await process_frame
	await _save("res://README/Weapon_Widget.png")

	# Move the host to the Hearth hub (Lantern's Rest) for the town shot.
	var map_manager := get_root().get_node("/root/MapManager")
	map_manager.request_map_change(1, "lanterns_rest")
	for i in 240:
		await process_frame
	await _save("res://README/Lanterns_Rest.png")

	# Unified game window — Character tab (Equipment with TWO weapons + the five
	# attributes + Inventory).
	_press_action("OpenStatsWindow")
	for i in 90:
		await process_frame
	await _save("res://README/Game_Window.png")

	# Abilities tab (branching weapon-mastery skill tree).
	_press_action("OpenAbilityWindow")
	for i in 90:
		await process_frame
	await _save("res://README/Abilities.png")

	quit(0)


## Drops a fresh weapon of `wtype` into the host player's SECONDARY_WEAPON slot
## and flags an equipment change so stats, the sprite, and the gauge widgets
## re-derive. Server-side direct mutation — fine for a screenshot harness.
func _equip_secondary(wtype: int) -> void:
	var player_manager := get_root().get_node("/root/PlayerManager")
	var resource_manager := get_root().get_node("/root/ResourceManager")
	var player = player_manager.get_player_node(1)
	if player == null or player.equipment_component == null:
		print("WARN: no host player / equipment to equip secondary")
		return
	var pick: WeaponData = null
	for item in resource_manager.item_data.values():
		if item is WeaponData and item.weapon_type == wtype:
			pick = item
			break
	if pick == null:
		print("WARN: no WeaponData of type %d found" % wtype)
		return
	var eq = player.equipment_component
	var sd = eq.slots_data.get("SECONDARY_WEAPON")
	if sd == null:
		print("WARN: no SECONDARY_WEAPON slot")
		return
	sd.item = pick.duplicate_with_path()
	eq.refresh_view("SECONDARY_WEAPON")
	eq.mark_changed()
	print("equipped secondary: %s" % pick.name)


func _press_action(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await process_frame
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func _save(path: String) -> void:
	await RenderingServer.frame_post_draw
	await process_frame
	var img: Image = get_root().get_texture().get_image()
	img.save_png(path)
	print("saved -> %s (%dx%d)" % [path, img.get_width(), img.get_height()])
