class_name QuestGiverDialog
extends Panel

## NPC quest dialog. Opened by QuestGiverNPC on right-click. Shows the subset
## of QuestManager quests this NPC has been configured to offer
## (`offered_quest_ids`), filtered by the player's current state:
##
##  * Available (level + prereqs satisfied, not active, not completed):
##    rendered with an Accept button that fires QuestManager.request_quest_accept.
##  * Active: rendered with the live objective-progress text, no button.
##  * Completed: hidden — the Q window's Completed tab is the long-form ledger.
##  * Anything not yet visible to the player (level too low / prereq unmet):
##    silently skipped, just like the Q window's Available tab.
##
## Data path mirrors quest_window.gd: in host mode we query
## QuestManager._build_quest_ui_data directly; on a remote client we send
## request_quest_ui_data.rpc_id(1) and react via the shared
## quest_ui_data_received signal.

const THEME_PATH: String = "res://assets/themes/UI_Theme.tres"

const GOLD: Color = Color(1.0, 0.85, 0.35)
const PROGRESS_BLUE: Color = Color(0.55, 0.85, 1.0)
const DESC_GRAY: Color = Color(0.85, 0.85, 0.85)
const DIM_GRAY: Color = Color(0.55, 0.55, 0.55)

var npc_name: String = "Quest-Giver"
var offered_quest_ids: PackedStringArray = PackedStringArray()

var _title_label: Label
var _list_container: VBoxContainer
var _signal_connected: bool = false


func _ready() -> void:
	add_to_group("ui_window")
	_build_ui()
	visible = false


func _build_ui() -> void:
	custom_minimum_size = Vector2(440, 380)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 0.5
	anchor_bottom = 0.5
	offset_left = -220.0
	offset_right = 220.0
	offset_top = -190.0
	offset_bottom = 190.0
	mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_theme: Theme = load(THEME_PATH)
	if ui_theme:
		theme = ui_theme

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	bg.border_color = Color(0.55, 0.45, 0.2, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 18.0
	bg.content_margin_right = 18.0
	bg.content_margin_top = 14.0
	bg.content_margin_bottom = 14.0
	add_theme_stylebox_override("panel", bg)

	var vbox := VBoxContainer.new()
	vbox.anchor_left = 0.0
	vbox.anchor_top = 0.0
	vbox.anchor_right = 1.0
	vbox.anchor_bottom = 1.0
	vbox.offset_left = 18.0
	vbox.offset_top = 14.0
	vbox.offset_right = -18.0
	vbox.offset_bottom = -14.0
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = npc_name
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", GOLD)
	_title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_label)

	vbox.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_list_container = VBoxContainer.new()
	_list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list_container.add_theme_constant_override("separation", 12)
	scroll.add_child(_list_container)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(btn_row)

	var close_button := Button.new()
	close_button.text = "Close"
	close_button.custom_minimum_size = Vector2(120, 32)
	close_button.pressed.connect(func(): visible = false)
	btn_row.add_child(close_button)


## Called by QuestGiverNPC after instantiation, before the dialog is opened.
func configure(display_name: String, quest_ids: PackedStringArray) -> void:
	npc_name = display_name
	offered_quest_ids = quest_ids.duplicate()
	if _title_label:
		_title_label.text = display_name


## Re-populate the list against the local player's current quest state.
## Called by QuestGiverNPC each time the dialog is opened.
func refresh_for_local_player() -> void:
	if not _list_container:
		return
	if not _signal_connected:
		QuestManager.quest_ui_data_received.connect(_on_quest_data_received)
		_signal_connected = true

	var local_player := _find_local_player()
	if not is_instance_valid(local_player):
		_render_empty("Could not find your character.")
		return

	if multiplayer.is_server():
		# Host mode: query directly, no RPC round-trip.
		var data := QuestManager._build_quest_ui_data(local_player.username, local_player)
		_populate(data, local_player)
	else:
		QuestManager.request_quest_ui_data.rpc_id(1)
		# _on_quest_data_received will fire and populate when the server replies.


func _on_quest_data_received(data: Dictionary) -> void:
	# This signal is shared with QuestWindow / QuestTracker — every dialog
	# instance gets every update. We only repopulate while we're visible,
	# otherwise stale dialogs in other player nodes would churn UI nodes.
	if not visible:
		return
	var local_player := _find_local_player()
	if is_instance_valid(local_player):
		_populate(data, local_player)


func _populate(data: Dictionary, _local_player: MultiplayerPlayerV2) -> void:
	for c in _list_container.get_children():
		c.queue_free()

	# Index the three categories by quest_id for O(1) lookup against our list.
	var by_id: Dictionary = {}
	for q in data.get("available", []):
		by_id[q.get("id", "")] = {"state": "available", "quest": q}
	for q in data.get("active", []):
		by_id[q.get("id", "")] = {"state": "active", "quest": q}
	for q in data.get("completed", []):
		by_id[q.get("id", "")] = {"state": "completed", "quest": q}

	var rendered: int = 0
	for qid in offered_quest_ids:
		var entry: Dictionary = by_id.get(qid, {})
		if entry.is_empty():
			# Player can't see this quest yet (level / prereq) — silently skip,
			# same as the Q window does.
			continue
		match entry["state"]:
			"available":
				_add_available_row(entry["quest"])
				rendered += 1
			"active":
				_add_active_row(entry["quest"])
				rendered += 1
			"completed":
				# Completed-from-this-NPC quests stay hidden; the Q window's
				# Completed tab is the persistent record.
				pass

	if rendered == 0:
		_render_empty("This NPC has nothing for you right now.\nCome back when you're stronger.")


func _add_available_row(q: Dictionary) -> void:
	var row := _make_row()
	var text_vbox := _make_text_vbox(q.get("name", "Quest"), q.get("description", ""), GOLD)
	row.add_child(text_vbox)

	var btn := Button.new()
	btn.text = "Accept"
	btn.custom_minimum_size = Vector2(90, 30)
	var qid: String = q.get("id", "")
	btn.pressed.connect(_on_accept_pressed.bind(qid))
	row.add_child(btn)

	_list_container.add_child(row)


func _add_active_row(q: Dictionary) -> void:
	var row := _make_row()
	var progress_text := _format_progress(q)
	var text_vbox := _make_text_vbox(q.get("name", "Quest"), progress_text, PROGRESS_BLUE)
	row.add_child(text_vbox)

	var status := Label.new()
	status.text = "In Progress"
	status.add_theme_color_override("font_color", PROGRESS_BLUE)
	status.add_theme_font_size_override("font_size", 12)
	row.add_child(status)

	_list_container.add_child(row)


func _render_empty(text: String) -> void:
	for c in _list_container.get_children():
		c.queue_free()
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.add_theme_color_override("font_color", DESC_GRAY)
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list_container.add_child(lbl)


func _make_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 12)
	return row


func _make_text_vbox(title: String, body: String, accent: Color) -> VBoxContainer:
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var t := Label.new()
	t.text = title
	t.add_theme_color_override("font_color", accent)
	t.add_theme_font_size_override("font_size", 14)
	vbox.add_child(t)

	if not body.is_empty():
		var d := Label.new()
		d.text = body
		d.add_theme_color_override("font_color", DESC_GRAY)
		d.add_theme_font_size_override("font_size", 12)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(d)
	return vbox


func _format_progress(q: Dictionary) -> String:
	var objectives: Array = q.get("objectives", [])
	var progress: Dictionary = q.get("progress", {})
	var lines := PackedStringArray()
	for i in range(objectives.size()):
		var obj: Dictionary = objectives[i]
		var amount: int = obj.get("amount", 1)
		var current: int = min(int(progress.get(str(i), 0)), amount)
		var target: String = obj.get("target", "")
		var type_name: String = obj.get("type_name", "")
		if type_name == "Reach Level":
			lines.append("Reach Level %d  (%d/%d)" % [amount, current, amount])
		elif target.is_empty():
			lines.append("%s  %d/%d" % [type_name, current, amount])
		else:
			lines.append("%s %s  %d/%d" % [type_name, target, current, amount])
	return "\n".join(lines)


func _find_local_player() -> MultiplayerPlayerV2:
	var local_id: int = multiplayer.get_unique_id()
	for p in get_tree().get_nodes_in_group("Players"):
		if p.player_id == local_id:
			return p
	return null


func _on_accept_pressed(quest_id: String) -> void:
	if quest_id.is_empty():
		return
	var local_player := _find_local_player()
	if not is_instance_valid(local_player):
		return
	if multiplayer.is_server():
		# Host path: bypass the RPC; the server can call _cmd_accept directly.
		QuestManager._cmd_accept(local_player.player_id, local_player.username, local_player, quest_id)
		# Refresh against the freshly-mutated state.
		refresh_for_local_player()
	else:
		QuestManager.request_quest_accept.rpc_id(1, quest_id)
		# Server will push updated UI data via quest_ui_data_received, which
		# our _on_quest_data_received handler picks up while we're visible.
