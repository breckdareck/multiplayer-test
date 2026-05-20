extends Portal
class_name SecretPortal

## A hidden portal that becomes visible only when a player touches it.
## Place in hard-to-reach spots for discoverable secret areas.

@export var reveal_message: String = "You found a secret passage!"

func _ready():
	super._ready()
	# Start invisible — the sprite and label are hidden
	if has_node("Sprite2D"):
		$Sprite2D.visible = false
	interaction_label.visible = false

func _on_body_entered(body: Node2D):
	if body is MultiplayerPlayerV2 and body.player_id != 0:
		# Reveal the portal visually for this player
		if has_node("Sprite2D"):
			$Sprite2D.visible = true
		interaction_label.visible = true

		if body.has_method("set_current_portal"):
			body.set_current_portal(self)

		# Show discovery message (skip bots — they have no client to receive the RPC)
		if multiplayer.is_server() and not reveal_message.is_empty() and not BotManager.is_bot(body.player_id):
			ChatManager.add_system_message.rpc_id(body.player_id, reveal_message, Color.CYAN)

		#print("Player %d discovered secret portal to '%s'" % [body.player_id, target_map_id])

func _on_body_exited(body: Node2D):
	if body is MultiplayerPlayerV2 and body.player_id != 0:
		# Hide again when player leaves
		if has_node("Sprite2D"):
			$Sprite2D.visible = false
		interaction_label.visible = false

		if body.has_method("clear_current_portal"):
			body.clear_current_portal()
