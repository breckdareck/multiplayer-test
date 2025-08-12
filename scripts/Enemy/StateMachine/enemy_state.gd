# enemy_state.gd
extends State
class_name EnemyState

# Override the base _play_animation to handle enemy animations
func _play_animation(anim_name: String) -> void:
	if not anim_name.is_empty():
		animations.play(anim_name)
