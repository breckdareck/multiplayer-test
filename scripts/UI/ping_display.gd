extends Label

var _ping_timer: float = 0.0
var _ping_send_time: float = 0.0
const PING_INTERVAL: float = 2.0

func _ready():
	text = "Ping: --"
	add_theme_color_override("font_color", Color.WHITE)

func _process(delta: float):
	if multiplayer.is_server():
		visible = false
		return

	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_ping_send_time = Time.get_ticks_msec()
		_ping_request.rpc_id(1)

@rpc("any_peer", "call_remote", "unreliable")
func _ping_request():
	if not multiplayer.is_server():
		return
	var sender = multiplayer.get_remote_sender_id()
	_ping_response.rpc_id(sender)

@rpc("authority", "call_remote", "unreliable")
func _ping_response():
	var rtt = Time.get_ticks_msec() - _ping_send_time
	text = "Ping: %dms" % rtt
	if rtt < 80:
		add_theme_color_override("font_color", Color.GREEN)
	elif rtt < 150:
		add_theme_color_override("font_color", Color.YELLOW)
	else:
		add_theme_color_override("font_color", Color.RED)
