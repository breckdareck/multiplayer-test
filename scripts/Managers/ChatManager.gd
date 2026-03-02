extends Node

signal message_received(message, color)

var local_player_node: MultiplayerPlayerV2 = null

# Dice roll challenges: challenger_peer_id -> { target_peer_id, wager, timestamp }
var _dice_challenges: Dictionary = {}
const DICE_PROXIMITY_RANGE: float = 150.0
const DICE_CHALLENGE_TIMEOUT: float = 30.0

func _ready():
	pass

func register_local_player(player_node: MultiplayerPlayerV2):
	local_player_node = player_node

func send_chat_message(text: String):
	if text.begins_with("/"):
		var parts: PackedStringArray = text.strip_edges().split(" ", false)
		var command: String = parts[0].to_lower()
		if command == "/roll":
			_request_dice_roll.rpc_id(1, text.strip_edges())
			return

	if local_player_node:
		broadcast_message.rpc(local_player_node.username, text)
	else:
		broadcast_message.rpc("Player", text)

func add_system_message(text: String, color: Color = Color.WHITE):
	message_received.emit(text, color)

@rpc("any_peer", "call_local", "reliable")
func broadcast_message(sender_name: String, text: String):
	var message = "%s: %s" % [sender_name, text]
	message_received.emit(message, Color.WHITE)


# ═══════════════════════════════════════════════════════════════════════════
# DICE ROLL
# ═══════════════════════════════════════════════════════════════════════════

@rpc("any_peer", "call_remote", "reliable")
func _request_dice_roll(raw_text: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = 1

	var parts: PackedStringArray = raw_text.split(" ", false)
	# /roll accept — accept a pending challenge
	if parts.size() == 2 and parts[1].to_lower() == "accept":
		_handle_dice_accept(sender_id)
		return

	# /roll <wager> <target_username>
	if parts.size() < 3:
		_send_system_message.rpc_id(sender_id, "Usage: /roll <wager> <target_username>  or  /roll accept", Color.GRAY)
		return

	var wager: int = int(parts[1])
	var target_username: String = parts[2]

	if wager <= 0:
		_send_system_message.rpc_id(sender_id, "Wager must be a positive number.", Color.RED)
		return

	var sender_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(sender_id)
	if not is_instance_valid(sender_node):
		return

	# Find target player
	var target_node: MultiplayerPlayerV2 = _find_player_by_username(target_username)
	if not is_instance_valid(target_node):
		_send_system_message.rpc_id(sender_id, "Player '%s' not found." % target_username, Color.RED)
		return

	if target_node.player_id == sender_id:
		_send_system_message.rpc_id(sender_id, "You can't challenge yourself.", Color.RED)
		return

	# Proximity check
	if sender_node.global_position.distance_to(target_node.global_position) > DICE_PROXIMITY_RANGE:
		_send_system_message.rpc_id(sender_id, "You must be closer to %s to challenge them." % target_username, Color.RED)
		return

	# Check funds
	if sender_node.player_inventory.monies_amount < wager:
		_send_system_message.rpc_id(sender_id, "You don't have enough coins. (Need %d)" % wager, Color.RED)
		return

	if target_node.player_inventory.monies_amount < wager:
		_send_system_message.rpc_id(sender_id, "%s doesn't have enough coins." % target_username, Color.RED)
		return

	# Store challenge
	_dice_challenges[sender_id] = {
		"target_id": target_node.player_id,
		"wager": wager,
		"timestamp": Time.get_unix_time_from_system(),
	}

	_send_system_message.rpc_id(sender_id, "Dice challenge sent to %s for %d coins!" % [target_username, wager], Color.YELLOW)
	_send_system_message.rpc_id(target_node.player_id, "%s challenges you to a dice roll for %d coins! Type /roll accept" % [sender_node.username, wager], Color.YELLOW)


func _handle_dice_accept(accepter_id: int) -> void:
	# Find a challenge targeting this player
	var challenger_id: int = -1
	for cid in _dice_challenges.keys():
		var challenge: Dictionary = _dice_challenges[cid]
		if challenge.target_id == accepter_id:
			# Check timeout
			if Time.get_unix_time_from_system() - challenge.timestamp > DICE_CHALLENGE_TIMEOUT:
				_dice_challenges.erase(cid)
				continue
			challenger_id = cid
			break

	if challenger_id == -1:
		_send_system_message.rpc_id(accepter_id, "No pending dice challenge found.", Color.RED)
		return

	var challenge: Dictionary = _dice_challenges[challenger_id]
	_dice_challenges.erase(challenger_id)
	var wager: int = challenge.wager

	var challenger_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(challenger_id)
	var accepter_node: MultiplayerPlayerV2 = PlayerManager.get_player_node(accepter_id)

	if not is_instance_valid(challenger_node) or not is_instance_valid(accepter_node):
		_send_system_message.rpc_id(accepter_id, "Dice roll cancelled — player disconnected.", Color.RED)
		return

	# Re-check funds
	if challenger_node.player_inventory.monies_amount < wager:
		_send_system_message.rpc_id(accepter_id, "%s no longer has enough coins." % challenger_node.username, Color.RED)
		_send_system_message.rpc_id(challenger_id, "Dice roll cancelled — insufficient funds.", Color.RED)
		return
	if accepter_node.player_inventory.monies_amount < wager:
		_send_system_message.rpc_id(accepter_id, "You don't have enough coins. (Need %d)" % wager, Color.RED)
		_send_system_message.rpc_id(challenger_id, "Dice roll cancelled — %s has insufficient funds." % accepter_node.username, Color.RED)
		return

	# Roll dice (1-100)
	var roll_a: int = randi_range(1, 100)
	var roll_b: int = randi_range(1, 100)

	# Reroll on tie
	while roll_a == roll_b:
		roll_a = randi_range(1, 100)
		roll_b = randi_range(1, 100)

	var winner_node: MultiplayerPlayerV2
	var loser_node: MultiplayerPlayerV2
	var winner_roll: int
	var loser_roll: int

	if roll_a > roll_b:
		winner_node = challenger_node
		loser_node = accepter_node
		winner_roll = roll_a
		loser_roll = roll_b
	else:
		winner_node = accepter_node
		loser_node = challenger_node
		winner_roll = roll_b
		loser_roll = roll_a

	# Transfer coins
	loser_node.player_inventory.monies_amount -= wager
	winner_node.player_inventory.monies_amount += wager

	# Sync monies to clients
	loser_node.player_inventory.set_monies_rpc.rpc(loser_node.player_inventory.monies_amount)
	winner_node.player_inventory.set_monies_rpc.rpc(winner_node.player_inventory.monies_amount)

	# Announce to both players
	var result_msg: String = "[DICE] %s rolled %d vs %s rolled %d — %s wins %d coins!" % [
		challenger_node.username, roll_a,
		accepter_node.username, roll_b,
		winner_node.username, wager
	]

	# Broadcast result to players on the same map
	var map_id: String = MapManager.get_player_map(challenger_id)
	if not map_id.is_empty():
		var players_on_map: Array = MapManager.get_players_on_map(map_id)
		for pid in players_on_map:
			_send_system_message.rpc_id(pid, result_msg, Color.YELLOW)
	else:
		_send_system_message.rpc_id(challenger_id, result_msg, Color.YELLOW)
		_send_system_message.rpc_id(accepter_id, result_msg, Color.YELLOW)


func _find_player_by_username(target_username: String) -> MultiplayerPlayerV2:
	for map_id in MapManager.active_maps.keys():
		var map_instance = MapManager.active_maps[map_id].scene_instance
		if not is_instance_valid(map_instance):
			continue
		var players_node = map_instance.get_node_or_null("Players")
		if not players_node:
			continue
		for child in players_node.get_children():
			if child is MultiplayerPlayerV2 and child.username == target_username:
				return child
	return null


@rpc("authority", "call_local", "reliable")
func _send_system_message(text: String, color: Color) -> void:
	message_received.emit(text, color)
