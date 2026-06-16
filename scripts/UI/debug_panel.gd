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

const SPAWN_CLASSES := ["SWORD", "BOW", "STAFF", "DAGGER"]
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
var _spawn_overlay: Node2D = null   # live DebugSpawnOverlay (the `spawns` command)


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
	row.add_child(_make_button("Roster", func(): _run_line("botdock")))
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
	BotManager.set_debug_draw_layer(which, on)


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
		for cmd in keys:
			if cmd.begins_with(token):
				names.append(cmd)
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

## Commands that act purely on the local console/UI (scrollback, aliases, the
## panel's own widgets/overlay) — never routed to the server, even from a client.
## Everything else IS routed when run on a client, so authoritative/inspection dev
## commands work for clients too (see _run_line / _run_on_server).
const LOCAL_ONLY_CMDS: Array = ["help", "clear", "echo", "find", "alias", "snapshot", "pause", "botdock", "navdraw"]

## When non-zero, the server is executing a command on behalf of this client peer,
## so _acting_id()/_local_player() resolve to THAT player instead of the host.
var _acting_peer_id: int = 0

## The peer the current command acts as: the routed client when the server is
## executing on its behalf, otherwise this machine's own peer.
func _acting_id() -> int:
	return _acting_peer_id if _acting_peer_id != 0 else multiplayer.get_unique_id()


func _run_line(line: String) -> void:
	# On a client, authoritative/inspection commands run on the SERVER as this
	# player — the host-only guards inside each handler are then satisfied and the
	# command mutates the correct character. Pure-console commands stay local.
	if not multiplayer.is_server() and _needs_server(line):
		_run_on_server.rpc_id(1, line)
		return
	var out: String = _eval_line(line)
	if not out.is_empty():
		_print(out)


## Runs one command line (resolving one alias hop) and RETURNS its output instead
## of printing, so the server can ship the result back to a remote client.
func _eval_line(line: String) -> String:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty(): return ""
	var cmd_name: String = parts[0].to_lower()
	# Alias expansion: replace the first token, keep the rest.
	if _aliases.has(cmd_name):
		var expansion: String = _aliases[cmd_name]
		var rest: String = "" if parts.size() == 1 else " " + " ".join(parts.slice(1))
		return _eval_line(expansion + rest)
	var args: Array = Array(parts.slice(1))
	if not _commands.has(cmd_name):
		return "[color=#ff8888]Unknown command '%s'. Try: help[/color]" % cmd_name
	var result: String = _commands[cmd_name].handler.call(args)
	return result


## Whether `line`'s command should run on the server (not in LOCAL_ONLY_CMDS).
func _needs_server(line: String) -> bool:
	var parts: PackedStringArray = line.split(" ", false)
	if parts.is_empty(): return false
	var cmd_name: String = parts[0].to_lower()
	# Resolve one alias hop so the routing decision matches the real command.
	if _aliases.has(cmd_name):
		var exp: PackedStringArray = String(_aliases[cmd_name]).split(" ", false)
		if not exp.is_empty(): cmd_name = exp[0].to_lower()
	return not LOCAL_ONLY_CMDS.has(cmd_name)


## [Client -> Server] Execute a debug command on the server in the CALLING
## client's context, then return its output to that client. The server is where
## all the host-only / server-authoritative dev commands actually take effect.
@rpc("any_peer", "call_remote", "reliable")
func _run_on_server(line: String) -> void:
	if not multiplayer.is_server():
		return
	var sender: int = multiplayer.get_remote_sender_id()
	_acting_peer_id = sender
	var out: String = _eval_line(line)
	_acting_peer_id = 0
	_run_result_to_client.rpc_id(sender, out)


## [Server -> requesting client] Print the routed command's output.
@rpc("authority", "call_remote", "reliable")
func _run_result_to_client(output: String) -> void:
	if not output.is_empty():
		_print(output)


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
	_register("mastery", "mastery [@target] <sword|bow|staff|dagger|0-3> [n=1] — grants enough XP to level that discipline's mastery N times.", _cmd_mastery, _complete_mastery)
	_register("upgrade", "upgrade list | upgrade buy <upgrade_id> — PR 6 ability-upgrade testing (host-only).", _cmd_upgrade, _complete_upgrade)
	_register("respec", "respec <sword|bow|staff|dagger|all> — refund a discipline's spent ability points + upgrades (host-only).", _cmd_respec, _complete_respec)
	_register("give", "give [@target] <item_name> [count=1]", _cmd_give, _complete_give)
	_register("gold", "gold [@target] <amount> — negative subtracts", _cmd_gold, _complete_target_first)
	_register("tp", "tp [@target] <map> | tp [@target] <x> <y>", _cmd_tp, _complete_tp)
	_register("come", "come <bot_id|name> — teleport a bot to your map", _cmd_come, _complete_bot_target)
	_register("goto", "goto <bot_id|name> — teleport yourself to a bot (the inverse of come)", _cmd_goto, _complete_bot_target)
	_register("botdock", "Open the live bot roster window (host-only).", _cmd_botdock)

	# Enemies (host-only; spawned enemy is server-side and visible to clients
	# via the normal MultiplayerSpawner path on the map).
	_register("enemy", "enemy spawn <name> [count] | enemy list", _cmd_enemy, _complete_enemy_args)
	_register("spawns", "spawns [on|off] — toggle the spawn-point + density overlay; 'spawns report' for a text breakdown (ADR 0015).", _cmd_spawns, _complete_spawns)

	# Bot subsystem passthroughs
	_register("watch-bot", "watch-bot <id|name|off> — camera-follow a bot. Host-only.", _cmd_watch_bot, _complete_bot_target)
	_register("navdraw", "Toggle the nav overlay; 'navdraw [graph|paths|info] [on|off]' for sub-layers.", _cmd_navdraw, _complete_navdraw)
	_register("bot", "Bot subcommands (spawn, despawn, list, ...). Host-only.", _cmd_bot, _complete_bot_args)
	_register("quest", "Quest subcommands (list, accept, progress, abandon, track). Host-only.", _cmd_quest, _complete_quest_args)
	_register("zone", "zone [name] — list/spawn a ground-zone for visual inspection (no damage). Host-only.", _cmd_zone, _complete_zone_args)

	# Pair-build testing
	_register("pairtest", "pairtest <primary> <secondary> — L100 pair build: max mastery + abilities + upgrades, Astral (L93) gear, curated synergy hotbar, teleport to the Warlord. Host-only.", _cmd_pairtest, _complete_pairtest)


func _register(cmd_name: String, desc: String, handler: Callable, completer: Callable = Callable()) -> void:
	_commands[cmd_name] = { "desc": desc, "handler": handler, "completer": completer }


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
	var cmd_name: String = args[0].to_lower()
	if _commands.has(cmd_name):
		return "[b]%s[/b] — %s" % [cmd_name, _commands[cmd_name].desc]
	if _aliases.has(cmd_name):
		return "[b]%s[/b] (alias) -> %s" % [cmd_name, _aliases[cmd_name]]
	return "[color=#ff8888]No such command: %s[/color]" % cmd_name


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
	var alias_name: String = String(args[0]).to_lower()
	if args.size() == 1:
		if _aliases.has(alias_name):
			_aliases.erase(alias_name)
			return "Removed alias '%s'." % alias_name
		return "(no such alias '%s'; provide an expansion to create one)" % alias_name
	if _commands.has(alias_name):
		return "[color=#ff8888]'%s' is a built-in command; choose a different alias name.[/color]" % alias_name
	var expansion: String = " ".join(PackedStringArray(args).slice(1))
	_aliases[alias_name] = expansion
	return "Alias '%s' -> '%s'" % [alias_name, expansion]


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


## mastery [@target] <discipline> [n=1] — adds N mastery levels to a
## specific discipline by granting just enough XP per loop iteration to
## tick the level over. Routes through grant_mastery_xp_server so all the
## downstream signals (mastery_level_changed → ability point grant, stat
## recalc) fire naturally. Host-only because mastery XP grants are
## server-authoritative.
func _cmd_mastery(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]mastery is host-only (server-authoritative).[/color]"
	var t := _resolve_target(args)
	if not t.error.is_empty(): return t.error
	var p: Node = t.node
	if not is_instance_valid(p) or not is_instance_valid(p.weapon_mastery_component):
		return "(no weapon mastery component)"
	if t.remaining.is_empty():
		return "Usage: mastery [@target] <sword|bow|staff|dagger|0-3> [n=1]"

	var disc: int = _parse_discipline_arg(String(t.remaining[0]))
	if disc < 0:
		return "[color=#ff8888]Unknown discipline '%s'. Use sword/bow/staff/dagger or 0-3.[/color]" % String(t.remaining[0])

	var n: int = 1
	if t.remaining.size() >= 2:
		var parsed: int = String(t.remaining[1]).to_int()
		if parsed > 0:
			n = parsed

	var wm = p.weapon_mastery_component
	var start_level: int = wm.get_mastery_level(disc)
	for i in range(n):
		var cur: int = wm.get_mastery_level(disc)
		if cur >= WeaponMasteryComponent.MASTERY_CAP:
			break
		wm.grant_mastery_xp_server(disc, wm.get_xp_to_next_level(disc))
	var end_level: int = wm.get_mastery_level(disc)
	var disc_name: String = _discipline_label(disc)
	return "%s %s mastery %d -> %d." % [_target_label(t), disc_name, start_level, end_level]


## Parses a discipline argument from either a name (sword/bow/staff/dagger,
## case-insensitive) or an int (0-3). Returns the ClassType enum value, or
## -1 if unrecognized.
func _parse_discipline_arg(s: String) -> int:
	if s.is_valid_int():
		var v: int = s.to_int()
		if v >= 0 and v <= 3:
			return v
		return -1
	match s.to_lower():
		"sword": return Constants.ClassType.SWORD
		"bow": return Constants.ClassType.BOW
		"staff": return Constants.ClassType.STAFF
		"dagger": return Constants.ClassType.DAGGER
	return -1


## upgrade list | upgrade buy <upgrade_id> — PR 6 ability-upgrade testing.
## Operates on the local player. Host-only (purchase is server-authoritative).
func _cmd_upgrade(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]upgrade is host-only (server-authoritative).[/color]"
	var p: Node = _local_player()
	if not is_instance_valid(p) or not is_instance_valid(p.ability_component):
		return "(no ability component)"
	var ac = p.ability_component

	var sub: String = String(args[0]).to_lower() if not args.is_empty() else "list"

	if sub == "list":
		var lines: PackedStringArray = ["[b]Ability upgrades[/b] (learned abilities only):"]
		for ability_id in ResourceManager.ability_data:
			var ability: AbilityData = ResourceManager.ability_data[ability_id]
			if ability == null or ability.upgrades == null or ability.upgrades.is_empty():
				continue
			# Only show abilities the player has learned (level >= 1).
			if int(ac.get_ability_level(ability_id) if ac.has_method("get_ability_level") else 0) <= 0:
				continue
			lines.append("[color=#e6c95c]%s[/color]:" % ability.ability_name)
			for up in ability.upgrades:
				if up == null:
					continue
				var status: String = "owned" if ac.has_upgrade(ability_id, up.upgrade_id) else "T%d %dpt" % [up.tier, up.point_cost]
				lines.append("  %s  [color=#9fcaff]%s[/color]  (%s)" % [up.upgrade_id, up.upgrade_name, status])
		if lines.size() == 1:
			lines.append("  (none — learn a sword ability with upgrades first, e.g. Crescent Cleave)")
		return "\n".join(lines)

	if sub == "buy":
		if args.size() < 2:
			return "Usage: upgrade buy <upgrade_id>"
		var upgrade_id: String = String(args[1])
		# Resolve the owning ability by scanning all abilities for the id.
		for ability_id in ResourceManager.ability_data:
			var ability: AbilityData = ResourceManager.ability_data[ability_id]
			if ability == null or ability.upgrades == null:
				continue
			for up in ability.upgrades:
				if up != null and up.upgrade_id == upgrade_id:
					var check: Dictionary = ac.can_purchase_upgrade(ability_id, upgrade_id)
					if not check.ok:
						return "[color=#ff8888]Cannot buy '%s': %s[/color]" % [upgrade_id, String(check.reason)]
					ac.purchase_upgrade(ability_id, upgrade_id)
					return "Purchased [color=#9fcaff]%s[/color] on %s." % [up.upgrade_name, ability.ability_name]
		return "[color=#ff8888]Unknown upgrade_id '%s'.[/color]" % upgrade_id

	return "Usage: upgrade list | upgrade buy <upgrade_id>"


## respec <sword|bow|staff|dagger|all> — refund a discipline's spent ability
## points (levels above the free starter + upgrade costs) on the local player.
## Host-only (server-authoritative).
func _cmd_respec(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]respec is host-only (server-authoritative).[/color]"
	var p: Node = _local_player()
	if not is_instance_valid(p) or not is_instance_valid(p.ability_component):
		return "(no ability component)"
	if args.is_empty():
		return "Usage: respec <sword|bow|staff|dagger|all>"
	var ac = p.ability_component

	var target: String = String(args[0]).to_lower()
	var keys: Array[String] = []
	if target == "all":
		keys = ["sword", "bow", "staff", "dagger"]
	elif target in ["sword", "bow", "staff", "dagger"]:
		keys = [target]
	else:
		return "[color=#ff8888]Unknown discipline '%s'. Use sword/bow/staff/dagger or all.[/color]" % target

	var results: PackedStringArray = []
	for key in keys:
		var before: int = ac.get_available_points_for_discipline(key)
		ac.respec_discipline(key)
		var after: int = ac.get_available_points_for_discipline(key)
		results.append("%s: %d → %d pts" % [key, before, after])
	return "Respec complete — " + ", ".join(results)


func _discipline_label(disc: int) -> String:
	match disc:
		Constants.ClassType.SWORD: return "Sword"
		Constants.ClassType.BOW: return "Bow"
		Constants.ClassType.STAFF: return "Staff"
		Constants.ClassType.DAGGER: return "Dagger"
	return "Unknown"


## Completer for `mastery` command. Suggests @target candidates and/or
## discipline names depending on which slot the user is typing into.
## Signature matches the other completers in this file:
## (prior_args: PackedStringArray, _t: String) -> PackedStringArray.
func _complete_mastery(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	var disciplines: PackedStringArray = PackedStringArray(["sword", "bow", "staff", "dagger"])
	if prior_args.is_empty():
		# First slot can be either @target or discipline.
		var out: PackedStringArray = _target_candidates()
		out.append_array(disciplines)
		return out
	# After an @target slot, the next slot is the discipline.
	if String(prior_args[0]).begins_with("@") and prior_args.size() == 1:
		return disciplines
	return PackedStringArray()


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


## Opens (or focuses) the live bot roster window. Lazily creates the dock the
## first time it is opened and parents it under the host's MoveableWindows
## container, matching how BotInspectWindow is hosted.
var _bot_dock: BotDock = null

func _cmd_botdock(_args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]botdock: host-only (bots are server-side).[/color]"
	if not is_instance_valid(_bot_dock):
		_bot_dock = BotDock.create()
		# Mount in the persistent LocalPlayerUI (ADR 0009 Stage B); fall back to /root.
		var parent: Node = get_tree().root
		var movable = MapManager.get_local_ui_moveable_windows()
		if is_instance_valid(movable):
			parent = movable
		parent.add_child(_bot_dock)
		# Center-ish on first open.
		var vp_size := get_viewport().get_visible_rect().size
		_bot_dock.global_position = (vp_size - _bot_dock.size) * 0.5
	_bot_dock.visible = true
	_bot_dock.move_to_front()
	return "Bot roster opened."


func _cmd_come(args: Array) -> String:
	if args.is_empty(): return "Usage: come <bot_id|name>"
	if not multiplayer.is_server(): return "[color=#ff8888]come: host-only.[/color]"
	var bot_id := _find_bot_id(String(args[0]))
	if bot_id == 0: return "Bot '%s' not found." % args[0]
	var host := _local_player()
	if not is_instance_valid(host): return "(no local player)"
	var host_map := MapManager.get_player_map(host.player_id)
	# Same map: just teleport the existing body. Different map: trigger a real
	# map change (which respawns the bot on the new map; bail without setting
	# position because the new body isn't live yet). Calling request_map_change
	# for the same map causes an unwanted respawn-in-place that leaves a ghost.
	var bot_map: String = MapManager.get_player_map(bot_id)
	if bot_map != host_map:
		BotManager.active_bots[bot_id].map_id = host_map
		MapManager.request_map_change(bot_id, host_map)
		return "Bot %d travelling to %s." % [bot_id, host_map]
	var bot_node := PlayerManager.get_player_node(bot_id)
	if is_instance_valid(bot_node):
		bot_node.global_position = host.global_position
	return "Bot %d teleported to %s." % [bot_id, str(host.global_position)]


## The inverse of `come`: move the HOST to the bot's map and position. The
## host takes the reparent fast path (ADR 0009 Stage C), so its node is live
## right after request_map_change; the recreate fallback lands at the spawn
## point instead (still on the right map).
func _cmd_goto(args: Array) -> String:
	if args.is_empty(): return "Usage: goto <bot_id|name>"
	if not multiplayer.is_server(): return "[color=#ff8888]goto: host-only.[/color]"
	var bot_id := _find_bot_id(String(args[0]))
	if bot_id == 0: return "Bot '%s' not found." % args[0]
	var bot_node := PlayerManager.get_player_node(bot_id)
	if not is_instance_valid(bot_node): return "Bot %d has no live body." % bot_id
	var bot_map: String = MapManager.get_player_map(bot_id)
	if bot_map.is_empty(): return "Bot %d has no current map." % bot_id
	var host_id := _acting_id()
	if MapManager.get_player_map(host_id) != bot_map:
		MapManager.request_map_change(host_id, bot_map)
	var host := PlayerManager.get_player_node(host_id)
	if is_instance_valid(host) and is_instance_valid(bot_node) \
			and MapManager.get_player_map(host_id) == bot_map:
		host.global_position = bot_node.global_position
		host.reset_physics_interpolation()
		return "Teleported to bot %d on '%s'." % [bot_id, bot_map]
	return "Travelling to '%s' (landed at spawn — recreate path)." % bot_map


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
	var enemy_name: String = String(args[0])
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

	return _spawn_enemy_by_name(enemy_name, count, map_node, pos)


func _spawn_enemy_by_name(enemy_name: String, count: int, map_node: Node, base_pos: Vector2) -> String:
	var snake: String = enemy_name.to_snake_case().replace(" ", "_").to_lower()
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
	return BotManager.handle_command(["watch", args[0]] as Array, _acting_id())


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
	BotManager.set_debug_draw_layer(first, want)
	match first:
		"graph": _layer_graph_check.set_pressed_no_signal(want)
		"paths": _layer_paths_check.set_pressed_no_signal(want)
		"info":  _layer_info_check.set_pressed_no_signal(want)
	return "navdraw.%s = %s" % [first, "on" if want else "off"]


# --- Spawn density / spawn-point overlay (ADR 0015) -------------------------

func _cmd_spawns(args: Array) -> String:
	if not args.is_empty() and String(args[0]).to_lower() in ["report", "list", "r"]:
		return _spawns_report()

	var want: bool
	if args.is_empty():
		want = not is_instance_valid(_spawn_overlay)
	else:
		var a := String(args[0]).to_lower()
		if a in ["on", "true", "1"]:
			want = true
		elif a in ["off", "false", "0"]:
			want = false
		else:
			return "Usage: spawns [on|off|report]"

	if not want:
		if is_instance_valid(_spawn_overlay):
			_spawn_overlay.queue_free()
		_spawn_overlay = null
		return "spawns overlay = off."

	if is_instance_valid(_spawn_overlay):
		return "spawns overlay already on. ('spawns report' for a text breakdown.)"
	var map = MapManager.current_map_instance
	if not is_instance_valid(map):
		return "[color=#ff8888]spawns: no current map to draw on.[/color]"
	_spawn_overlay = (load("res://scripts/UI/debug_spawn_overlay.gd") as GDScript).new()
	map.add_child(_spawn_overlay)
	return "spawns overlay = on — spawn-point markers + live density per spawner. 'spawns report' for text."


func _spawns_report() -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]spawns report: host-only (density is server-side). The overlay still shows markers on a client.[/color]"
	var map_id: String = MapManager.current_map_id
	if map_id == "":
		map_id = MapManager.get_player_map(_acting_id())
	var s: Dictionary = MapManager.get_map_population_summary(map_id)
	if s.is_empty():
		return "spawns: no current map."
	var spawners: Array = s.spawners
	if spawners.is_empty():
		return "spawns: no spawners on '%s'." % map_id

	var map_cap := int(s.map_cap)
	var total_alive := int(s.total_alive)
	# The headline: ONE map-wide cap across all spawn points (ADR 0015), so the
	# 75%->100% occupancy ramp is meaningful even with small per-spawner pools.
	var lines: PackedStringArray = [
		"[b]Spawn density — %s[/b]   occ:%d" % [map_id, int(s.occupants)],
		"  [b]MAP[/b] %s  [b]%d/%d[/b] alive  (pool %d)" % [
			_density_bar(total_alive, map_cap), total_alive, map_cap, int(s.total_pool)],
	]
	for r in spawners:
		var excluded: bool = r.get("excluded", false)
		var tag: String = "  [color=#caa]always-full[/color]" if excluded else ""
		lines.append("    [color=#9fd]%s[/color]  %d/%d  (%d pts)%s" % [
			String(r.get("name", "?")), int(r.get("alive", 0)), int(r.get("pool", 0)),
			r.get("spawn_locations", []).size(), tag])
	return "\n".join(lines)


## A tiny [####----] fill bar for alive-vs-capacity, color-graded by fullness.
func _density_bar(alive: int, cap: int) -> String:
	var width := 10
	var filled := 0 if cap <= 0 else clampi(int(round(float(alive) / float(cap) * width)), 0, width)
	var frac := 0.0 if cap <= 0 else float(alive) / float(cap)
	var color := "#7fd97f" if frac < 0.9 else ("#e8d24a" if frac <= 1.0 else "#e87a5a")
	return "[color=%s]%s%s[/color]" % [color, "█".repeat(filled), "░".repeat(width - filled)]


func _complete_spawns(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["on", "off", "report"])
	return PackedStringArray()


func _cmd_bot(args: Array) -> String:
	return BotManager.handle_command(args, _acting_id())


func _cmd_quest(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]quest: host-only.[/color]"
	if not QuestManager.has_method("handle_quest_command"):
		return "QuestManager has no handle_quest_command method."
	var line := "/quest " + " ".join(PackedStringArray(args))
	QuestManager.handle_quest_command(line, _acting_id())
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


## Completer for 'upgrade' — list/buy, then upgrade ids for buy.
func _complete_upgrade(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["list", "buy"])
	if prior_args[0].to_lower() == "buy" and prior_args.size() == 1:
		var out: PackedStringArray = []
		if "ability_data" in ResourceManager:
			for ability_id in ResourceManager.ability_data:
				var ability: AbilityData = ResourceManager.ability_data[ability_id]
				if ability == null or ability.upgrades == null:
					continue
				for up in ability.upgrades:
					if up != null:
						out.append(up.upgrade_id)
		out.sort()
		return out
	return PackedStringArray()


## Completer for 'respec' — disciplines plus 'all' (no @target: self-only).
func _complete_respec(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if not prior_args.is_empty():
		return PackedStringArray()
	return PackedStringArray(["sword", "bow", "staff", "dagger", "all"])


## Completer for 'quest' — subcommands, then quest ids where one is expected.
func _complete_quest_args(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["list", "accept", "progress", "abandon", "track"])
	if prior_args.size() == 1 and prior_args[0].to_lower() in ["accept", "abandon", "track"]:
		var out: PackedStringArray = []
		if "_quests" in QuestManager:
			for quest_id in QuestManager._quests:
				out.append(quest_id)
		out.sort()
		return out
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
	# MAP_SCENES is the canonical map registry — the previous probes
	# (get_all_map_ids() / a `maps` property) matched nothing, so every map
	# completion silently returned empty.
	var out: PackedStringArray = []
	if "MAP_SCENES" in MapManager:
		for map_id in MapManager.MAP_SCENES:
			out.append(map_id)
	out.sort()
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
		var bot_name: String = BotManager.active_bots[bot_id].get("username", "")
		if not bot_name.is_empty(): out.append(bot_name)
	return out


func _complete_navdraw(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.is_empty():
		return PackedStringArray(["on", "off", "graph", "paths", "info"])
	if prior_args[0].to_lower() in ["graph", "paths", "info"]:
		return PackedStringArray(["on", "off"])
	return PackedStringArray()


func _complete_bot_args(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	const BOT_SUBS := ["spawn", "despawn", "despawn_all", "list", "roster", "teleport",
		"set_level", "personality", "say", "emote", "rep", "party",
		"follow", "stay", "free", "churn", "banter", "travel", "inspect",
		"trade", "navgraph", "navpath", "debugdraw", "stats", "watch", "reload_config"]
	if prior_args.is_empty():
		var out: PackedStringArray = []
		for s in BOT_SUBS: out.append(s)
		return out
	var sub: String = prior_args[0].to_lower()
	match sub:
		"spawn":
			if prior_args.size() == 1:
				return PackedStringArray(["random"])
			if prior_args.size() == 2:
				var out: PackedStringArray = []
				for c in SPAWN_CLASSES: out.append(c)
				return out
			if prior_args.size() == 3:
				return _map_id_candidates()
			return PackedStringArray()
		"teleport":
			if prior_args.size() == 1:
				return _bot_name_candidates()
			if prior_args.size() == 2:
				return _map_id_candidates()
			return PackedStringArray()
		"despawn", "set_level", "watch", "stats", "inspect", "trade", "navgraph", "navpath":
			var out: PackedStringArray = _bot_name_candidates()
			if sub == "watch": out.append("off")
			return out
		"personality", "say", "emote", "rep", "follow", "stay", "free":
			if prior_args.size() == 1:
				var out: PackedStringArray = _bot_name_candidates()
				if sub in ["follow", "stay", "free"]: out.append("all")
				return out
			match sub:
				"personality":
					return PackedStringArray(BotManager._personalities.keys())
				"emote":
					return PackedStringArray(["sit", "wave", "laugh", "cry"])
				"say":
					return PackedStringArray(["greet", "level_up", "death", "rare_loot",
						"boss_kill", "boss_engage", "party_join", "retreat", "gear_upgrade",
						"reply", "grats"])
				"rep":
					var players: PackedStringArray = []
					for pid in PlayerManager.active_players:
						if not BotManager.is_bot(pid):
							var pname: String = PlayerManager.active_players[pid].get("username", "")
							if not pname.is_empty(): players.append(pname)
					return players
			return PackedStringArray()
		"roster":
			if prior_args.size() == 1:
				return PackedStringArray(["forget"])
			if prior_args.size() == 2 and prior_args[1].to_lower() == "forget":
				return PackedStringArray(BotManager.get_roster().keys())
			return PackedStringArray()
		"churn":
			return PackedStringArray(["status", "on", "off", "now"])
		"party":
			return PackedStringArray(["list", "info", "kick"])
		"travel":
			return PackedStringArray(["info"])
		"debugdraw":
			return PackedStringArray(["on", "off"])
	return PackedStringArray()


## Active bot ids AND names — names read better in commands.
func _bot_name_candidates() -> PackedStringArray:
	var out: PackedStringArray = []
	for bot_id in BotManager.active_bots:
		out.append(str(bot_id))
		var bot_name: String = BotManager.active_bots[bot_id].get("username", "")
		if not bot_name.is_empty(): out.append(bot_name)
	return out


# --- Helpers ----------------------------------------------------------------

func _local_player() -> Node:
	if PlayerManager.has_method("get_player_node"):
		return PlayerManager.get_player_node(_acting_id())
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


# --- /zone command ----------------------------------------------------------
#
# Debug command for visually inspecting ground-zone shapes at scale. Spawns
# the configured zone (no damage) at the local player's position so the user
# can eyeball whether the size/shape reads correctly in-game.
#
# The configs below MIRROR the constants in each AL_*.gd. If an AL changes
# its zone shape/size, this dict needs the same edit — there's no central
# source. Worth the duplication: this is a debug-only tool, and tightly
# coupling it to the AL constants would pull every AL into the debug panel's
# parse graph.

const ZONE_CATALOG: Dictionary = {
	"caltrops":      { "weapon": "Bow",    "shape": "rect",   "size": Vector2(160, 50), "duration": 5.0, "color": Color(0.55, 0.42, 0.18, 0.40), "desc": "Caltrops scatter — wide ground patch + slow." },
	"earthsplitter": { "weapon": "Sword",  "shape": "rect",   "size": Vector2(220, 60), "duration": 4.0, "color": Color(0.55, 0.30, 0.18, 0.42), "desc": "Earthsplitter tremor — heavy ground rect, scales with combo." },
	"sky_volley":    { "weapon": "Bow",    "shape": "rect",   "size": Vector2(240, 60), "duration": 3.0, "color": Color(0.85, 0.78, 0.55, 0.42), "desc": "Sky Volley rain — wide arrow strike strip." },
	"frost_patch":   { "weapon": "Staff",  "shape": "rect",   "size": Vector2(180, 50), "duration": 4.0, "color": Color(0.55, 0.80, 1.00, 0.40), "desc": "Frost Patch — chill + damage zone hugging the floor." },
	"stormcall":     { "weapon": "Staff",  "shape": "rect",   "size": Vector2(220, 60), "duration": 3.0, "color": Color(0.55, 0.55, 1.00, 0.38), "desc": "Stormcall — Lightning channel strip." },
	"pyre_pool":     { "weapon": "Staff",  "shape": "rect",   "size": Vector2(180, 55), "duration": 3.0, "color": Color(0.95, 0.30, 0.10, 0.42), "desc": "Pyre Burst Fire-stance pool — fire on the floor." },
	"spellweave_fire":{"weapon": "Staff",  "shape": "rect",   "size": Vector2(220, 65), "duration": 5.0, "color": Color(0.95, 0.30, 0.10, 0.42), "desc": "Spellweave (Fire) — amplified Pyre pool." },
	"banner":        { "weapon": "Sword",  "shape": "circle", "radius": 110.0,         "duration": 8.0, "color": Color(1.00, 0.85, 0.45, 0.30), "desc": "Banner of the Vanguard — defensive aura (circle reads as a radial buff)." },
	"smoke_bomb":    { "weapon": "Dagger", "shape": "circle", "radius": 90.0,          "duration": 4.0, "color": Color(0.25, 0.25, 0.30, 0.55), "desc": "Smoke Bomb — billowing cloud (circle reads as a 3D-shaped cloud)." },
}


func _cmd_zone(args: Array) -> String:
	if args.is_empty():
		# Listing mode — show every catalog entry with shape + dimensions.
		var lines: PackedStringArray = ["[b]Ground-zone catalog[/b] (use [color=#9fd]zone <name>[/color] to spawn at your feet):"]
		var names := ZONE_CATALOG.keys()
		names.sort()
		for n in names:
			var entry: Dictionary = ZONE_CATALOG[n]
			var dim: String
			if entry["shape"] == "rect":
				dim = "rect %dx%d px" % [int(entry["size"].x), int(entry["size"].y)]
			else:
				dim = "circle r=%d px" % int(entry["radius"])
			lines.append("  [color=#9fd]%-16s[/color] [color=#c79bff]%-6s[/color] %s  [color=#888]%.1fs[/color]  %s" %
				[n, entry["weapon"], dim, entry["duration"], entry["desc"]])
		return "\n".join(lines)

	# Spawn mode — name must be in the catalog.
	if not multiplayer.is_server():
		return "[color=#ff8888]zone spawn requires host (server).[/color]"
	var zone_name: String = String(args[0]).to_lower()
	if not ZONE_CATALOG.has(zone_name):
		return "[color=#ff8888]Unknown zone '%s'. Run 'zone' for the catalog.[/color]" % zone_name

	var player: Node = _local_player()
	if player == null or not is_instance_valid(player):
		return "[color=#ff8888]No local player to anchor the zone on.[/color]"

	var cfg: Dictionary = ZONE_CATALOG[zone_name]
	var GroundZoneScript = load("res://scripts/Gameplay/ground_zone.gd")
	# damage_per_tick=0 so this is a pure visual / no-stat-modify zone. The
	# spawn helper still does its overlap iteration on tick (cheap on the
	# server) — verifies the shape ticking even without a real effect.
	var zone
	if cfg["shape"] == "rect":
		zone = GroundZoneScript.spawn_server_rect(
			player, player.global_position, cfg["size"],
			float(cfg["duration"]), 1.0, 0, cfg["color"],
		)
	else:
		zone = GroundZoneScript.spawn_server(
			player, player.global_position, float(cfg["radius"]),
			float(cfg["duration"]), 1.0, 0, cfg["color"],
		)
	if zone == null:
		return "[color=#ff8888]GroundZone.spawn_server returned null (no map / no applier).[/color]"
	var dim_label: String
	if cfg["shape"] == "rect":
		dim_label = "%dx%d rect" % [int(cfg["size"].x), int(cfg["size"].y)]
	else:
		dim_label = "r=%d circle" % int(cfg["radius"])
	return "[color=#9fd]Spawned %s zone (%s, %.1fs)[/color] at your feet for inspection." % [zone_name, dim_label, float(cfg["duration"])]


func _complete_zone_args(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	# Suggest catalog names for the first arg, nothing past that. (Previously
	# declared with a String first param while the dispatcher passes a
	# PackedStringArray — completing past 'zone ' errored instead of suggesting.)
	if not prior_args.is_empty():
		return PackedStringArray()
	var out: PackedStringArray = PackedStringArray()
	for n in ZONE_CATALOG.keys():
		out.append(n)
	out.sort()
	return out


# ===========================================================================
# pairtest — one-command max-power weapon-pair build vs the boss
# ===========================================================================

## Curated per-(active|offhand) hotbar loadouts: 5 actives of the ACTIVE
## discipline chosen to exercise the pair layer (imbues, combo/momentum/charge
## spends) and the status-tag escalations (Thermal Shock / Septic / Brittle).
## Staff bars carry the Immolate+Frost Patch thermal engine; bow bars the
## Barbed Shot bleed + Mark of the Hunt Brittle core; sword|dagger leans on
## Hemorrhage bleeds feeding the off-hand poison imbue into Septic.
const PAIRTEST_LOADOUTS := {
	"sword|staff": ["Steel Flurry", "Crescent Cleave", "Sentinel's Mark", "Earthsplitter", "Vault Strike"],
	"sword|dagger": ["Steel Flurry", "Hemorrhage", "Sentinel's Mark", "Crescent Cleave", "Earthsplitter"],
	"sword|bow": ["Steel Flurry", "Crescent Cleave", "Hemorrhage", "Vanguard's Onslaught", "Earthsplitter"],
	"bow|sword": ["Split Shot", "Barbed Shot", "Mark of the Hunt", "Hailstorm", "Snipe"],
	"bow|staff": ["Split Shot", "Barbed Shot", "Mark of the Hunt", "Hailstorm", "Snipe"],
	"bow|dagger": ["Split Shot", "Barbed Shot", "Mark of the Hunt", "Hailstorm", "Snipe"],
	"staff|sword": ["Arcane Bolt", "Immolate", "Frost Patch", "Spellweave", "Stormcall"],
	"staff|bow": ["Arcane Bolt", "Immolate", "Frost Patch", "Arcane Lance", "Stormcall"],
	"staff|dagger": ["Arcane Bolt", "Immolate", "Frost Patch", "Mana Surge", "Stormcall"],
	"dagger|sword": ["Twin Fang", "Eviscerate", "Envenom", "Death Mark", "Fan of Knives"],
	"dagger|staff": ["Twin Fang", "Eviscerate", "Envenom", "Shadowstep", "Death Mark"],
	"dagger|bow": ["Twin Fang", "Eviscerate", "Fan of Knives", "Shadowstep", "Smoke Bomb"],
}
## Astral = item_level 93, the tier nearest "level 90 gear".
const PAIRTEST_GEAR_TIER := "Astral"
const PAIRTEST_ARMOR_FAMILY := {0: "Vanguard", 1: "Pathfinder", 2: "Arcanist", 3: "Nightshade"}
const PAIRTEST_WEAPON_NOUN := {0: "Longsword", 1: "Warbow", 2: "Spellstaff", 3: "Dirk"}
const PAIRTEST_LEVEL := 100
const PAIRTEST_BOSS_MAP := "warlord"
const PAIRTEST_BOSS_NODE := "EternalWarlord"
## Legit budget: NO dev point grant. The build spends only what capped
## mastery legitimately provides (MASTERY_CAP x ABILITY_POINTS_PER_MASTERY_LEVEL
## = 100 points per discipline), allocated like a real player would:
## max the 5 hotbar actives, buy their T1/T2 + one curated T3 each, then
## sink the remainder into the discipline's synergy passives.
const PAIRTEST_PASSIVES := {
	"sword": ["Vanguard's Resolve", "Battle-Hardened", "Aggression"],
	"bow": ["Wind Rider", "Tailwind", "Lethality"],
	"staff": ["Elemental Affinity", "Overload", "Killing Spree"],
	"dagger": ["Predator's Patience", "Opportunist", "Toxicology"],
}
## effect_keys that are plain stat bumps — when picking ONE T3 variant per
## ability, prefer the behavioral option (the one whose key is NOT in this
## set); those are the variants authored to feed the pair/escalation play.
## ADR 0014: every curated bar must carry its discipline's ULTIMATE - the
## ~30s big hitter is the pacing spectrum's centerpiece and the thing the
## pairtest fights exist to feel-test.
const PAIRTEST_ULTIMATES := {"sword": "Earthsplitter", "bow": "Snipe", "staff": "Stormcall", "dagger": "Eviscerate"}
const PAIRTEST_NUMERIC_KEYS := ["bonus_damage_mult", "bonus_targets", "bonus_hits",
	"cooldown_flat_reduction", "mana_flat_reduction", "buff_duration_bonus",
	"bonus_zone_radius", "bonus_zone_duration"]

const _DISC_KEYS := {0: "sword", 1: "bow", 2: "staff", 3: "dagger"}


func _cmd_pairtest(args: Array) -> String:
	if not multiplayer.is_server():
		return "[color=#ff8888]pairtest is host-only (everything it touches is server-authoritative).[/color]"
	if args.size() < 2:
		return "Usage: pairtest <primary> <secondary>  (sword|bow|staff|dagger, distinct)"
	var prim: int = _parse_discipline_arg(String(args[0]))
	var sec: int = _parse_discipline_arg(String(args[1]))
	if prim < 0 or sec < 0:
		return "[color=#ff8888]Unknown discipline. Use sword/bow/staff/dagger.[/color]"
	if prim == sec:
		return "[color=#ff8888]Pick two DIFFERENT disciplines (pairs need a genuine pair).[/color]"

	var p: Node = _local_player()
	if not is_instance_valid(p):
		return "(no local player)"
	var out: PackedStringArray = []
	var prim_name: String = _discipline_label(prim)
	var sec_name: String = _discipline_label(sec)

	# 1. Character level -> 100. _is_loading_data mutes the per-level fan-out
	# (SFX / party share / announcements) - 99 level-ups in one frame
	# otherwise stall the game; one save/sync happens naturally afterwards.
	if is_instance_valid(p.level_component):
		var lc = p.level_component
		var was_loading: bool = lc._is_loading_data
		lc._is_loading_data = true
		var start: int = lc.level
		while lc.level < PAIRTEST_LEVEL:
			lc.add_exp(lc.get_exp_to_next_level())
			if lc.level == start:
				break
			start = lc.level
		lc._is_loading_data = was_loading
		out.append("level -> %d" % lc.level)

	# 2. Mastery cap on both disciplines. ONE mega-grant per discipline: the
	# grant loops levels internally and (since the per-level emit fix) fires
	# mastery_level_changed once per level, so the point flow stays exact
	# while the sync RPC happens once instead of 100 times.
	var ac_bulk = p.ability_component
	if is_instance_valid(ac_bulk) and ac_bulk.has_method("begin_bulk_edit"):
		ac_bulk.begin_bulk_edit()
	var wm = p.weapon_mastery_component
	if is_instance_valid(wm):
		for disc in [prim, sec]:
			if wm.get_mastery_level(disc) < WeaponMasteryComponent.MASTERY_CAP:
				wm.grant_mastery_xp_server(disc, 1 << 31)
		wm.set_primary_discipline(prim)
		out.append("mastery capped (%s + %s), primary = %s" % [prim_name, sec_name, prim_name])

	# 3. Astral (L93) gear: both weapons + the primary discipline's armor set.
	var equipped: PackedStringArray = []
	if is_instance_valid(p.equipment_component) and is_instance_valid(p.inventory_component):
		var gear: Array = [
			["WEAPON", "%s %s" % [PAIRTEST_GEAR_TIER, PAIRTEST_WEAPON_NOUN[prim]]],
			["SECONDARY_WEAPON", "%s %s" % [PAIRTEST_GEAR_TIER, PAIRTEST_WEAPON_NOUN[sec]]],
			[Constants.ArmorType.HEAD, "%s %s Helm" % [PAIRTEST_GEAR_TIER, PAIRTEST_ARMOR_FAMILY[prim]]],
			[Constants.ArmorType.CHEST, "%s %s Mail" % [PAIRTEST_GEAR_TIER, PAIRTEST_ARMOR_FAMILY[prim]]],
			[Constants.ArmorType.LEGS, "%s %s Legguards" % [PAIRTEST_GEAR_TIER, PAIRTEST_ARMOR_FAMILY[prim]]],
			[Constants.ArmorType.FEET, "%s %s Boots" % [PAIRTEST_GEAR_TIER, PAIRTEST_ARMOR_FAMILY[prim]]],
		]
		for entry in gear:
			var item: ItemData = ResourceManager.get_item_by_name(entry[1])
			var sd: SlotData = p.equipment_component.get_slot_data(entry[0])
			if item == null or sd == null:
				out.append("[color=#ff8888]gear miss: %s[/color]" % String(entry[1]))
				continue
			sd.item = item
			p.equipment_component.refresh_view(entry[0])
			if p.inventory_component.has_method("_sync_equipment_slot_to_client") and not BotManager.is_bot(p.player_id):
				p.inventory_component._sync_equipment_slot_to_client(sd, false)
			equipped.append(String(entry[1]))
		p.equipment_component._emit_equipment_changed_deferred()
		out.append("equipped: " + ", ".join(equipped))

	# 4. Spend the LEGIT budget (100 pts/discipline from capped mastery):
	# respec to a clean slate first so reruns and pre-spent characters get
	# the full pool back, then allocate like a real build - hotbar actives
	# first, their upgrades, then the discipline's synergy passives.
	var ac = p.ability_component
	if is_instance_valid(ac):
		for disc in [prim, sec]:
			ac.respec_discipline(_DISC_KEYS[disc])
		for disc in [prim, sec]:
			var key: String = _DISC_KEYS[disc]
			var loadout_key: String = key + "|" + _DISC_KEYS[sec if disc == prim else prim]
			var maxed := 0
			var upgrades_bought := 0
			# Actives on the bar first - the build's core.
			for ability_name in PAIRTEST_LOADOUTS[loadout_key]:
				var r := _pairtest_build_ability(ac, String(ability_name))
				maxed += r.x
				upgrades_bought += r.y
			# Remaining points into the synergy passives, in priority order.
			for passive_name in PAIRTEST_PASSIVES[key]:
				var r2 := _pairtest_build_ability(ac, String(passive_name))
				maxed += r2.x
				upgrades_bought += r2.y
			out.append("%s build: %d abilities maxed, %d upgrades, %d pts left" % [
				key, maxed, upgrades_bought, ac.get_available_points_for_discipline(key)])
		# Flush everything the bulk suppressed in one pass (passives, signals,
		# syncs) - the UI rebuilds once instead of ~400 times.
		if ac.has_method("end_bulk_edit"):
			ac.end_bulk_edit()

		# 5. Curated synergy hotbars — primary bar for (prim|sec), secondary
		# bar for the reverse direction, so Tab-swapping keeps the synergy story.
		var slot_count: int = 10
		if is_instance_valid(ac.hotbar) and not ac.hotbar.hotbar_slots.is_empty():
			slot_count = ac.hotbar.hotbar_slots.size()
		var prim_cfg := _pairtest_bar(_DISC_KEYS[prim] + "|" + _DISC_KEYS[sec], slot_count)
		var sec_cfg := _pairtest_bar(_DISC_KEYS[sec] + "|" + _DISC_KEYS[prim], slot_count)
		ac._primary_hotbar_bindings = prim_cfg
		ac._secondary_hotbar_bindings = sec_cfg
		ac.hotbar_bindings_changed.emit()
		if is_instance_valid(ac.hotbar):
			ac.hotbar.load_hotbar_config(ac._active_bindings_for_load())
		out.append("hotbars set: [%s] / swap: [%s]" % [
			", ".join(PackedStringArray(PAIRTEST_LOADOUTS[_DISC_KEYS[prim] + "|" + _DISC_KEYS[sec]])),
			", ".join(PackedStringArray(PAIRTEST_LOADOUTS[_DISC_KEYS[sec] + "|" + _DISC_KEYS[prim]]))])

	# 6. Top up, revive the boss, and ship them in. The Warlord's natural
	# respawn is 300s - far too slow for back-to-back combo runs - and
	# pool_reset() is the engine's own full revive (health, visuals, boss
	# phase/enrage state), so every pairtest starts against a clean fight.
	if is_instance_valid(p.health_component):
		p.health_component.heal_damage(9999999, p)
	if MapManager.active_maps.has(PAIRTEST_BOSS_MAP):
		var map_inst = MapManager.active_maps[PAIRTEST_BOSS_MAP].scene_instance
		if is_instance_valid(map_inst):
			var boss = map_inst.find_child(PAIRTEST_BOSS_NODE, true, false)
			if is_instance_valid(boss) and boss.has_method("pool_reset"):
				boss.pool_reset()
				out.append("boss reset: %s at full strength" % PAIRTEST_BOSS_NODE)
	MapManager.request_map_change(p.player_id, PAIRTEST_BOSS_MAP)
	out.append("teleported to '%s' — good hunting." % PAIRTEST_BOSS_MAP)

	return "[b]pairtest %s + %s[/b]\n  " % [prim_name, sec_name] + "\n  ".join(out)


## Builds a hotbar config ({str(slot): ability_id}) from a curated loadout key.
func _pairtest_bar(loadout_key: String, slot_count: int) -> Dictionary:
	var cfg := {}
	var names: Array = PAIRTEST_LOADOUTS.get(loadout_key, [])
	for i in range(slot_count):
		var id := ""
		if i < names.size():
			var ability: AbilityData = ResourceManager.get_ability_data(String(names[i]))
			if ability != null:
				id = ability.ability_id
		cfg[str(i)] = id
	return cfg


## Levels one ability to max and buys its upgrade line (T1, T2, ONE curated
## T3) within whatever points remain. Returns Vector2i(maxed ? 1 : 0, upgrades
## bought). All spending goes through the real validation APIs, so when the
## pool dries up the calls refuse and the build simply stops growing.
func _pairtest_build_ability(ac, ability_name: String) -> Vector2i:
	var ability: AbilityData = ResourceManager.get_ability_data(ability_name)
	if ability == null:
		return Vector2i.ZERO
	var ability_id: String = ability.ability_id
	if int(ac.get_ability_level(ability_id)) <= 0:
		ac.learn_ability(ability_id, 0)
	while int(ac.get_ability_level(ability_id)) < ability.max_level:
		if not ac.level_up_ability(ability_id):
			break
	var maxed: int = 1 if int(ac.get_ability_level(ability_id)) >= ability.max_level else 0
	var bought := 0
	if ability.upgrades == null or maxed == 0:
		return Vector2i(maxed, 0)
	# T1 + T2 (stackable), then exactly one curated T3.
	for up in ability.upgrades:
		if up == null or up.tier >= 3:
			continue
		if ac.can_purchase_upgrade(ability_id, up.upgrade_id).ok:
			ac.purchase_upgrade(ability_id, up.upgrade_id)
			bought += 1
	var t3 := _pairtest_pick_t3(ability)
	if t3 != null and ac.can_purchase_upgrade(ability_id, t3.upgrade_id).ok:
		ac.purchase_upgrade(ability_id, t3.upgrade_id)
		bought += 1
	return Vector2i(maxed, bought)


## The curated T3: prefer the behavioral variant (effect_key outside the
## plain-numeric set) - those are the options authored to feed the pair
## synergy and the status-tag escalations. Falls back to the first T3.
func _pairtest_pick_t3(ability: AbilityData) -> AbilityUpgradeData:
	var first: AbilityUpgradeData = null
	for up in ability.upgrades:
		if up == null or up.tier != 3:
			continue
		if first == null:
			first = up
		if not (up.effect_key in PAIRTEST_NUMERIC_KEYS):
			return up
	return first


func _complete_pairtest(prior_args: PackedStringArray, _t: String) -> PackedStringArray:
	if prior_args.size() <= 1:
		return PackedStringArray(["sword", "bow", "staff", "dagger"])
	return PackedStringArray()
