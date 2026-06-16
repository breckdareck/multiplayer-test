extends MarginContainer

@onready var history: RichTextLabel = $VBoxContainer/History
@onready var input_line: LineEdit = $VBoxContainer/InputLine

func _ready():
	input_line.text_submitted.connect(_on_text_submitted)
	input_line.focus_entered.connect(_on_input_line_focus_entered)
	input_line.focus_exited.connect(_on_input_line_focus_exited)
	ChatManager.message_received.connect(add_message)
	_apply_text_size(UserConfig.chat_text_size)
	UserConfig.chat_text_size_changed.connect(_apply_text_size)


## Player-adjustable chat font size (options menu -> UserConfig).
func _apply_text_size(text_size: int) -> void:
	history.add_theme_font_size_override("normal_font_size", text_size)
	history.add_theme_font_size_override("bold_font_size", text_size)
	history.add_theme_font_size_override("italics_font_size", text_size)
	input_line.add_theme_font_size_override("font_size", text_size)

func _on_input_line_focus_entered():
	InputManager.set_input_locked(true)

func _on_input_line_focus_exited():
	InputManager.set_input_locked(false)

func _on_text_submitted(text: String):
	if text.is_empty():
		# Enter on an empty line closes the input. Without the release the
		# focus_exited -> InputManager unlock never fires and movement stays
		# locked until Esc.
		input_line.release_focus()
		return
	ChatManager.send_chat_message(text)
	input_line.clear()
	input_line.release_focus()

func add_message(message: String, color: Color):
	history.push_color(color)
	history.append_text("\n" + message)
	history.pop()

func add_system_message(message: String, color: Color):
	history.push_color(color)
	history.append_text("\n" + message)
	history.pop()

func _unhandled_input(event: InputEvent):
	if input_line.has_focus() and event.is_action_pressed("ui_cancel"):
		input_line.release_focus()
	elif not input_line.has_focus() and event is InputEventKey and event.pressed and event.keycode == KEY_ENTER:
		input_line.grab_focus()
		get_viewport().set_input_as_handled()
