extends Node

signal message_received(message, color)

# This is a placeholder for the player's name
var player_name = "Player"

func _ready():
    # In a real game, you would get the player's name after they log in
    pass

# Called from the ChatWindow UI
func send_chat_message(text: String):
    # In a multiplayer game, you would send this to the server
    # For now, we'll just broadcast it locally
    broadcast_message.rpc(player_name, text)

# Called from anywhere to add a system message (e.g., item pickups)
func add_system_message(text: String, color: Color = Color.WHITE):
    message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
    var message = "%s: %s" % [sender_name, text]
    message_received.emit(message, Color.WHITE)
