class_name TradeRequestPopup
extends Panel

## A small accept/decline popup shown when another player requests a trade.
## Accepting tells the server to open a trade session; declining dismisses it.
## Built programmatically to match the PlayerContextMenu / TradeWindow style.

const POPUP_WIDTH: float = 240.0
const POPUP_HEIGHT: float = 96.0
## Auto-dismiss if the request is not answered — keeps a stale popup from
## lingering after the requester has cancelled or moved on.
const TIMEOUT: float = 20.0

var _answered: bool = false
var _life_timer: float = 0.0


static func create(requester_name: String) -> TradeRequestPopup:
	var popup := TradeRequestPopup.new()
	popup.custom_minimum_size = Vector2(POPUP_WIDTH, POPUP_HEIGHT)
	popup.size = Vector2(POPUP_WIDTH, POPUP_HEIGHT)
	popup.visible = false
	popup.mouse_filter = Control.MOUSE_FILTER_STOP
	popup.add_to_group("ui_window")

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.15, 0.97)
	bg.border_color = Color(0.4, 0.4, 0.5, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	popup.add_theme_stylebox_override("panel", bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	popup.add_child(root)

	var label := Label.new()
	label.text = "%s wants to trade with you." % requester_name
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(label)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	root.add_child(buttons)

	var accept := Button.new()
	accept.text = "Accept"
	accept.custom_minimum_size = Vector2(100, 26)
	accept.add_theme_font_size_override("font_size", 11)
	accept.pressed.connect(popup._on_accept)
	buttons.add_child(accept)

	var decline := Button.new()
	decline.text = "Decline"
	decline.custom_minimum_size = Vector2(100, 26)
	decline.add_theme_font_size_override("font_size", 11)
	decline.pressed.connect(popup._on_decline)
	buttons.add_child(decline)

	return popup


func present() -> void:
	var vp_size := get_viewport_rect().size
	# Anchor near the top-centre, below where party invites appear.
	global_position = Vector2((vp_size.x - size.x) * 0.5, 120.0)
	visible = true
	move_to_front()


func _process(delta: float) -> void:
	if _answered:
		return
	_life_timer += delta
	if _life_timer >= TIMEOUT:
		# Treat a timed-out request as a decline so the server clears it.
		_on_decline()


func _on_accept() -> void:
	if _answered:
		return
	_answered = true
	TradeManager.rpc_accept_trade_request.rpc_id(1)
	queue_free()


func _on_decline() -> void:
	if _answered:
		return
	_answered = true
	TradeManager.rpc_decline_trade_request.rpc_id(1)
	queue_free()
