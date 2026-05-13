extends Area2D

func _on_body_entered(body: Node2D) -> void:
	_multiplayer_dead(body)

func _multiplayer_dead(body: Node2D) -> void:
	# The server is the authority. It checks if the body is a player
	# and if they aren't already marked as dead to prevent multiple triggers.
	if multiplayer.is_server() and body is MultiplayerPlayerV2:
		if body.health_component and not body.health_component.is_dead:
			# Set health to 0 so the normal death flow triggers (health setter → die → signals).
			# This ensures current_health is properly synced and respawn can restore it.
			body.health_component.current_health = 0
