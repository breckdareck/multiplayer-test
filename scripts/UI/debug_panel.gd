extends CanvasLayer
## Backtick-toggled debug panel for bot tooling.
##
## Lists active bots, spawns/despawns them, toggles the navigation debug
## overlay, camera-follows a bot, and shows a selected bot's lifetime metrics —
## the clickable equivalent of the `/bot` console commands. Built entirely in
## code (no .tscn). Registered as the `DebugPanel` autoload.
##
## Only opens in debug builds, and the bot actions only do anything on the host
## (bots are server-side).

const SPAWN_CLASSES := ["SWORDSMAN", "ARCHER", "MAGE", "ROGUE"]
const REFRESH_INTERVAL := 0.5

var _panel: PanelContainer
var _roster: ItemList
var _class_picker: OptionButton
var _debugdraw_check: CheckBox
var _stats_label: Label
var _watch_label: Label
var _roster_ids: Array[int] = []
var _selected_bot: int = 0
var _refresh_timer := 0.0


func _ready() -> void:
	layer = 128  # above the gameplay HUD
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_panel.visible = false


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.keycode == KEY_QUOTELEFT:
		_panel.visible = not _panel.visible
		if _panel.visible:
			_refresh()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _panel.visible:
		return
	_refresh_timer -= delta
	if _refresh_timer <= 0.0:
		_refresh_timer = REFRESH_INTERVAL
		_refresh()


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.custom_minimum_size = Vector2(320, 0)
	add_child(_panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_panel.add_child(vb)

	var title := Label.new()
	title.text = "Bot Debug   ( ` to close )"
	vb.add_child(title)

	_roster = ItemList.new()
	_roster.custom_minimum_size = Vector2(0, 150)
	_roster.item_selected.connect(_on_roster_selected)
	vb.add_child(_roster)

	var spawn_row := HBoxContainer.new()
	vb.add_child(spawn_row)
	_class_picker = OptionButton.new()
	for cls in SPAWN_CLASSES:
		_class_picker.add_item(cls)
	spawn_row.add_child(_class_picker)
	spawn_row.add_child(_make_button("Spawn", _on_spawn))

	var despawn_row := HBoxContainer.new()
	vb.add_child(despawn_row)
	despawn_row.add_child(_make_button("Despawn", _on_despawn))
	despawn_row.add_child(_make_button("Despawn All", _on_despawn_all))

	var watch_row := HBoxContainer.new()
	vb.add_child(watch_row)
	watch_row.add_child(_make_button("Watch", _on_watch))
	watch_row.add_child(_make_button("Stop Watch", _on_stop_watch))
	_watch_label = Label.new()
	_watch_label.text = "Watching: none"
	watch_row.add_child(_watch_label)

	_debugdraw_check = CheckBox.new()
	_debugdraw_check.text = "Nav debug draw"
	_debugdraw_check.toggled.connect(_on_debugdraw_toggled)
	vb.add_child(_debugdraw_check)

	_stats_label = Label.new()
	_stats_label.text = "Select a bot to see its stats."
	_stats_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stats_label.custom_minimum_size = Vector2(0, 60)
	vb.add_child(_stats_label)


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(handler)
	return b


# --- Refresh ----------------------------------------------------------------

func _refresh() -> void:
	_refresh_roster()
	_refresh_stats()
	var watched: int = BotManager.get_watched_bot()
	_watch_label.text = "Watching: %s" % ("none" if watched == 0 else str(watched))


func _refresh_roster() -> void:
	_roster.clear()
	_roster_ids.clear()
	for bot_id in BotManager.active_bots:
		var info: Dictionary = BotManager.active_bots[bot_id]
		var level := "?"
		var node := PlayerManager.get_player_node(bot_id)
		if is_instance_valid(node) and is_instance_valid(node.level_component):
			level = str(node.level_component.level)
		var cls = Constants.ClassType.find_key(info.get("class_type", 0))
		_roster.add_item("[%d] %s  %s Lv.%s  @%s" % [
			bot_id, info.get("username", "?"), cls, level, info.get("map_id", "?")])
		_roster_ids.append(bot_id)
		if bot_id == _selected_bot:
			_roster.select(_roster_ids.size() - 1)


func _refresh_stats() -> void:
	if _selected_bot == 0 or not BotManager.active_bots.has(_selected_bot):
		_stats_label.text = "Select a bot to see its stats."
		return
	var brain = BotManager.get_bot_brain(_selected_bot)
	if brain == null:
		_stats_label.text = "Bot %d: no active brain." % _selected_bot
		return
	var m: Dictionary = brain.get_metrics()
	_stats_label.text = "Bot %d  —  action: %s\nkills %d   deaths %d (enemy %d / hazard %d)\nstuck %d   travel-abandons %d\nloot %d   sale-gold %d" % [
		_selected_bot, brain.current_action,
		m.kills, m.deaths, m.deaths_to_enemy, m.deaths_to_hazard,
		m.stuck_recoveries, m.travel_abandons, m.loot_collected, m.gold_from_sales]


# --- Button handlers --------------------------------------------------------

func _on_roster_selected(index: int) -> void:
	if index >= 0 and index < _roster_ids.size():
		_selected_bot = _roster_ids[index]
		_refresh_stats()


func _on_spawn() -> void:
	var cls: String = SPAWN_CLASSES[_class_picker.selected] if _class_picker.selected >= 0 else SPAWN_CLASSES[0]
	BotManager.handle_command(["spawn", "random", cls])
	_refresh()


func _on_despawn() -> void:
	if _selected_bot != 0:
		BotManager.handle_command(["despawn", str(_selected_bot)])
		_selected_bot = 0
		_refresh()


func _on_despawn_all() -> void:
	BotManager.handle_command(["despawn_all"])
	_selected_bot = 0
	_refresh()


func _on_watch() -> void:
	if _selected_bot != 0:
		BotManager.watch_bot(_selected_bot)
		_refresh()


func _on_stop_watch() -> void:
	BotManager.watch_bot(0)
	_refresh()


func _on_debugdraw_toggled(pressed: bool) -> void:
	BotManager.handle_command(["debugdraw", "on" if pressed else "off"])
