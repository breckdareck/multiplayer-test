extends CanvasLayer
## Backtick-toggled developer console.
##
## Slides down from the top on `, with a typed command line (Tab autocomplete,
## Up/Down history, persistent across sessions), alias table, quick-action
## buttons, and a resize handle. Built in code; no .tscn. Registered as the
## `DebugPanel` autoload (name kept for backwards compat).
##
## Routes:
##   bot ...    -> BotManager.handle_command         (host-only effect)
##   quest ...  -> QuestManager.handle_quest_command (host-only effect)
##
## Targeted commands (heal/damage/revive/level/give/gold/tp): default to the
## local player; prefix '@<peer_id|name>' to act on another player or bot
## (host-only — these mutate authoritative state). Enemy spawning is host-only
## and works on whichever map the host is currently viewing.
##
## Opens only in debug builds. Locks input via InputManager.set_input_locked.

const SPAWN_CLASSES := ["SWORDSMAN", "ARCHER", "MAGE", "ROGUE"]
const DEFAULT_PANEL_HEIGHT := 360
const MIN_PANEL_HEIGHT := 160
const MAX_PANEL_HEIGHT := 720
const SLIDE_DURATION := 0.18
const HISTORY_LIMIT := 200
const OUTPUT_LIMIT := 600
const SUGGESTION_LIMIT := 6
const HISTORY_FILE := "user://debug_console_history.json"

# --- UI ---
var _root: PanelContainer
var _output: RichTextLabel
var _input_edit: LineEdit
var _suggestions: Label
var _quick_class_picker: OptionButton
var _layer_graph_check: CheckBox
var _layer_paths_check: CheckBox
var _layer_info_check: CheckBox
var _resize_grabber: Control
var _title_label: Label
var _panel_height: int = DEFAULT_PANEL_HEIGHT
var _is_open := false
var _tween: Tween

# --- Command state ---
var _commands: Dictionary = {}      # name -> { desc, handler:Callable, completer:Callable }
var _aliases: Dictionary = {}       # alias name -> expansion string
var _history: Array[String] = []
var _history_idx: int = -1
var _draft: String = ""
var _suggestion_matches: PackedStringArray = []
var _suggestion_token_start: int = 0
var _resizing: bool = false


func _ready() -> void:
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_history()
	_build_ui()
	_register_commands()
	_root.position.y = -_panel_height


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_QUOTELEFT:
			_toggle()
			get_viewport().set_input_as_handled()
		elif _is_open and event.keycode == KEY_ESCAPE:
			_close()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	# Keep the title showing live map + x/y for the local player. Used as a
	# reference when typing `tp <x> <y>`.
	if not _is_open or not is_instance_valid(_title_label):
		return
	var p := _local_player()
	if is_instance_valid(p):
		var map_id: String = MapManager.get_player_map(p.player_id) if MapManager.has_method("get_player_map") else ""
		_title_label.text = "Debug   @%s  (%d, %d)   ( ` close · Esc · Tab · ↑/↓ )" % [
			map_id if not map_id.is_empty() else "?",
			int(p.global_position.x), int(p.global_position.y)]
	else:
		_title_label.text = "Debug   (no local player)   ( ` close · Esc · Tab · ↑/↓ )"


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	_root = PanelContainer.new()
	_root.anchor_left = 0.0
	_root.anchor_right = 1.0
	_root.anchor_top = 0.0
	_root.anchor_bottom = 0.0
	_root.offset_top = 0
	_root.offset_bottom = _panel_height
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	_root.add_child(vb)

	vb.add_child(_build_quick_actions_row())

	_output = RichTextLabel.new()
	_output.bbcode_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_output.custom_minimum_size = Vector2(0, 220)
	_output.focus_mode = Control.FOCUS_NONE
	vb.add_child(_output)

	_suggestions = Label.new()
	_suggestions.add_theme_font_size_override("font_size", 11)
	_suggestions.modulate = Color(1, 1, 1, 0.55)
	_suggestions.text = ""
	vb.add_child(_suggestions)

	var input_row := HBoxContainer.new()
	vb.add_child(input_row)
	var prompt := Label.new()
	prompt.text = "> "
	input_row.add_child(prompt)
	_input_edit = LineEdit.new()
	_input_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input_edit.placeholder_text = "type a command (try: help)"
	_input_edit.text_changed.connect(_on_input_changed)
	_input_edit.text_submitted.connect(_on_input_submitted)
	_input_edit.gui_input.connect(_on_input_gui_input)
	input_row.add_child(_input_edit)

	_resize_grabber = _build_resize_grabber()
	vb.add_child(_resize_grabber)


func _build_quick_actions_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	_title_label = Label.new()
	_title_label.text = "Debug   ( ` close · Esc dismiss · Tab complete · ↑/↓ history )"
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title_label)

	_quick_class_picker = OptionButton.new()
	_quick_class_picker.focus_mode = Control.FOCUS_NONE
	for cls in SPAWN_CLASSES:
		_quick_class_picker.add_item(cls)
	row.add_child(_quick_class_picker)

	row.add_child(_make_button("Spawn", func():
		var cls: String = SPAWN_CLASSES[_quick_class_picker.selected if _quick_class_picker.selected >= 0 else 0]
		_run_line("bot spawn random %s" % cls)))
	row.add_child(_make_button("Despawn All", func(): _run_line("bot despawn_all")))
	row.add_child(_make_button("Nav Draw", func(): _run_line("navdraw")))
	_layer_graph_check = _make_layer_check("Graph", func(on): _push_layer("graph", on))
	_layer_paths_check = _make_layer_check("Paths", func(on): _push_layer("paths", on))
	_layer_info_check = _make_layer_check("Info", func(on): _push_layer("info", on))
	row.add_child(_layer_graph_check)
	row.add_child(_layer_paths_check)
	row.add_child(_layer_info_check)
	row.add_child(_make_button("State", func(): _run_line("state")))
	row.add_child(_make_button("Pause", func(): _run_line("pause")))
	row.add_child(_make_button("Heal", func(): _run_line("heal")))
	row.add_child(_make_button("Snap", func(): _run_line("snapshot")))
	row.add_child(_make_button("Clear", func(): _run_line("clear")))
	return row


func _make_button(text: String, handler: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(handler)
	return b


func _make_layer_check(text: String, handler: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = true
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(handler)
	return c


func _build_resize_grabber() -> Control:
	# A 6-px-tall strip the user can drag to resize the console height.
	var grabber := ColorRect.new()
	grabber.color = Color(1, 1, 1, 0.12)
	grabber.custom_minimum_size = Vector2(0, 6)
	grabber.mouse_default_cursor_shape = Control.CURSOR_VSIZE
	grabber.gui_input.connect(_on_grabber_input)
	return grabber


func _on_grabber_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_resizing = event.pressed
	elif event is InputEventMouseMotion and _resizing:
		_panel_height = clampi(_panel_height + int(event.relative.y), MIN_PANEL_HEIGHT, MAX_PANEL_HEIGHT)
		_root.offset_bottom = _panel_height
		# When closed (rare during a drag) keep it hidden above the screen.
		if not _is_open:
			_root.position.y = -_panel_height


func _push_layer(which: String, on: bool) -> void:
	var dd = BotManager.get_debug_draw()
	if dd == null: return
	match which:
		"graph": dd.show_graph = on
		"paths": dd.show_paths = on
		"info":  dd.show_bot_info = on


# --- Open / close -----------------------------------------------------------

func _toggle() -> void:
	if _is_open:
		_close()
	else:
		_open()


func _open() -> void:
	_is_open = true
	InputManager.set_input_locked(true)
	if is_instance_valid(_tween): _tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "position:y", 0.0, SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_input_edit.grab_focus()


func _close() -> void:
	_is_open = false
	InputManager.set_input_locked(false)
	if is_instance_valid(_tween): _tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "position:y", float(-_panel_height), SLIDE_DURATION) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	_input_edit.release_focus()
	_suggestions.text = ""


# --- Input handling ---------------------------------------------------------

func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_TAB:
				_complete_token()
				_input_edit.accept_event()
			KEY_UP:
				_history_step(-1)
				_input_edit.accept_event()
			KEY_DOWN:
				_history_step(1)
				_input_edit.accept_event()


func _on_input_changed(_text: String) -> void:
	if _input_edit.text.contains("`"):
		var caret := _input_edit.caret_column
		_input_edit.text = _input_edit.text.replace("`", "")
		_input_edit.caret_column = max(0, caret - 1)
	_refresh_suggestions()


func _on_input_submitted(text: String) -> void:
	var line := text.strip_edges()
	_input_edit.clear()
	_suggestions.text = ""
	_input_edit.call_deferred("grab_focus")
	if line.is_empty():
		return
	_history.push_back(line)
	while _history.size() > HISTORY_LIMIT:
		_history.pop_front()
	_save_history()
	_history_idx = -1
	_draft = ""
	_print("[color=#7ec8ff]> %s[/color]" % _escape_bb(line))
	_run_line(line)


func _history_step(direction: int) -> void:
	if _history.is_empty(): return
	if _history_idx == -1:
		_draft = _input_edit.text
		_history_idx = _history.size()
	_history_idx = clamp(_history_idx + direction, 0, _history.size())
	if _history_idx == _history.size():
		_input_edit.text = _draft
	else:
		_input_edit.text = _history[_history_idx]
	_input_edit.caret_column = _input_edit.text.length()
	_refresh_suggestions()


# --- Autocomplete -----------------------------------------------------------

func _refresh_suggestions() -> void:
	_suggestion_matches = _compute_matches(_input_edit.text)
	if _suggestion_matches.is_empty():
		_suggestions.text = ""
	else:
		_suggestions.text = "  ".join(_suggestion_matches.slice(0, SUGGESTION_LIMIT))


func _compute_matches(text: String) -> PackedStringArray:
	var caret: int = _input_edit.caret_column
	var prefix_text: String = text.substr(0, caret)
	var space_idx: int = prefix_text.rfind(" ")
	_suggestion_token_start = space_idx + 1
	var token: String = prefix_text.substr(_suggestion_token_start)

	if space_idx == -1:
		var names: PackedStringArray = []
		var keys := _commands.keys()
		keys.append_array(_aliases.keys())
		keys.sort()
		for name in keys:
			if name.begins_with(token):
				names.append(name)
		return names

	var head: String = prefix_text.substr(0, space_idx)
	var head_tokens: PackedStringArray = head.split(" ", false)
	if head_tokens.is_empty(): return PackedStringArray()
	var cmd_name: String = head_tokens[0]

	# Multi-word completion for 'give' — item names contain spaces, so the
	# default token-by-token model can't match them.
	if cmd_name == "give":
		return _compute_give_matches(prefix_text, head_tokens)

	if not _commands.has(cmd_name): return PackedStringArray()
	var completer: Callable = _commands[cmd_name].get("completer", Callable())
	if not completer.is_valid(): return PackedStringArray()
	var arg_tokens: PackedStringArray = head_tokens.slice(1)
	var candidates: PackedStringArray = completer.call(arg_tokens, token)
	var matches: PackedStringArray = []
	for c in candidates:
		if c.begins_with(token):
			matches.append(c)
	return matches


## Special-case completion for 'give', whose item-name arg can span multiple
## tokens. Treats everything from after 'give ' (skipping an optional @target)
## up to the caret as one multi-word token, and matches that prefix against
## item names. Sets _suggestion_token_start so Tab replaces the full span.
func _compute_give_matches(prefix_text: String, head_tokens: PackedStringArray) -> PackedStringArray:
	var name_start: int = "give ".length()
	var has_target := false
	if head_tokens.size() >= 2 and String(head_tokens[1]).begins_with("@"):
		name_start += head_tokens[1].length() + 1  # +1 for the trailing space
		has_target = true
	_suggestion_token_start = name_start

	var multi: String = ""
	if prefix_text.length() > name_start:
		multi = prefix_text.substr(name_start)

	# If the user is still typing a @target (no @target yet committed), offer
	# @target candidates filtered by the typed prefix.
	if not has_target and multi.begins_with("@"):
		var out: PackedStringArray = []
		for c in _target_candidates():
			if c.begins_with(multi): out.append(c)
		return out

	# If the last whitespace-separated chunk is a pure integer, the user is on
	# the optional [count] arg — no item-name suggestions.
	var last_space: int = multi.rfind(" ")
	if last_space >= 0 and multi.substr(last_space + 1).is_valid_int():
		return PackedStringArray()

	# Match item names by case-insensitive prefix.
	var matches: PackedStringArray = []
	var lower_multi: String = multi.to_lower()
	if "item_by_name" in ResourceManager:
		for n in ResourceManager.item_by_name:
			if String(n).to_lower().begins_with(lower_multi):
				matches.append(n)
	# When no @target is in play yet and the user hasn't typed anything, also
	# include @target candidates so Tab discovers either option from cold.
	if not has_target and multi.is_empty():
		matches.append_array(_target_candidates())
	matches.sort()
	return matches


func _complete_token() -> void:
	if _suggestion_matches.is_empty(): return
	var common := _longest_common_prefix(_suggestion_matches)
	var caret: int = _input_edit.caret_column
	var before: String = _input_edit.text.substr(0, _suggestion_token_start)
	var after: String = _input_edit.text.substr(caret)
	var replacement: String = common if not common.is_empty() else _suggestion_matches[0]
	if _suggestion_matches.size() == 1:
		replacement += " "
	_input_edit.text = before + replacement + after
	_input_edit.caret_column = (before + replacement).length()
	_refresh_suggestions()


func _longest_common_prefix(arr: PackedStringArray) -> String:
	if arr.is_empty(): return ""
	var prefix: String = arr[0]
	for s in arr:
		while not s.begins_with(prefix):
			prefix = prefix.substr(0, prefix.length() - 1)
			if prefix.is_empty(): return ""
	return prefix


# --- Command dispatch -------------------------------------------------------

func _run_line(line: String) -> void:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty(): return
	var name: String = parts[0].to_lower()
	# Alias expansion: replace the first token, keep the rest.
	if _aliases.has(name):
		var expansion: String = _aliases[name]
		var rest: String = "" if parts.size() == 1 else " " + " ".join(parts.slice(1))
		_run_line(expansion + rest)
		return
	var args: Array = Array(parts.slice(1))
	if not _commands.has(name):
		_print("[color=#ff8888]Unknown command '%s'. Try: help[/color]" % name)
		return
	var handler: Callable = _commands[name].handler
	var result: String = handler.call(args)
	if not result.is_empty():
		_print(result)


func _print(text: String) -> void:
	_output.append_text(text + "\n")


func _escape_bb(text: String) -> String:
	return text.replace("[", "[lb]")


# --- Built-in commands ------------------------------------------------------

func _register_commands() -> void:
	# Inspection / utility
	_register("help", "List commands or 'help <cmd>' for detail.", _cmd_help, _complete_command_name)
	_register("clear", "Clear the scrollback.", _cmd_clear)
	_register("echo", "Echo the rest of the line.", _cmd_echo)
	_register("state", "Snapshot server state: players, bots, enemies per map.", _cmd_state)
	_register("bots", "Detailed list of active bots (server-side only).", _cmd_bots)
	_register("find", "find <text> — list scrollback lines containing text.", _cmd_find)
	_register("snapshot", "Copy a full state snapshot to the clipboard.", _cmd_snapshot)
	_register("pause", "Toggle get_tree().paused. The console stays interactive.", _cmd_pause)
	_register("where", "where [@target] — print map + (x,y) for self or another peer.", _cmd_where, _complete_target_first)

	# Aliases
	_register("alias", "alias [name [expansion]] — define, list, or remove an alias.", _cmd_alias)

	# Self / targeted commands. Prefix '@<id|name>' targets another player or
	# bot (host-only); no prefix acts on the local player.
	_register("heal", "heal [@target] [amount=5]", _cmd_heal, _complete_target_first)
	_register("damage", "damage [@target] [amount=10]", _cmd_damage, _complete_target_first)
	_register("revive", "revive [@target]", _cmd_revive, _complete_target_first)
	_register("level", "level [@target] [n] — no n: +1 level", _cmd_level, _complete_target_first)
	_register("give", "give [@target] <item_name> [count=1]", _cmd_give, _complete_give)
	_register("gold", "gold [@target] <amount> — negative subtracts", _cmd_gold, _complete_target_first)
	_register("tp", "tp [@target] <map> | tp [@target] <x> <y>", _cmd_tp, _complete_tp)
	_register("come", "come <bot_id|name> — teleport a bot to your map", _cmd_come, _complete_bot_target)

	# Enemies (host-only; spawned enemy is server-side and visible to clients
	# via the normal MultiplayerSpawner path on the map).
	_register("enemy", "enemy spawn <name> [count] | enemy list", _cmd_enemy, _complete_enemy_args)

	# Bot subsystem passthroughs
	_register("watch-bot", "watch-bot <id|name|off> — camera-follow a bot. Host-only.", _cmd_watch_bot, _complete_bot_target)
	_register("navdraw", "Toggle the nav overlay; 'navdraw [graph|paths|info] [on|off]' for sub-layers.", _cmd_navdraw, _complete_navdraw)
	_register("bot", "Bot subcommands (spawn, despawn, list, ...). Host-only.", _cmd_bot, _complete_bot_args)
	_register("quest", "Quest subcommands. Host-only.", _cmd_quest)


func _register(name: String, desc: String, handler: Callable, completer: Callable = Callable()) -> void:
	_commands[name] = { "desc": desc, "handler": handler, "completer": completer }


# --- Help / utility ---------------------------------------------------------

func _cmd_help(args: Array) -> String:
	if args.is_empty():
		var lines: PackedStringArray = ["[b]Commands[/b]:"]
		var keys := _commands.keys()
		keys.sort()
		for k in keys:
			lines.append("  [color=#9fd]%s[/color] — %s" % [k, _commands[k].desc])
		if not _aliases.is_empty():
			lines.append("[b]Aliases[/b]:")
			for a in _aliases:
				lines.append("  [color=#fc9]%s[/color] -> %s" % [a, _aliases[a]])
		return "\n".join(lines)
	var name: String = args[0].to_lower()
	if _commands.has(name):
		return "[b]%s[/b] — %s" % [name, _commands[name].desc]
	if _aliases.has(name):
		return "[b]%s[/b] (alias) -> %s" % [name, _aliases[name]]
	return "[color=#ff8888]No such command: %s[/color]" % name


func _cmd_clear(_args: Array) -> String:
	_output.clear()
	return ""


func _cmd_echo(args: Array) -> String:
	return " ".join(PackedStringArray(args))


func _cmd_find(args: Array) -> String:
	if args.is_empty():
		return "Usage: find <text>"
	var needle: String = " ".join(PackedStringArray(args))
	var hits: PackedStringArray = []
	for line in _output.text.split("\n"):
		if line.findn(needle) >= 0:
			hits.append("  " + line)
	if hits.is_empty():
		return "(no matches for '%s')" % needle
	return "[b]Matches for '%s'[/b]:\n%s" % [needle, "\n".join(hits)]


func _cmd_pause(_args: Array) -> String:
	get_tree().paused = not get_tree().paused
	return "tree.paused = %s" % str(get_tree().paused)


func _cmd_where(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p): return "(no target)"
	var map_id: String = MapManager.get_player_map(p.player_id) if MapManager.has_method("get_player_map") else ""
	return "%s  @%s  (%d, %d)  exact:(%.2f, %.2f)" % [
		_target_label(t),
		map_id if not map_id.is_empty() else "?",
		int(p.global_position.x), int(p.global_position.y),
		p.global_position.x, p.global_position.y]


# --- State / bots -----------------------------------------------------------

func _cmd_state(_args: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("[b]Server state[/b]")
	lines.append("  is_server: %s   peer_id: %d" % [str(multiplayer.is_server()), multiplayer.get_unique_id()])
	var ne_count: int = get_tree().get_nodes_in_group("networked_entities").size()
	lines.append("  networked_entities: %d" % ne_count)

	var maps_seen: Dictionary = {}
	if "active_players" in PlayerManager:
		for peer_id in PlayerManager.active_players:
			var map_id: String = MapManager.get_player_map(peer_id) if MapManager.has_method("get_player_map") else ""
			var bucket: Dictionary = maps_seen.get(map_id, {"players": [], "bots": []})
			var entry := {"id": peer_id, "name": _peer_name(peer_id)}
			if BotManager.is_bot(peer_id):
				bucket.bots.append(entry)
			else:
				bucket.players.append(entry)
			maps_seen[map_id] = bucket

	if maps_seen.is_empty():
		lines.append("  (no active players)")
	else:
		for map_id in maps_seen:
			var b: Dictionary = maps_seen[map_id]
			var sample_id: int = b.players[0].id if not b.players.is_empty() else b.bots[0].id
			var alive_enemies: int = 0
			var map_node = MapManager.get_player_map_node(sample_id)
			if is_instance_valid(map_node):
				for enemy in get_tree().get_nodes_in_group("Enemies"):
					if not is_instance_valid(enemy): continue
					if not map_node.is_ancestor_of(enemy): continue
					if "health_component" in enemy and is_instance_valid(enemy.health_component):
						if enemy.health_component.is_dead: continue
					alive_enemies += 1
			lines.append("  [color=#9fd]%s[/color]   players:%d  bots:%d  enemies:%d" % [
				map_id if not map_id.is_empty() else "(none)",
				b.players.size(), b.bots.size(), alive_enemies])
			for p in b.players:
				lines.append("    P  %d  %s" % [p.id, p.name])
			for bot in b.bots:
				lines.append("    B  %d  %s" % [bot.id, bot.name])
	return "\n".join(lines)


func _cmd_bots(_args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]bots: host-only.[/color]"
	if BotManager.active_bots.is_empty():
		return "(no active bots)"
	var lines: PackedStringArray = ["[b]Active bots[/b]"]
	for bot_id in BotManager.active_bots:
		var info: Dictionary = BotManager.active_bots[bot_id]
		var node := PlayerManager.get_player_node(bot_id)
		var level := "?"
		var hp := "?"
		var action := "?"
		if is_instance_valid(node):
			if is_instance_valid(node.level_component):
				level = str(node.level_component.level)
			if is_instance_valid(node.health_component):
				hp = "%d/%d" % [node.health_component.current_health, node.health_component.max_health]
		var brain = BotManager.get_bot_brain(bot_id)
		if brain != null:
			action = brain.current_action
		lines.append("  [%d] %s  %s Lv.%s  hp:%s  @%s  action:%s" % [
			bot_id, info.get("username", "?"),
			Constants.ClassType.find_key(info.get("class_type", 0)),
			level, hp, info.get("map_id", "?"), action])
	return "\n".join(lines)


func _cmd_snapshot(_args: Array) -> String:
	var lines: PackedStringArray = []
	lines.append("=== debug snapshot @ %s ===" % Time.get_datetime_string_from_system(true))
	lines.append(_strip_bb(_cmd_state([])))
	var host := _local_player()
	if is_instance_valid(host):
		lines.append("")
		lines.append("local player: id=%d name=%s" % [host.player_id, host.username])
		if is_instance_valid(host.level_component):
			lines.append("  level=%d exp=%d/%d" % [
				host.level_component.level,
				host.level_component.experience,
				host.level_component.get_exp_to_next_level()])
		if is_instance_valid(host.health_component):
			lines.append("  hp=%d/%d" % [host.health_component.current_health, host.health_component.max_health])
		if is_instance_valid(host.player_inventory):
			lines.append("  gold=%d" % host.player_inventory.monies_amount)
	var text := "\n".join(lines)
	DisplayServer.clipboard_set(text)
	return "Snapshot copied to clipboard (%d chars)." % text.length()


# --- Aliases ----------------------------------------------------------------

func _cmd_alias(args: Array) -> String:
	if args.is_empty():
		if _aliases.is_empty():
			return "(no aliases; usage: alias <name> <expansion>)"
		var lines: PackedStringArray = ["[b]Aliases[/b]"]
		for a in _aliases:
			lines.append("  %s -> %s" % [a, _aliases[a]])
		return "\n".join(lines)
	var name: String = String(args[0]).to_lower()
	if args.size() == 1:
		if _aliases.has(name):
			_aliases.erase(name)
			return "Removed alias '%s'." % name
		return "(no such alias '%s'; provide an expansion to create one)" % name
	if _commands.has(name):
		return "[color=#ff8888]'%s' is a built-in command; choose a different alias name.[/color]" % name
	var expansion: String = " ".join(PackedStringArray(args).slice(1))
	_aliases[name] = expansion
	return "Alias '%s' -> '%s'" % [name, expansion]


# --- Targeted commands ------------------------------------------------------
##
## Convention: optional first arg '@<peer_id|player_name|bot_id|bot_name>'
## targets another player/bot. Targeting requires host (server) authority — the
## old per-player Debug component's actions were always local-self; that path
## still works (no @target → self).

## Parse an optional '@target' first arg. Returns:
##   { node: Node, remaining: Array, error: String, targeted: bool }
## error is non-empty when @target was supplied but couldn't be resolved.
func _resolve_target(args: Array) -> Dictionary:
	var self_node := _local_player()
	if args.is_empty() or not String(args[0]).begins_with("@"):
		return { "node": self_node, "remaining": args, "error": "", "targeted": false }
	if not multiplayer.is_server():
		return { "node": null, "remaining": args.slice(1), "error":
			"[color=#ff8888]@target requires host (server).[/color]", "targeted": true }
	var key: String = String(args[0]).substr(1)
	var node := _find_peer_node(key)
	var err := "" if is_instance_valid(node) else "[color=#ff8888]Target '%s' not found.[/color]" % key
	return { "node": node, "remaining": args.slice(1), "error": err, "targeted": true }


## Resolves @target text to a player/bot character node. Tries int id, then
## player username, then bot username.
func _find_peer_node(key: String) -> Node:
	if key.is_valid_int():
		var id := key.to_int()
		return PlayerManager.get_player_node(id)
	# Search real players.
	if "active_players" in PlayerManager:
		for pid in PlayerManager.active_players:
			var info: Dictionary = PlayerManager.active_players[pid]
			if String(info.get("username", "")).to_lower() == key.to_lower():
				return PlayerManager.get_player_node(pid)
	# Search bots.
	for bot_id in BotManager.active_bots:
		if String(BotManager.active_bots[bot_id].get("username", "")).to_lower() == key.to_lower():
			return PlayerManager.get_player_node(bot_id)
	return null


func _target_label(t: Dictionary) -> String:
	if not t.targeted: return "self"
	var n: Node = t.node
	if not is_instance_valid(n): return "?"
	return "@%d:%s" % [n.player_id if "player_id" in n else 0, n.username if "username" in n else "?"]


func _cmd_heal(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.health_component):
		return "(no health component)"
	var amount := 5 if t.remaining.is_empty() else String(t.remaining[0]).to_int()
	p.health_component.heal_damage.rpc(amount)
	return "Healed %s by %d." % [_target_label(t), amount]


func _cmd_damage(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.health_component):
		return "(no health component)"
	var amount := 10 if t.remaining.is_empty() else String(t.remaining[0]).to_int()
	p.health_component.take_damage.rpc(amount, null, true)
	return "Damaged %s by %d." % [_target_label(t), amount]


func _cmd_revive(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p): return "(no target)"
	p.respawn.rpc()
	return "Revive requested for %s." % _target_label(t)


func _cmd_level(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.level_component):
		return "(no level component)"
	var target_level := 0
	if t.remaining.is_empty():
		target_level = p.level_component.level + 1
	else:
		target_level = String(t.remaining[0]).to_int()
	if target_level < 1: return "Level must be >= 1."
	var start = p.level_component.level
	while p.level_component.level < target_level:
		p.level_component.add_exp.rpc(p.level_component.get_exp_to_next_level())
		if p.level_component.level == start and target_level > start: break
		start = p.level_component.level
	return "%s level %d -> %d." % [_target_label(t), start, p.level_component.level]


func _cmd_give(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	if t.remaining.is_empty(): return "Usage: give [@target] <item_name> [count]"
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.inventory_component):
		return "(no inventory component)"
	var rem: Array = t.remaining
	var count := 1
	var name_parts: Array = rem
	# If the last arg parses as an int, treat it as count.
	if rem.size() >= 2 and String(rem[rem.size() - 1]).is_valid_int():
		count = String(rem[rem.size() - 1]).to_int()
		name_parts = rem.slice(0, rem.size() - 1)
	var item_name := " ".join(PackedStringArray(name_parts))
	var item: ItemData = ResourceManager.get_item_by_name(item_name)
	if item == null:
		return "[color=#ff8888]No item named '%s'.[/color]" % item_name
	for i in count:
		p.inventory_component.add_item(item.item_id)
	return "Gave %s: %d x %s." % [_target_label(t), count, item.name]


func _cmd_gold(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	if t.remaining.is_empty(): return "Usage: gold [@target] <amount>"
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.player_inventory):
		return "(no player inventory)"
	var delta := String(t.remaining[0]).to_int()
	p.player_inventory.monies_amount = p.player_inventory.monies_amount + delta
	return "%s gold: %d (delta %d)." % [_target_label(t), p.player_inventory.monies_amount, delta]


func _cmd_tp(args: Array) -> String:
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	if t.remaining.is_empty(): return "Usage: tp [@target] <map> | tp [@target] <x> <y>"
	var p: Node = t.node
	if not is_instance_valid(p): return "(no target)"
	var rem: Array = t.remaining
	# Two numbers -> position teleport on current map. One token -> map change.
	if rem.size() >= 2 and String(rem[0]).is_valid_float() and String(rem[1]).is_valid_float():
		var pos := Vector2(String(rem[0]).to_float(), String(rem[1]).to_float())
		p.global_position = pos
		return "Teleported %s to %s." % [_target_label(t), str(pos)]
	var map_id := String(rem[0])
	MapManager.request_map_change(p.player_id, map_id)
	return "Map change requested for %s: %s." % [_target_label(t), map_id]


func _cmd_come(args: Array) -> String:
	if args.is_empty(): return "Usage: come <bot_id|name>"
	if not multiplayer.is_server(): return "[color=#ff8888]come: host-only.[/color]"
	var bot_id := _find_bot_id(String(args[0]))
	if bot_id == 0: return "Bot '%s' not found." % args[0]
	var host := _local_player()
	if not is_instance_valid(host): return "(no local player)"
	var host_map := MapManager.get_player_map(host.player_id)
	BotManager.active_bots[bot_id].map_id = host_map
	MapManager.request_map_change(bot_id, host_map)
	var bot_node := PlayerManager.get_player_node(bot_id)
	if is_instance_valid(bot_node):
		bot_node.global_position = host.global_position
	return "Bot %d coming to %s @ %s." % [bot_id, host_map, str(host.global_position)]


# --- Enemies ----------------------------------------------------------------

const ENEMY_SCENES_DIR := "res://scenes/NPC/"


func _cmd_enemy(args: Array) -> String:
	if args.is_empty():
		return "Usage: enemy spawn <name> [count] [@map] [x y] | enemy list"
	var sub: String = String(args[0]).to_lower()
	match sub:
		"list":
			var names: PackedStringArray = _list_enemy_scene_names()
			if names.is_empty(): return "(no enemy scenes in %s)" % ENEMY_SCENES_DIR
			return "[b]Enemy scenes[/b]:\n  " + "  ".join(names)
		"spawn":
			if not multiplayer.is_server():
				return "[color=#ff8888]enemy spawn: host-only.[/color]"
			if args.size() < 2: return "Usage: enemy spawn <name> [count] [@map] [x y]"
			return _do_enemy_spawn(args.slice(1))
		_:
			return "Usage: enemy spawn <name> [count] [@map] [x y] | enemy list"


## Parses 'enemy spawn' args (everything AFTER the literal 'spawn') in this order:
##   name [count] [@map] [x y]
## Defaults: count=1; map=host's current map; pos=in-front-of-host (40px in
## facing_direction). If @map is given without x/y, pos defaults to (0, 0).
func _do_enemy_spawn(args: Array) -> String:
	var name: String = String(args[0])
	var idx := 1
	var count := 1
	if idx < args.size() and String(args[idx]).is_valid_int():
		count = max(1, String(args[idx]).to_int())
		idx += 1
	var map_id: String = ""
	var map_explicit := false
	if idx < args.size() and String(args[idx]).begins_with("@"):
		map_id = String(args[idx]).substr(1)
		map_explicit = true
		idx += 1
	var pos: Vector2 = Vector2.ZERO
	var pos_explicit := false
	if idx + 1 < args.size() \
			and String(args[idx]).is_valid_float() \
			and String(args[idx + 1]).is_valid_float():
		pos = Vector2(String(args[idx]).to_float(), String(args[idx + 1]).to_float())
		pos_explicit = true

	var host := _local_player()
	if not is_instance_valid(host): return "(no local player)"

	# Resolve map: explicit @map, else host's current map.
	if not map_explicit:
		map_id = MapManager.get_player_map(host.player_id) if MapManager.has_method("get_player_map") else ""
		if map_id.is_empty(): return "[color=#ff8888]Host has no current map.[/color]"
	var map_node: Node = MapManager.active_maps.get(map_id, {}).get("scene_instance") \
		if "active_maps" in MapManager else null
	if not is_instance_valid(map_node):
		return "[color=#ff8888]Map '%s' is not loaded.[/color]" % map_id

	# Resolve position. Defaults: in-front-of-host if same map and no explicit map;
	# (0, 0) if @map was supplied without x/y; explicit x/y wins otherwise.
	if not pos_explicit:
		if map_explicit:
			pos = Vector2.ZERO
		else:
			var dir: float = 1.0
			if "facing_direction" in host:
				dir = -1.0 if host.facing_direction < 0 else 1.0
			pos = host.global_position + Vector2(40.0 * dir, 0.0)

	return _spawn_enemy_by_name(name, count, map_node, pos)


func _spawn_enemy_by_name(name: String, count: int, map_node: Node, base_pos: Vector2) -> String:
	var snake: String = name.to_snake_case().replace(" ", "_").to_lower()
	var path: String = ENEMY_SCENES_DIR + snake + ".tscn"
	if not ResourceLoader.exists(path):
		return "[color=#ff8888]No enemy scene '%s'. Try 'enemy list'.[/color]" % path
	var scene: PackedScene = load(path)
	if scene == null: return "[color=#ff8888]Failed to load %s.[/color]" % path
	var spawned := 0
	for i in count:
		var enemy = scene.instantiate()
		if enemy == null: continue
		map_node.add_child(enemy, true)
		if enemy is Node2D:
			# Stagger multiple spawns so they don't pile on a single pixel.
			enemy.global_position = base_pos + Vector2(i * 24.0, 0.0)
		if enemy.has_method("pool_reset"):
			enemy.pool_reset()
		spawned += 1
	return "Spawned %d x %s on '%s' at (%d, %d)." % [
		spawned, snake, map_node.name, int(base_pos.x), int(base_pos.y)]


func _list_enemy_scene_names() -> PackedStringArray:
	var out: PackedStringArray = []
	var dir := DirAccess.open(ENEMY_SCENES_DIR)
	if dir == null: return out
	for f in dir.get_files():
		if not f.ends_with(".tscn"): continue
		# Skip the generic template and NPCs that aren't enemies (merchant, job advancement).
		var base := f.get_basename()
		if base == "enemy_template" or base.ends_with("_npc"): continue
		out.append(base)
	out.sort()
	return out


# --- Bot / quest passthroughs ----------------------------------------------

func _cmd_watch_bot(args: Array) -> String:
	if args.is_empty(): return "Usage: watch-bot <id|name|off>"
	return BotManager.handle_command(["watch", args[0]] as Array, multiplayer.get_unique_id())


func _cmd_navdraw(args: Array) -> String:
	if args.is_empty():
		return BotManager.handle_command(["debugdraw"] as Array, multiplayer.get_unique_id())
	var first: String = String(args[0]).to_lower()
	if first in ["on", "off", "true", "false", "1", "0"]:
		return BotManager.handle_command(["debugdraw", first] as Array, multiplayer.get_unique_id())
	if first not in ["graph", "paths", "info"]:
		return "Usage: navdraw [on|off|graph|paths|info] [on|off]"
	var dd = BotManager.get_debug_draw()
	if dd == null:
		return "[color=#ff8888]navdraw: overlay not enabled — run 'navdraw' first.[/color]"
	var want: bool
	if args.size() >= 2:
		want = String(args[1]).to_lower() in ["on", "true", "1"]
	else:
		match first:
			"graph": want = not dd.show_graph
			"paths": want = not dd.show_paths
			"info":  want = not dd.show_bot_info
	match first:
		"graph":
			dd.show_graph = want
			_layer_graph_check.set_pressed_no_signal(want)
		"paths":
			dd.show_paths = want
			_layer_paths_check.set_pressed_no_signal(want)
		"info":
			dd.show_bot_info = want
			_layer_info_check.set_pressed_no_signal(want)
	return "navdraw.%s = %s" % [first, "on" if want else "off"]


func _cmd_bot(args: Array) -> String:
	return BotManager.handle_command(args, multiplayer.get_unique_id())


func _cmd_quest(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]quest: host-only.[/color]"
	if not QuestManager.has_method("handle_quest_command"):
		return "QuestManager has no handle_quest_command method."
	var line := "/quest " + " ".join(PackedStringArray(args))
	QuestManager.handle_quest_command(line, multiplayer.get_unique_id())
	return "[color=#aaaaaa](quest reply routed to chat)[/color]"


# --- Completers -------------------------------------------------------------

func _complete_command_name(_p: PackedStringArray, _t: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for k in _commands.keys(): out.append(k)
	for k in _aliases.keys(): out.append(k)
	return out


## All known @target candidates: real player names and bot ids/names.
func _target_candidates() -> PackedStringArray:
	var out: PackedStringArray = []
	if "active_players" in PlayerManager:
		for pid in PlayerManager.active_players:
			var info: Dictionary = PlayerManager.active_players[pid]
			out.append("@%d" % pid)
			var pname: String = info.get("username", "")
			if not pname.is_empty(): out.append("@%s" % pname)
	for bot_id in BotManager.active_bots:
		out.append("@%d" % bot_id)
		var bname: String = BotManager.active_bots[bot_id].get("username", "")
		if not bname.is_empty(): out.append("@%s" % bname)
	return out


## Completer for commands whose first arg is an optional '@target'.
func _complete_target_first(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty(): return _target_candidates()
	return PackedStringArray()


## Completer for 'give' — @target candidates as the first arg, item names after.
func _complete_give(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		var out: PackedStringArray = _target_candidates()
		if "item_by_name" in ResourceManager:
			for n in ResourceManager.item_by_name: out.append(n)
		return out
	# If the first prior arg is a @target, the next slot is the item name.
	if String(prior_args[0]).begins_with("@") and prior_args.size() == 1:
		return _complete_item_name(prior_args, _t)
	return PackedStringArray()


## Completer for 'tp' — @target candidates or map IDs as the first arg.
func _complete_tp(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		var out: PackedStringArray = _target_candidates()
		out.append_array(_map_id_candidates())
		return out
	if String(prior_args[0]).begins_with("@") and prior_args.size() == 1:
		return _map_id_candidates()
	return PackedStringArray()


func _complete_item_name(_p: PackedStringArray, _t: String) -> PackedStringArray:
	var out: PackedStringArray = []
	if "item_by_name" in ResourceManager:
		for n in ResourceManager.item_by_name:
			out.append(n)
	return out


func _map_id_candidates() -> PackedStringArray:
	var out: PackedStringArray = []
	if MapManager.has_method("get_all_map_ids"):
		out = MapManager.get_all_map_ids()
	elif "maps" in MapManager:
		out = PackedStringArray(MapManager.maps.keys())
	return out


func _complete_map_name(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if not prior_args.is_empty(): return PackedStringArray()
	return _map_id_candidates()


func _complete_enemy_args(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["spawn", "list"])
	if prior_args[0].to_lower() != "spawn": return PackedStringArray()
	# prior_args[1] is the enemy name; subsequent slots could be count or @map.
	if prior_args.size() == 1:
		return _list_enemy_scene_names()
	# After the name, suggest @<map_id> for whichever slot the user is in next.
	var maps: PackedStringArray = _map_id_candidates()
	var out: PackedStringArray = []
	for m in maps: out.append("@" + m)
	return out


func _complete_bot_target(_p: PackedStringArray, _t: String) -> PackedStringArray:
	var out: PackedStringArray = ["off"]
	for bot_id in BotManager.active_bots:
		out.append(str(bot_id))
		var name: String = BotManager.active_bots[bot_id].get("username", "")
		if not name.is_empty(): out.append(name)
	return out


func _complete_navdraw(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["on", "off", "graph", "paths", "info"])
	if prior_args[0].to_lower() in ["graph", "paths", "info"]:
		return PackedStringArray(["on", "off"])
	return PackedStringArray()


func _complete_bot_args(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	const BOT_SUBS := ["spawn", "despawn", "despawn_all", "list", "teleport",
		"set_level", "party", "travel", "inspect", "trade", "navgraph",
		"navpath", "debugdraw", "stats", "watch", "reload_config"]
	if prior_args.is_empty():
		var out: PackedStringArray = []
		for s in BOT_SUBS: out.append(s)
		return out
	var sub: String = prior_args[0].to_lower()
	match sub:
		"spawn":
			if prior_args.size() == 2:
				var out: PackedStringArray = []
				for c in SPAWN_CLASSES: out.append(c)
				return out
			return PackedStringArray(["random"]) if prior_args.size() == 1 else PackedStringArray()
		"despawn", "set_level", "teleport", "watch", "stats", "inspect", "trade", "navgraph", "navpath":
			var out: PackedStringArray = []
			for bot_id in BotManager.active_bots:
				out.append(str(bot_id))
			if sub == "watch": out.append("off")
			return out
		"party":
			return PackedStringArray(["list", "info", "kick"])
		"travel":
			return PackedStringArray(["info"])
		"debugdraw":
			return PackedStringArray(["on", "off"])
	return PackedStringArray()


# --- Helpers ----------------------------------------------------------------

func _local_player() -> Node:
	if PlayerManager.has_method("get_player_node"):
		return PlayerManager.get_player_node(multiplayer.get_unique_id())
	return null


func _find_bot_id(target: String) -> int:
	if target.is_valid_int():
		var id := target.to_int()
		if id in BotManager.active_bots: return id
	for bot_id in BotManager.active_bots:
		if String(BotManager.active_bots[bot_id].get("username", "")).to_lower() == target.to_lower():
			return bot_id
	return 0


func _peer_name(peer_id: int) -> String:
	if BotManager.is_bot(peer_id):
		return BotManager.active_bots.get(peer_id, {}).get("username", "bot_%d" % peer_id)
	if PlayerManager.has_method("get_player_info"):
		var info = PlayerManager.get_player_info(peer_id)
		return info.get("username", "peer_%d" % peer_id)
	return "peer_%d" % peer_id


func _strip_bb(text: String) -> String:
	# Crude BBCode strip for clipboard output: drop anything between [ and ].
	var out := ""
	var in_tag := false
	for c in text:
		if c == "[": in_tag = true
		elif c == "]": in_tag = false
		elif not in_tag: out += c
	return out


# --- History persistence ----------------------------------------------------

func _load_history() -> void:
	if not FileAccess.file_exists(HISTORY_FILE): return
	var f := FileAccess.open(HISTORY_FILE, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Array:
		for line in parsed:
			if line is String:
				_history.append(line)


func _save_history() -> void:
	var f := FileAccess.open(HISTORY_FILE, FileAccess.WRITE)
	if f == null: return
	f.store_string(JSON.stringify(_history))
	f.close()
