class_name QuestWindow
extends Panel

## Quest window — MapleStory-style quest tracker.
## Shows available, active, and completed quests with details and accept/abandon controls.
## Requests quest data from the server via RPC (or directly in host mode).

@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var available_tab_btn: Button = %AvailableTabBtn
@onready var active_tab_btn: Button = %ActiveTabBtn
@onready var completed_tab_btn: Button = %CompletedTabBtn
@onready var quest_list_container: VBoxContainer = %QuestListContainer
@onready var quest_title_label: Label = %QuestTitleLabel
@onready var quest_desc_label: RichTextLabel = %QuestDescLabel
@onready var objectives_container: VBoxContainer = %ObjectivesContainer
@onready var rewards_container: VBoxContainer = %RewardsContainer
@onready var action_button: Button = %ActionButton
@onready var track_button: CheckButton = %TrackButton

var player: MultiplayerPlayerV2

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

enum TabMode { AVAILABLE, ACTIVE, COMPLETED }
var current_tab: TabMode = TabMode.AVAILABLE

var quest_data_cache: Dictionary = {}
var selected_quest_id: String = ""


func _ready() -> void:
	add_to_group("ui_window")

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

	close_button.pressed.connect(func(): self.visible = false)
	available_tab_btn.pressed.connect(func(): _switch_tab(TabMode.AVAILABLE))
	active_tab_btn.pressed.connect(func(): _switch_tab(TabMode.ACTIVE))
	completed_tab_btn.pressed.connect(func(): _switch_tab(TabMode.COMPLETED))
	action_button.pressed.connect(_on_action_pressed)
	track_button.toggled.connect(_on_track_toggled)

	QuestManager.quest_ui_data_received.connect(_on_quest_data_received)

	_clear_detail_panel()
	_update_tab_buttons()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenQuestWindow"):
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
		# Host mode: build data directly
		var data := QuestManager._build_quest_ui_data(player.username, player)
		_on_quest_data_received(data)
	else:
		QuestManager.request_quest_ui_data.rpc_id(1)


func _on_quest_data_received(data: Dictionary) -> void:
	quest_data_cache = data
	_refresh_quest_list()
	if not selected_quest_id.is_empty():
		_try_reselect_quest()


# ── Tab switching ─────────────────────────────────────────────────────────────

func _switch_tab(tab: TabMode) -> void:
	current_tab = tab
	selected_quest_id = ""
	_clear_detail_panel()
	_update_tab_buttons()
	_refresh_quest_list()


func _update_tab_buttons() -> void:
	available_tab_btn.flat = (current_tab != TabMode.AVAILABLE)
	active_tab_btn.flat = (current_tab != TabMode.ACTIVE)
	completed_tab_btn.flat = (current_tab != TabMode.COMPLETED)


# ── Quest list ────────────────────────────────────────────────────────────────

func _refresh_quest_list() -> void:
	for child in quest_list_container.get_children():
		child.queue_free()

	var quests: Array = []
	match current_tab:
		TabMode.AVAILABLE:
			# NPC-only quests are hidden from the journal's Available tab —
			# they only show in the dialog of the QuestGiverNPC that offers
			# them. After acceptance they appear normally in Active /
			# Completed (which is why those tabs don't filter).
			for q in quest_data_cache.get("available", []):
				if bool(q.get("npc_only", false)):
					continue
				quests.append(q)
		TabMode.ACTIVE:    quests = quest_data_cache.get("active", [])
		TabMode.COMPLETED: quests = quest_data_cache.get("completed", [])

	if quests.is_empty():
		var empty_label := Label.new()
		match current_tab:
			TabMode.AVAILABLE: empty_label.text = "No quests available at your level."
			TabMode.ACTIVE:    empty_label.text = "No active quests.\nUse Available tab to find quests."
			TabMode.COMPLETED: empty_label.text = "No completed quests yet."
		empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		quest_list_container.add_child(empty_label)
		return

	for q in quests:
		var q_id: String = q.get("id", "")
		var btn := Button.new()
		btn.text = "  " + q.get("name", q_id)
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.focus_mode = Control.FOCUS_NONE
		if q_id == selected_quest_id:
			btn.add_theme_color_override("font_color", Color.GOLD)
		btn.pressed.connect(_on_quest_selected.bind(q_id))
		quest_list_container.add_child(btn)


func _on_quest_selected(quest_id: String) -> void:
	selected_quest_id = quest_id
	_refresh_quest_list()
	_show_quest_detail(quest_id)


# ── Detail panel ──────────────────────────────────────────────────────────────

func _show_quest_detail(quest_id: String) -> void:
	var quest_info: Dictionary = {}
	for list_key in ["available", "active", "completed"]:
		for q in quest_data_cache.get(list_key, []):
			if q.get("id", "") == quest_id:
				quest_info = q
				break
		if not quest_info.is_empty():
			break

	if quest_info.is_empty():
		_clear_detail_panel()
		return

	quest_title_label.text = quest_info.get("name", "Unknown")

	# Description
	quest_desc_label.clear()
	quest_desc_label.push_color(Color(0.6, 0.8, 1.0))
	quest_desc_label.add_text("Level %d Required\n\n" % quest_info.get("required_level", 1))
	quest_desc_label.pop()
	quest_desc_label.add_text(quest_info.get("description", ""))

	# Objectives
	for child in objectives_container.get_children():
		child.queue_free()

	var objectives: Array = quest_info.get("objectives", [])
	var progress: Dictionary = quest_info.get("progress", {})
	var is_active: bool = current_tab == TabMode.ACTIVE

	for i in range(objectives.size()):
		var obj: Dictionary = objectives[i]
		var type_name: String = obj.get("type_name", "")
		var target: String = obj.get("target", "")
		var amount: int = obj.get("amount", 1)
		var current: int = progress.get(str(i), 0)

		var label := Label.new()
		if not target.is_empty():
			label.text = "  • %s %s" % [type_name, target]
		else:
			label.text = "  • %s" % type_name

		if is_active:
			label.text += "  [%d/%d]" % [current, amount]
			if current >= amount:
				label.add_theme_color_override("font_color", Color.GREEN)
		else:
			label.text += "  x%d" % amount

		if current_tab == TabMode.COMPLETED:
			label.add_theme_color_override("font_color", Color.GREEN)

		objectives_container.add_child(label)

	# Rewards
	for child in rewards_container.get_children():
		child.queue_free()

	var exp: int = quest_info.get("reward_exp", 0)
	var coins: int = quest_info.get("reward_coins", 0)
	var items: Array = quest_info.get("reward_items", [])

	if exp > 0:
		var lbl := Label.new()
		lbl.text = "  • %d EXP" % exp
		lbl.add_theme_color_override("font_color", Color(1.0, 0.95, 0.4))
		rewards_container.add_child(lbl)
	if coins > 0:
		var lbl := Label.new()
		lbl.text = "  • %d Coins" % coins
		lbl.add_theme_color_override("font_color", Color.GOLD)
		rewards_container.add_child(lbl)
	for item in items:
		var lbl := Label.new()
		lbl.text = "  • %s" % item
		rewards_container.add_child(lbl)

	# Action button + Track toggle (Track only meaningful on the Active tab)
	match current_tab:
		TabMode.AVAILABLE:
			action_button.text = "Accept Quest"
			action_button.disabled = false
			action_button.visible = true
			track_button.visible = false
		TabMode.ACTIVE:
			action_button.text = "Abandon Quest"
			action_button.disabled = false
			action_button.visible = true
			track_button.visible = true
			_refresh_track_button(quest_info)
		TabMode.COMPLETED:
			action_button.visible = false
			track_button.visible = false


func _try_reselect_quest() -> void:
	var quest_list: Array = []
	match current_tab:
		TabMode.AVAILABLE: quest_list = quest_data_cache.get("available", [])
		TabMode.ACTIVE:    quest_list = quest_data_cache.get("active", [])
		TabMode.COMPLETED: quest_list = quest_data_cache.get("completed", [])

	for q in quest_list:
		if q.get("id", "") == selected_quest_id:
			_show_quest_detail(selected_quest_id)
			return

	selected_quest_id = ""
	_clear_detail_panel()


func _clear_detail_panel() -> void:
	quest_title_label.text = "Select a quest"
	quest_desc_label.clear()
	for child in objectives_container.get_children():
		child.queue_free()
	for child in rewards_container.get_children():
		child.queue_free()
	action_button.visible = false
	track_button.visible = false


## Sync the Track checkbox to the server-reported state for the given quest,
## without re-firing the toggled signal.
func _refresh_track_button(quest_info: Dictionary) -> void:
	track_button.set_pressed_no_signal(bool(quest_info.get("tracked", false)))


# ── Action button ─────────────────────────────────────────────────────────────

func _on_action_pressed() -> void:
	if selected_quest_id.is_empty() or not is_instance_valid(player):
		return

	match current_tab:
		TabMode.AVAILABLE:
			if multiplayer.is_server():
				QuestManager._cmd_accept(player.player_id, player.username, player, selected_quest_id)
				_request_data()
			else:
				QuestManager.request_quest_accept.rpc_id(1, selected_quest_id)
		TabMode.ACTIVE:
			if multiplayer.is_server():
				QuestManager._cmd_abandon(player.player_id, player.username, selected_quest_id)
				_request_data()
			else:
				QuestManager.request_quest_abandon.rpc_id(1, selected_quest_id)


func _on_track_toggled(_pressed: bool) -> void:
	if selected_quest_id.is_empty() or not is_instance_valid(player):
		return
	# Always round-trip through the server — it owns the cap (MAX_TRACKED_QUESTS)
	# and may reject the change with a chat message. The follow-up snapshot push
	# resyncs the checkbox to whatever the server actually applied.
	if multiplayer.is_server():
		QuestManager._cmd_toggle_track(player.player_id, player.username, selected_quest_id)
	else:
		QuestManager.request_quest_toggle_track.rpc_id(1, selected_quest_id)
