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
	# Prefer the bound body, but fall back to the live local body if that ref is
	# stale (e.g. a recreate map-swap freed the body this popup was bound to). The
	# fallback guarantees the button always revives the current character instead of
	# silently no-op'ing on a freed node.
	var target = _player if is_instance_valid(_player) else MapManager.my_player_node
	if is_instance_valid(target):
		target.respawn.rpc()
	hide()
	InputManager.set_input_locked(false)

func _on_close_requested():
	# Don't allow closing via X button while dead
	pass
