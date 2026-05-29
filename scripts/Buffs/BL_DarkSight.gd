extends Node

## Buff logic for the Dagger discipline's Vanish.
## Sets an is_invisible meta flag on the player so enemy AI skips them,
## and makes the sprite semi-transparent as a visual indicator.

var source_ability_level: int = 1

func on_apply(owner_node: Node, _active_buff) -> void:
	owner_node.set_meta("is_invisible", true)
	_set_sprite_alpha(owner_node, 0.3)
	print("Vanish (Level %d) activated — %s is now invisible!" % [
		source_ability_level, owner_node.name])

func on_remove(owner_node: Node, _active_buff) -> void:
	owner_node.set_meta("is_invisible", false)
	_set_sprite_alpha(owner_node, 1.0)
	print("Vanish expired on %s" % owner_node.name)

func on_tick(_owner_node: Node, _active_buff, _delta: float) -> void:
	pass

func _set_sprite_alpha(owner_node: Node, alpha: float) -> void:
	var sprite := owner_node.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite:
		sprite.modulate.a = alpha
	if owner_node.has_method("sync_dark_sight_visual"):
		owner_node.sync_dark_sight_visual.rpc(alpha)
