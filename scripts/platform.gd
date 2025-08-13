extends AnimatableBody2D

@export var anim_player_optional: AnimationPlayer

func _ready():
	print("Platform: OnReady called")
	if not multiplayer.is_server() and anim_player_optional:
		print("Player: %s stopping platform" % str(multiplayer.get_unique_id()) )
		anim_player_optional.stop()
		anim_player_optional.set_active(false)
