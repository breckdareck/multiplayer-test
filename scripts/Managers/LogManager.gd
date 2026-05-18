extends Node

var scrolling_log
var _log_file: FileAccess

func _ready():
	if OS.has_feature("dedicated_server") or (multiplayer and multiplayer.is_server()):
		var datetime = Time.get_datetime_string_from_system().replace(":", "").replace("-", "").replace("T", "_")
		var path = "user://server_log_%s.txt" % datetime
		_log_file = FileAccess.open(path, FileAccess.WRITE)
		if _log_file:
			print("LogManager: Logging to %s" % ProjectSettings.globalize_path(path))

func set_scrolling_log(log_node):
	scrolling_log = log_node

func add_scrolling_log(text: String, color: Color = Color.WHITE):
	if is_instance_valid(scrolling_log):
		scrolling_log.add_log(text, color)

func log_info(msg: String):
	_write_log("INFO", msg)
	add_scrolling_log(msg, Color.WHITE)

func log_warn(msg: String):
	_write_log("WARN", msg)
	add_scrolling_log(msg, Color.YELLOW)

func log_error(msg: String):
	_write_log("ERROR", msg)
	add_scrolling_log(msg, Color.RED)

func flush_and_close():
	if _log_file:
		_log_file.flush()
		_log_file.close()
		_log_file = null

func _write_log(level: String, msg: String):
	if not _log_file:
		return
	var timestamp = Time.get_datetime_string_from_system()
	_log_file.store_line("[%s] [%s] %s" % [timestamp, level, msg])
	_log_file.flush()
