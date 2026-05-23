class_name JobAdvancementDialog
extends Panel

## Code-built dialog window opened by JobAdvancementNPC. Reads the local
## player's class + level when shown and either offers Job Advancement, gates
## the player on the level requirement, or acknowledges they have already
## advanced. The "Advance" button fires the same RPC as the /advance chat
## command.

const THEME_PATH: String = "res://assets/themes/UI_Theme.tres"

var _title_label: Label
var _body_label: Label
var _current_label: Label
var _target_label: Label
var _advance_button: Button
var _close_button: Button


func _ready() -> void:
	add_to_group("ui_window")
	_build_ui()
	visible = false


func _build_ui() -> void:
	custom_minimum_size = Vector2(400, 260)
	# Center on screen.
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -200
	offset_right = 200
	offset_top = -130
	offset_bottom = 130
	mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_theme: Theme = load(THEME_PATH)
	if ui_theme:
		theme = ui_theme

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.95)
	bg.border_color = Color(0.55, 0.45, 0.2, 0.95)
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
	vbox.offset_right = -18.0
	vbox.offset_top = 14.0
	vbox.offset_bottom = -14.0
	vbox.add_theme_constant_override("separation", 10)
	add_child(vbox)

	_title_label = Label.new()
	_title_label.text = "Job Advancement Master"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	_title_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(_title_label)

	_body_label = Label.new()
	_body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body_label.add_theme_font_size_override("font_size", 13)
	_body_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	_body_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(_body_label)

	_current_label = Label.new()
	_current_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	_current_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_current_label)

	_target_label = Label.new()
	_target_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.6))
	_target_label.add_theme_font_size_override("font_size", 12)
	vbox.add_child(_target_label)

	var btnrow := HBoxContainer.new()
	btnrow.alignment = BoxContainer.ALIGNMENT_CENTER
	btnrow.add_theme_constant_override("separation", 12)
	vbox.add_child(btnrow)

	_advance_button = Button.new()
	_advance_button.text = "Advance"
	_advance_button.custom_minimum_size = Vector2(120, 32)
	_advance_button.pressed.connect(_on_advance_pressed)
	btnrow.add_child(_advance_button)

	_close_button = Button.new()
	_close_button.text = "Close"
	_close_button.custom_minimum_size = Vector2(120, 32)
	_close_button.pressed.connect(func(): visible = false)
	btnrow.add_child(_close_button)


## Refresh the dialog text based on the local player's current state. Called by
## JobAdvancementNPC right before showing.
func refresh_for_local_player() -> void:
	var local_id: int = multiplayer.get_unique_id()
	var local_player: MultiplayerPlayerV2 = null
	for p in get_tree().get_nodes_in_group("Players"):
		if p.player_id == local_id:
			local_player = p
			break

	if not is_instance_valid(local_player):
		_body_label.text = "I cannot find your character."
		_current_label.text = ""
		_target_label.text = ""
		_advance_button.visible = false
		return

	var level: int = 1
	if is_instance_valid(local_player.level_component):
		level = local_player.level_component.level

	var current_class: int = Constants.ClassType.BEGINNER
	if is_instance_valid(local_player.class_component):
		current_class = local_player.class_component.current_class

	var current_name: String = _class_display_name(current_class)
	_current_label.text = "Class: %s    Level: %d" % [current_name, level]

	if JobAdvancementManager.can_advance(local_player):
		var new_name: String = JobAdvancementManager.get_advanced_class_name(current_class)
		_body_label.text = "You have walked the path of the %s long enough. Will you ascend to the rank of %s?" % [current_name, new_name]
		_target_label.text = "Will advance to: %s" % new_name
		_advance_button.visible = true
		_advance_button.disabled = false
	elif level < JobAdvancementManager.ADVANCEMENT_LEVEL:
		_body_label.text = "Return to me when you have reached Level %d. Strength comes only with experience." % JobAdvancementManager.ADVANCEMENT_LEVEL
		_target_label.text = "Required: Level %d" % JobAdvancementManager.ADVANCEMENT_LEVEL
		_advance_button.visible = false
	else:
		_body_label.text = "You have already chosen your specialized path. Walk it well."
		_target_label.text = ""
		_advance_button.visible = false


func _class_display_name(class_type: int) -> String:
	var key: String = Constants.ClassType.find_key(class_type)
	if key == null or key.is_empty():
		return "Unknown"
	# "SWORDSMAN" -> "Swordsman"
	return key.to_lower().capitalize()


func _on_advance_pressed() -> void:
	# Same path as the /advance chat command — server validates and broadcasts.
	JobAdvancementManager.request_advancement.rpc_id(1)
	visible = false
