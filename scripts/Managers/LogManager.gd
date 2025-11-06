extends Node

var scrolling_log

func set_scrolling_log(log_node):
	scrolling_log = log_node

func add_scrolling_log(text: String, color: Color = Color.WHITE):
	if is_instance_valid(scrolling_log):
		scrolling_log.add_log(text, color)
	ChatManager.add_system_message(text, color)
