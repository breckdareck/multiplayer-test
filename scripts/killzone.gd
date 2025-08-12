extends Area2D

@onready var timer: Timer = $Timer

func _on_body_entered(body: Node2D) -> void:
	# The robust way to check for multiplayer is to see if a peer is active.
	if not multiplayer.has_multiplayer_peer():
		# --- Single-player logic ---
		Engine.time_scale = 0.5
		# Add a safety check in case something other than the player enters
		if body.has_node("CollisionShape2D"):
			body.get_node("CollisionShape2D").queue_free()
		timer.start()
	else:
		# --- Multiplayer logic ---
		_multiplayer_dead(body)

func _multiplayer_dead(body: Node2D) -> void:
	# The server is the authority. It checks if the body is a player
	# and if they aren't already marked as dead to prevent multiple triggers.
	if multiplayer.is_server() and body is MultiplayerPlayer:
		if body.health_component and not body.health_component.is_dead:
			# The server tells the player's HealthComponent to initiate the death sequence.
			body.health_component.die.rpc()

func _on_timer_timeout() -> void:
	# This timer is only used for single-player mode.
	Engine.time_scale = 1
	get_tree().reload_current_scene()
