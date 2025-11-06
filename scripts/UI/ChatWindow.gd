extends MarginContainer

@onready var history: RichTextLabel = $VBoxContainer/History
@onready var input_line: LineEdit = $VBoxContainer/InputLine

func _ready():
	input_line.text_submitted.connect(_on_text_submitted)
	ChatManager.message_received.connect(add_message)

func _on_text_submitted(text: String):
	if text.is_empty():
		return
	ChatManager.send_chat_message(text)
	input_line.clear()

func add_message(message: String, color: Color):
	history.push_color(color)
	history.append_text("\n" + message)
	history.pop()

func add_system_message(message: String, color: Color):
	history.push_color(color)
	history.append_text("\n" + message)
	history.pop()
