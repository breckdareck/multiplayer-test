extends Area2D

func _on_body_entered(body: Node2D) -> void:
		_multiplayer_dead(body)

func _multiplayer_dead(body: Node2D) -> void:
	# The server is the authority. It checks if the body is a player
	# and if they aren't already marked as dead to prevent multiple triggers.
	if multiplayer.is_server() and body is MultiplayerPlayerV2:
		if body.health_component and not body.health_component.is_dead:
			# The server tells the player's HealthComponent to initiate the death sequence.
			body.health_component.die.rpc()
