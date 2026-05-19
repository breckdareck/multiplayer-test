class_name PlayerContextMenu
extends Panel

var _target_id: int = 0
var _target_is_bot: bool = false
var _button_container: VBoxContainer

const MENU_WIDTH: float = 180.0


static func create() -> PlayerContextMenu:
	var menu := PlayerContextMenu.new()
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.15, 0.95)
	bg.border_color = Color(0.3, 0.3, 0.4, 1.0)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	menu.add_theme_stylebox_override("panel", bg)

	menu._button_container = VBoxContainer.new()
	menu._button_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu._button_container.add_theme_constant_override("separation", 1)
	menu.add_child(menu._button_container)

	return menu


func show_for_target(target_id: int, screen_pos: Vector2) -> void:
	_target_id = target_id
	_target_is_bot = BotManager.is_bot(target_id)

	for child in _button_container.get_children():
		child.queue_free()

	var target_name := _get_target_name()

	_add_button("Inspect %s" % target_name, _do_inspect)
	_add_button("Trade with %s" % target_name, _do_trade)
	_add_button("Invite to Party", _do_party_invite)

	if _target_is_bot and multiplayer.is_server():
		_add_separator()
		_add_button("Force Travel", _do_travel)
		_add_button("Kick from Party", _do_kick)
		_add_button("Despawn Bot", _do_despawn)

	await get_tree().process_frame
	size = Vector2(MENU_WIDTH, _button_container.size.y + 8)

	var vp_size := get_viewport_rect().size
	var pos := screen_pos
	if pos.x + size.x > vp_size.x:
		pos.x = vp_size.x - size.x
	if pos.y + size.y > vp_size.y:
		pos.y = vp_size.y - size.y
	global_position = pos
	visible = true
	move_to_front()


func _add_button(text: String, callback: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.flat = true
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size = Vector2(MENU_WIDTH - 8, 24)
	btn.add_theme_font_size_override("font_size", 11)
	btn.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	btn.add_theme_color_override("font_hover_color", Color(1.0, 0.95, 0.7))

	var hover_bg := StyleBoxFlat.new()
	hover_bg.bg_color = Color(0.25, 0.25, 0.35, 1.0)
	hover_bg.set_corner_radius_all(2)
	btn.add_theme_stylebox_override("hover", hover_bg)

	var normal_bg := StyleBoxEmpty.new()
	btn.add_theme_stylebox_override("normal", normal_bg)
	btn.add_theme_stylebox_override("pressed", hover_bg)
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

	btn.pressed.connect(func():
		callback.call()
		visible = false
	)
	_button_container.add_child(btn)


func _add_separator() -> void:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = Color(0.3, 0.3, 0.4, 0.5)
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	_button_container.add_child(sep)


func _get_target_name() -> String:
	if _target_is_bot:
		var bot_info: Dictionary = BotManager.active_bots.get(_target_id, {})
		return bot_info.get("username", "Bot %d" % _target_id)
	else:
		var player_node := PlayerManager.get_player_node(_target_id)
		if is_instance_valid(player_node) and not player_node.username.is_empty():
			return player_node.username
		var player_info = PlayerManager.get_player_info(_target_id)
		if player_info:
			return player_info.get("username", str(_target_id))
	return str(_target_id)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var local_rect := Rect2(global_position, size)
		if not local_rect.has_point(event.global_position):
			visible = false


func _do_inspect() -> void:
	BotManager.open_inspect_window(_target_id)


func _do_trade() -> void:
	_open_trade_window(_target_id)


func _open_trade_window(target_id: int) -> void:
	var moveable := _find_moveable_container()
	if not moveable:
		return

	var existing: TradeWindow = null
	for child in moveable.get_children():
		if child is TradeWindow:
			existing = child
			break

	if not existing:
		existing = TradeWindow.create()
		moveable.add_child(existing)

	existing.show_for_target(target_id)


func _find_moveable_container() -> Node:
	var player_node := PlayerManager.get_player_node(multiplayer.get_unique_id())
	if is_instance_valid(player_node):
		var container = player_node.get_node_or_null("CanvasLayer/MoveableWindows")
		if container:
			return container
	return null


func _do_party_invite() -> void:
	var target_name := _get_target_name()
	PartyManager.rpc_send_invite(target_name)


func _do_kick() -> void:
	if _target_is_bot and multiplayer.is_server():
		var party_id := PartyManager.get_player_party_id(_target_id)
		if party_id != -1:
			PartyManager.leave_party(_target_id)
			ChatManager.add_system_message("Kicked bot from party.", Color.CYAN)
		else:
			ChatManager.add_system_message("Bot is not in a party.", Color.ORANGE)


func _do_travel() -> void:
	if _target_is_bot and multiplayer.is_server():
		var player_node := PlayerManager.get_player_node(_target_id)
		if is_instance_valid(player_node):
			var brain = player_node.get_node_or_null("BotBrain")
			if brain:
				brain._map_travel_timer = 0.0
				ChatManager.add_system_message("Forcing travel check for bot.", Color.CYAN)


func _do_despawn() -> void:
	if _target_is_bot and multiplayer.is_server():
		var bot_name := _get_target_name()
		BotManager.despawn_bot(_target_id)
		ChatManager.add_system_message("Despawned bot '%s'." % bot_name, Color.CYAN)
