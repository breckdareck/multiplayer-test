class_name DailyChallengeWindow
extends Panel

## Daily Co-op Challenge window — shows today's rotating party challenge,
## the player's progress, the reward, and any active EXP buff.
##
## Toggled with the OpenDailyChallengeWindow input action. Draggable by its
## title bar, like the other moveable windows. Data is requested from the
## server via DailyChallengeManager (or built directly in host mode).

@onready var title_label: Label = %TitleLabel
@onready var close_button: Button = %CloseButton
@onready var challenge_name_label: Label = %ChallengeNameLabel
@onready var type_label: Label = %TypeLabel
@onready var desc_label: RichTextLabel = %DescLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var progress_label: Label = %ProgressLabel
@onready var reward_label: Label = %RewardLabel
@onready var status_label: Label = %StatusLabel

var player: MultiplayerPlayerV2

var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO

var _cached_data: Dictionary = {}


func _ready() -> void:
	add_to_group("ui_window")

	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2

	close_button.pressed.connect(func(): self.visible = false)
	DailyChallengeManager.challenge_ui_data_received.connect(_on_data_received)

	_clear_panel()


func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return

	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenDailyChallengeWindow"):
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
		# Host mode — build data directly.
		_on_data_received(DailyChallengeManager._build_ui_data(player.username))
	else:
		DailyChallengeManager.request_challenge_ui_data.rpc_id(1)


func _on_data_received(data: Dictionary) -> void:
	_cached_data = data
	_refresh()


# ── Rendering ─────────────────────────────────────────────────────────────────

func _refresh() -> void:
	if _cached_data.is_empty() or not _cached_data.get("has_challenge", false):
		_clear_panel()
		challenge_name_label.text = "No challenge available."
		return

	challenge_name_label.text = _cached_data.get("title", "")
	type_label.text = "[%s]" % _cached_data.get("type_name", "")

	desc_label.clear()
	desc_label.add_text(_cached_data.get("description", ""))

	var progress: int = _cached_data.get("progress", 0)
	var goal: int = max(1, _cached_data.get("goal", 1))
	var completed: bool = _cached_data.get("completed", false)

	progress_bar.max_value = goal
	progress_bar.value = progress
	progress_label.text = "%d / %d" % [progress, goal]

	reward_label.text = "Reward: %s" % _cached_data.get("reward_text", "")

	if completed:
		status_label.text = "COMPLETED — come back tomorrow!"
		status_label.add_theme_color_override("font_color", Color.GOLD)
	else:
		status_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
		var buff_remaining: float = _cached_data.get("exp_buff_remaining", 0.0)
		if buff_remaining > 0.0:
			status_label.text = "Double EXP active: %d min left" % int(buff_remaining / 60.0)
		else:
			status_label.text = "Progress only counts in a party of 2+."


func _clear_panel() -> void:
	challenge_name_label.text = ""
	type_label.text = ""
	desc_label.clear()
	progress_bar.value = 0
	progress_label.text = ""
	reward_label.text = ""
	status_label.text = ""
