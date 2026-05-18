extends MarginContainer

@onready var history: RichTextLabel = $VBoxContainer/History
@onready var input_line: LineEdit = $VBoxContainer/InputLine

func _ready():
	input_line.text_submitted.connect(_on_text_submitted)
	input_line.focus_entered.connect(_on_input_line_focus_entered)
	input_line.focus_exited.connect(_on_input_line_focus_exited)
	ChatManager.message_received.connect(add_message)

func _on_input_line_focus_entered():
	InputManager.set_input_locked(true)

func _on_input_line_focus_exited():
	InputManager.set_input_locked(false)

func _on_text_submitted(text: String):
	if text.is_empty():
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
