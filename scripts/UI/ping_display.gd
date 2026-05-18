extends Label

var _ping_timer: float = 0.0
var _ping_send_time: float = 0.0
const PING_INTERVAL: float = 2.0

func _ready():
	text = "Ping: --"
	add_theme_color_override("font_color", Color.WHITE)
	add_theme_constant_override("outline_size", 3)
	add_theme_color_override("font_outline_color", Color.BLACK)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MultiplayerManager.set_ping_display(self)

func _process(delta: float):
	if multiplayer.is_server():
		visible = false
		return
	if not multiplayer.has_multiplayer_peer():
		return

	_ping_timer += delta
	if _ping_timer >= PING_INTERVAL:
		_ping_timer = 0.0
		_ping_send_time = Time.get_ticks_msec()
		MultiplayerManager._ping_request.rpc_id(1)
