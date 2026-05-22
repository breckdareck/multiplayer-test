# enemy_state.gd
extends State
class_name EnemyState

# Override the base _play_animation to handle enemy animations
func _play_animation(anim_name: String) -> void:
	if not anim_name.is_empty():
		animations.play(anim_name)


## Shared aggro probe for the idle/patrol states. Returns the chase state when
## the enemy should pursue a target, otherwise null.
func _check_aggro() -> State:
	var enemy := parent as EnemyBase
	if enemy == null:
		return null
	if enemy.get_aggro_target() != null:
		return get_node_or_null("../chase")
	return null
