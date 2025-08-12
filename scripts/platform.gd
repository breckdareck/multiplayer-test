extends AnimatableBody2D

@export var anim_player_optional: AnimationPlayer

func _on_player_connected(_id):
	if not multiplayer.is_server():
		anim_player_optional.stop()
		anim_player_optional.set_active(false)

func _ready():
	if anim_player_optional:
		multiplayer.peer_connected.connect(_on_player_connected)	
