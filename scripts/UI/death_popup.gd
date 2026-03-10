extends Window

class_name DeathPopup

var _player

@onready var message_label: Label = %MessageLabel
@onready var respawn_button: Button = %RespawnButton

func _ready():
	respawn_button.pressed.connect(_on_respawn_button_pressed)
	close_requested.connect(_on_close_requested)

func set_player(player) -> void:
	_player = player

func _on_respawn_button_pressed():
	if is_instance_valid(_player):
		_player.respawn.rpc()
	hide()

func _on_close_requested():
	# Don't allow closing via X button while dead
	pass
