class_name DailyQuestWindow
extends Panel

## Daily Quests window — shows today's 3 rotating daily objectives, each with a
## progress bar (e.g. 7/20) and an auto-grant indicator on completion.
##
## Rewards are granted automatically by the server the moment a quest's
## objective is met; this panel is purely a tracker. Data is requested from the
## server via RPC (or built directly in host mode).

@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var date_label: Label = %DateLabel
@onready var quest_list: VBoxContainer = %QuestListContainer

var player: MultiplayerPlayerV2

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	add_to_group("ui_window")

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

	close_button.pressed.connect(func(): self.visible = false)
	DailyQuestManager.daily_quest_ui_data_received.connect(_on_data_received)


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenDailyQuestWindow"):
			if self.visible:
				self.visible = false
			elif not InputManager.is_locked():
				self.visible = true
				_request_data()

	if is_dragging:
		var new_pos := get_global_mouse_position() - drag_offset
		var vp := get_viewport_rect().size
		var win := size
		new_pos.x = clamp(new_pos.x, 0, vp.x - win.x)
		new_pos.y = clamp(new_pos.y, 0, vp.y - win.y)
		global_position = new_pos


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
				self.move_to_front()
		else:
			is_dragging = false


# ── Data fetching ────────────────────────────────────────────────────────────

func _request_data() -> void:
	if not is_instance_valid(player):
		return
	if multiplayer.is_server():
		# Host mode: build data directly.
		_on_data_received(DailyQuestManager.build_ui_data(player.username))
	else:
		DailyQuestManager.request_daily_quest_ui_data.rpc_id(1)


func _on_data_received(data: Dictionary) -> void:
	# Only react when this window is visible to avoid needless rebuilds.
	if not visible:
		return
	_refresh(data)


# ── Rendering ─────────────────────────────────────────────────────────────────

func _refresh(data: Dictionary) -> void:
	date_label.text = "Today: %s" % data.get("date", "")

	for child in quest_list.get_children():
		child.queue_free()

	var quests: Array = data.get("quests", [])
	if quests.is_empty():
		var empty := Label.new()
		empty.text = "No daily quests available."
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		quest_list.add_child(empty)
		return

	for q in quests:
		quest_list.add_child(_build_quest_entry(q))


func _build_quest_entry(q: Dictionary) -> Control:
	var completed: bool = q.get("completed", false)
	var current: int = q.get("current", 0)
	var amount: int = max(1, q.get("amount", 1))

	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	margin.add_child(vbox)

	# Title row — name + status badge.
	var title_row := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = q.get("title", "")
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if completed:
		name_lbl.add_theme_color_override("font_color", Color.GREEN)
	else:
		name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.4))
	title_row.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "CLAIMED" if completed else "%d / %d" % [current, amount]
	status_lbl.add_theme_color_override("font_color",
		Color.GREEN if completed else Color(0.7, 0.85, 1.0))
	title_row.add_child(status_lbl)
	vbox.add_child(title_row)

	# Description.
	var desc_lbl := Label.new()
	desc_lbl.text = q.get("description", "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	desc_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(desc_lbl)

	# Progress bar.
	var bar := ProgressBar.new()
	bar.min_value = 0
	bar.max_value = amount
	bar.value = current
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0, 14)
	vbox.add_child(bar)

	# Rewards line.
	var reward_lbl := Label.new()
	var parts: Array = []
	var exp: int = q.get("reward_exp", 0)
	var coins: int = q.get("reward_coins", 0)
	if exp > 0:
		parts.append("%d EXP" % exp)
	if coins > 0:
		parts.append("%d Coins" % coins)
	reward_lbl.text = "Reward: " + (", ".join(PackedStringArray(parts)) if not parts.is_empty() else "—")
	reward_lbl.add_theme_color_override("font_color", Color.GOLD)
	reward_lbl.add_theme_font_size_override("font_size", 12)
	vbox.add_child(reward_lbl)

	return panel
