extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	if text.begins_with("/"):
		var parts: PackedStringArray = text.strip_edges().split(" ", false)
		var command: String = parts[0].to_lower()

		if command == "/trade":
			_handle_trade_command(parts)
			return

	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)


func _handle_trade_command(parts: PackedStringArray) -> void:
	if parts.size() < 2:
		add_system_message("Usage: /trade <username> | accept | confirm | cancel | status | coins <amount>", Color.GRAY)
		return

	var action: String = parts[1].to_lower()
	match action:
		"accept":
			TradeManager.accept_trade.rpc_id(1)
		"confirm":
			TradeManager.confirm_trade.rpc_id(1)
		"cancel":
			TradeManager.cancel_trade.rpc_id(1)
		"status":
			TradeManager.request_trade_status.rpc_id(1)
		"coins":
			if parts.size() >= 3:
				TradeManager.trade_offer_coins.rpc_id(1, int(parts[2]))
			else:
				add_system_message("Usage: /trade coins <amount>", Color.GRAY)
		_:
			# Treat as username for trade request
			TradeManager.request_trade.rpc_id(1, parts[1])

func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)
