extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)

@rpc("any_peer", "call_local", "reliable")
func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)
