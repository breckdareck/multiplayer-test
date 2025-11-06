extends MarginContainer

const LogMessageScene = preload("res://scenes/UI/LogMessage.tscn")

@export var max_messages: int = 10
@export var message_duration: float = 5.0 # Time before a message fades on its own

@onready var vbox: VBoxContainer = $VBoxContainer

func add_log(text: String, color: Color = Color.WHITE) -> void:
	# Create and add the new message
	var log_message = LogMessageScene.instantiate()
	vbox.add_child(log_message)
	log_message.set_text(text, color)
	log_message.fade_in()

	# Set a timer to remove this specific message after a duration
	var timer = get_tree().create_timer(message_duration)
	timer.timeout.connect(func():
		if is_instance_valid(log_message):
			log_message.fade_out()
	)

	# If limit is exceeded, remove the oldest message
	# Use a small delay to ensure layout is updated before checking
	await get_tree().process_frame
	if vbox.get_child_count() > max_messages:
		var oldest_message = vbox.get_child(0)
		if is_instance_valid(oldest_message):
			oldest_message.fade_out()
