class_name QuestTracker
extends PanelContainer

## On-screen quest tracker — a compact, always-visible HUD overlay listing the
## local player's active quests and their objective progress, so the progression
## journey stays legible without opening the full Quest Log (Q).
##
## Built entirely in code and instantiated by the player controller into the
## local player's HUD. Data is driven by QuestManager: the tracker listens to
## `quest_ui_data_received` (pushed by the server on every quest change) and
## requests an initial snapshot itself, retrying until one arrives.

const MAX_TRACKED: int = 5
const THEME_PATH: String = "res://assets/themes/UI_Theme.tres"
const RETRY_INTERVAL: float = 1.5

var player: MultiplayerPlayerV2

var _entries_box: VBoxContainer
var _data_received: bool = false
var _retry_accum: float = 0.0
var _active_count: int = 0


## Called by the player controller right after instantiation.
func setup(p: MultiplayerPlayerV2) -> void:
	player = p


func _ready() -> void:
	_build_ui()
	visible = false
	QuestManager.quest_ui_data_received.connect(_on_quest_data_received)


func _build_ui() -> void:
	# Anchor to the top-right of the HUD, growing downward as quests are added.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_left = -272.0
	offset_right = -12.0
	offset_top = 64.0
	offset_bottom = 64.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	grow_vertical = Control.GROW_DIRECTION_END
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var ui_theme: Theme = load(THEME_PATH)
	if ui_theme:
		theme = ui_theme

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.105, 0.078, 0.058, 0.86)
	bg.border_color = Color(0.6, 0.42, 0.2, 0.9)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(3)
	bg.content_margin_left = 10.0
	bg.content_margin_right = 10.0
	bg.content_margin_top = 8.0
	bg.content_margin_bottom = 8.0
	add_theme_stylebox_override("panel", bg)

	var outer := VBoxContainer.new()
	outer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outer.add_theme_constant_override("separation", 6)
	add_child(outer)

	var header := Label.new()
	header.text = "QUESTS"
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	header.add_theme_font_size_override("font_size", 14)
	outer.add_child(header)

	_entries_box = VBoxContainer.new()
	_entries_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_entries_box.add_theme_constant_override("separation", 8)
	outer.add_child(_entries_box)


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		visible = false
		return

	# Only the local player's tracker is ever shown or active.
	if multiplayer.get_unique_id() != player.player_id:
		visible = false
		return

	visible = _active_count > 0

	if not _data_received:
		_retry_accum -= delta
		if _retry_accum <= 0.0:
			_retry_accum = RETRY_INTERVAL
			_request_data()


func _request_data() -> void:
	if not is_instance_valid(player):
		return
	if multiplayer.is_server():
		# Host mode: build the snapshot directly (no RPC round-trip). Wait until
		# the player's username has been assigned during spawn initialization.
		if player.username != "":
			_on_quest_data_received(QuestManager._build_quest_ui_data(player.username, player))
	else:
		QuestManager.request_quest_ui_data.rpc_id(1)


func _on_quest_data_received(data: Dictionary) -> void:
	_data_received = true
	_rebuild(data.get("active", []))


func _rebuild(active: Array) -> void:
	for child in _entries_box.get_children():
		child.queue_free()
	_active_count = 0
	for q in active:
		if _active_count >= MAX_TRACKED:
			break
		# Only quests the player has pinned via the Quest Journal show in the HUD.
		# An older save snapshot lacking the field defaults to tracked so the
		# tracker still works while the upgrade rolls out.
		if not bool(q.get("tracked", true)):
			continue
		_entries_box.add_child(_make_entry(q))
		_active_count += 1


func _make_entry(q: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)

	var name_label := Label.new()
	name_label.text = q.get("name", "Quest")
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_label.add_theme_color_override("font_color", Color(0.95, 0.86, 0.66))
	name_label.add_theme_font_size_override("font_size", 13)
	box.add_child(name_label)

	var objectives: Array = q.get("objectives", [])
	var progress: Dictionary = q.get("progress", {})
	for i in range(objectives.size()):
		var obj: Dictionary = objectives[i]
		var amount: int = obj.get("amount", 1)
		var current: int = min(int(progress.get(str(i), 0)), amount)
		var target: String = obj.get("target", "")
		var type_name: String = obj.get("type_name", "")

		var text: String
		if type_name == "Reach Level":
			text = "  Reach Level %d  (%d/%d)" % [amount, current, amount]
		elif target.is_empty():
			text = "  %s  %d/%d" % [type_name, current, amount]
		else:
			text = "  %s %s  %d/%d" % [type_name, target, current, amount]

		var obj_label := Label.new()
		obj_label.text = text
		obj_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		obj_label.add_theme_font_size_override("font_size", 12)
		if current >= amount:
			obj_label.add_theme_color_override("font_color", Color(0.45, 0.9, 0.45))
		else:
			obj_label.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82))
		box.add_child(obj_label)

	return box
