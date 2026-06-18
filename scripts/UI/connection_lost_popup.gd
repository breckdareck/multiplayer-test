extends CanvasLayer

@onready var detail_label: Label = %DetailLabel
@onready var retry_button: Button = %RetryButton
@onready var login_button: Button = %LoginButton

var _last_ip: String = ""
var _last_port: int = 0

func _ready():
	retry_button.pressed.connect(_on_retry)
	login_button.pressed.connect(_on_return_to_login)
	visible = false

func show_popup(reason: String, ip: String, port: int):
	_last_ip = ip
	_last_port = port
	detail_label.text = reason
	visible = true

func _on_retry():
	detail_label.text = "Reconnecting to %s:%d..." % [_last_ip, _last_port]
	retry_button.disabled = true

	if not ClientManager.connection_succeeded.is_connected(_on_reconnect_success):
		ClientManager.connection_succeeded.connect(_on_reconnect_success)
	if not ClientManager.connection_failed.is_connected(_on_reconnect_failed):
		ClientManager.connection_failed.connect(_on_reconnect_failed)

	await MultiplayerManager.reset_data()
	ClientManager.connect_to_server(_last_ip, _last_port)

func _on_reconnect_success():
	_cleanup_signals()
	retry_button.disabled = false
	visible = false

func _on_reconnect_failed():
	_cleanup_signals()
	retry_button.disabled = false
	detail_label.text = "Reconnection failed. Server may be offline."

func _on_return_to_login():
	_cleanup_signals()
	visible = false
	get_tree().change_scene_to_file("res://scenes/Screens/LoginScreen.tscn")

func _cleanup_signals():
	if ClientManager.connection_succeeded.is_connected(_on_reconnect_success):
		ClientManager.connection_succeeded.disconnect(_on_reconnect_success)
	if ClientManager.connection_failed.is_connected(_on_reconnect_failed):
		ClientManager.connection_failed.disconnect(_on_reconnect_failed)
