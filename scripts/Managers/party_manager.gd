extends Node

signal party_created(party_id)
signal party_joined(player_id, party_id)
signal party_left(player_id, party_id)
signal member_added(party_id, player_id)
signal member_removed(party_id, player_id)
signal leader_changed(party_id, new_leader_id)
signal party_invite_received(inviter_id: int, inviter_username: String, party_id: int)
signal host_party_data_updated

var _parties = {} # { party_id: PartyData }
var _player_party_map = {} # { player_id: int (party_id) }
var _next_party_id = 1
var _player_info_cache = {} # { player_id: {"username": "..."} }

func _ready():                                                                                              
	#print("PartyManager: In _ready(), multiplayer.is_server(): ", multiplayer.is_server())                  
	if not multiplayer.is_server():                                                                         
		return 

func accept_invite(invitee_id: int, party_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if _player_party_map.has(invitee_id):
		return false

	if not _parties.has(party_id):
		return false

	var party: PartyData = _parties[party_id]
	var invite_found = false
	for inviter_id in party.invites.keys():
		if party.has_invite(inviter_id, invitee_id):
			party.remove_invite(inviter_id, invitee_id)
			invite_found = true
			break

	if not invite_found:
		return false

	party.add_member(invitee_id)
	_player_party_map[invitee_id] = party_id
	party_joined.emit(invitee_id, party_id)
	member_added.emit(party_id, invitee_id)
	_send_party_data_to_members(party_id)
	return true

func create_party(leader_id: int) -> int:
	if not multiplayer.is_server():
		return -1

	if _player_party_map.has(leader_id):
		#print("Player %d is already in a party." % leader_id)
		return -1

	var party_id = _next_party_id
	_next_party_id += 1

	var new_party = PartyData.new(party_id, leader_id)
	_parties[party_id] = new_party
	_player_party_map[leader_id] = party_id
	#print("Party %d created by leader %d" % [party_id, leader_id])
	party_created.emit(party_id)
	_send_party_data_to_members(party_id)
	return party_id

func send_invite(inviter_id: int, invitee_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	var inviter_party_id = _player_party_map.get(inviter_id)
	if not inviter_party_id:
		#print("Player %d is not in a party." % inviter_id)
		return false

	var party: PartyData = _parties[inviter_party_id]
	if not party.is_leader(inviter_id):
		#print("Player %d is not the leader of party %d." % [inviter_id, inviter_party_id])
		return false

	if _player_party_map.has(invitee_id):
		if BotManager.is_bot(invitee_id):
			leave_party(invitee_id)
		else:
			#print("Player %d is already in a party." % invitee_id)
			return false

	party.add_invite(inviter_id, invitee_id)

	if BotManager.is_bot(invitee_id):
		if BotManager.is_bot(inviter_id):
			if not _bot_evaluate_invite(inviter_id, invitee_id):
				party.remove_invite(inviter_id, invitee_id)
				#print("PartyManager: Bot %d declined invite from bot %d." % [invitee_id, inviter_id])
				return false
		#print("PartyManager: Bot %d auto-accepting invite to party %d." % [invitee_id, inviter_party_id])
		accept_invite(invitee_id, party.party_id)
		return true

	# Get inviter's username for the invite message
	var inviter_info = PlayerManager.get_player_info(inviter_id)
	var inviter_username = inviter_info.get("username", str(inviter_id))

	# Send RPC to invitee_id to notify them of the invite
	rpc_id(invitee_id, "_client_receive_party_invite", inviter_id, inviter_username, party.party_id)
	#print("Player %d invited player %d to party %d." % [inviter_id, invitee_id, inviter_party_id])
	return true

# Client-side RPC to receive party invite
@rpc("reliable" , "call_local")
func _client_receive_party_invite(inviter_id: int, inviter_username: String, party_id: int):
	if multiplayer.is_server():
		_host_receive_party_invite(inviter_id, inviter_username, party_id)
	else:
		#print("Client received party invite from %s (ID: %d) for party %d." % [inviter_username, inviter_id, party_id])
		# Emit a signal that the UI can connect to
		party_invite_received.emit(inviter_id, inviter_username, party_id)

func _host_receive_party_invite(inviter_id: int, inviter_username: String, party_id: int):
	#print("Host received party invite from %s (ID: %d) for party %d." % [inviter_username, inviter_id, party_id])
	party_invite_received.emit(inviter_id, inviter_username, party_id)

func leave_party(player_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	var party_id = _player_party_map.get(player_id)
	if not party_id:
		#print("Player %d is not in a party." % player_id)
		return false

	var party: PartyData = _parties[party_id]
	party.remove_member(player_id)
	_player_party_map.erase(player_id)
	#print("Player %d left party %d." % [player_id, party_id])
	party_left.emit(player_id, party_id)
	member_removed.emit(party_id, player_id)

	# Send RPC to the player who left to clear their local party status
	if not BotManager.is_bot(player_id):
		rpc_id(player_id, "_client_clear_my_party_status")

	if party.members.is_empty():
		_parties.erase(party_id)
		#print("Party %d disbanded as it has no members." % party_id)
	elif party.is_leader(player_id):
		# Leader left, promote a new leader
		var new_leader_id = party.members[0]
		party.leader_id = new_leader_id
		#print("Party %d leader changed to %d." % [party_id, new_leader_id])
		leader_changed.emit(party_id, new_leader_id)
		_send_party_data_to_members(party_id)
	else:
		_send_party_data_to_members(party_id)
	return true

func get_party_members(player_id: int) -> Array[int]:
	var party_id = _player_party_map.get(player_id)
	if party_id and _parties.has(party_id):
		return _parties[party_id].members
	return []

func get_party_leader(party_id: int) -> int:
	if _parties.has(party_id):
		return _parties[party_id].leader_id
	return -1

func get_player_party_id(player_id: int) -> int:
	return _player_party_map.get(player_id, -1)

func _bot_evaluate_invite(inviter_id: int, invitee_id: int) -> bool:
	var inviter_node := PlayerManager.get_player_node(inviter_id)
	var invitee_node := PlayerManager.get_player_node(invitee_id)
	if not is_instance_valid(inviter_node) or not is_instance_valid(invitee_node):
		return false
	var lvl_a: int = inviter_node.level_component.level if is_instance_valid(inviter_node.level_component) else 1
	var lvl_b: int = invitee_node.level_component.level if is_instance_valid(invitee_node.level_component) else 1
	if absi(lvl_a - lvl_b) > 10:
		return false
	# 70% base accept chance for bot-to-bot invites
	return randf() < 0.7


func get_party_member_info(player_id: int) -> Dictionary:
	return _player_info_cache.get(player_id, {})

func get_player_username(player_id: int) -> String:
	# First, try the client-side cache
	if _player_info_cache.has(player_id):
		return _player_info_cache[player_id].get("username", "Player " + str(player_id))

	# If on server or cache miss, use PlayerManager
	var player_info = PlayerManager.get_player_info(player_id)
	if player_info:
		return player_info.get("username", "Player " + str(player_id))
		
	return "Player " + str(player_id)

# RPCs for client-side calls to server
@rpc("any_peer", "call_local") # Execute on the remote peer (server)
func rpc_create_party():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	#print("RPC sender ID in PartyManager.rpc_create_party: ", sender_id)
	create_party(sender_id)
	
@rpc("any_peer", "call_local") # Execute on the remote peer (server)
func rpc_send_invite(invitee_name: String):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	
	var invitee_id = PlayerManager.get_player_id_from_name(invitee_name)
	if invitee_id == -1:
		for bot_id in BotManager.active_bots:
			if BotManager.active_bots[bot_id].username.to_lower() == invitee_name.to_lower():
				invitee_id = bot_id
				break
	if invitee_id == -1:
		#print("Server: Player not found by name: ", invitee_name)
		return

	if not _player_party_map.has(sender_id):
		create_party(sender_id)

	send_invite(sender_id, invitee_id)

@rpc("any_peer", "call_local") # Execute on the remote peer (server)
func rpc_accept_invite(party_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	#print("PartyManager: rpc_accept_invite called by sender ", sender_id, " for party ", party_id)
	accept_invite(sender_id, party_id)

@rpc("any_peer", "call_local") # Execute on the remote peer (server)
func rpc_leave_party():
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()
	#print("RPC sender ID in PartyManager.rpc_leave_party: ", sender_id)
	leave_party(sender_id)

@rpc("any_peer", "call_local") # Execute on the remote peer (server)
func rpc_change_leader(new_leader_id: int):
	var sender_id = multiplayer.get_remote_sender_id()
	if sender_id == 0:
		sender_id = multiplayer.get_unique_id()

	if not multiplayer.is_server():
		return

	var party_id = _player_party_map.get(sender_id)
	if not party_id:
		#print("Player %d is not in a party." % sender_id)
		return

	var party: PartyData = _parties[party_id]
	if not party.is_leader(sender_id):
		#print("Player %d is not the leader of party %d." % [sender_id, party_id])
		return

	if not party.members.has(new_leader_id):
		#print("Player %d is not a member of party %d." % [new_leader_id, party_id])
		return
	
	if party.leader_id == new_leader_id:
		return # No change needed

	party.leader_id = new_leader_id
	#print("Party %d leader changed to %d." % [party_id, new_leader_id])
	leader_changed.emit(party_id, new_leader_id)
	_send_party_data_to_members(party_id)

# Server-to-client synchronization
@rpc("reliable", "call_local")
func _client_update_party_data(party_data_dict: Dictionary):
	if multiplayer.is_server():
		return # Only clients should receive this

	var party_id = party_data_dict.get("party_id", -1)
	if party_id == -1:
		push_error("Received party data without valid party_id.")
		return

	# Update player info cache
	var members_info = party_data_dict.get("members", [])
	for member_data in members_info:
		_player_info_cache[member_data.id] = {
			"username": member_data.username,
			"level": member_data.level,
			"class_name": member_data.class_name
		}

	var new_party_data = PartyData.new(party_id, party_data_dict.get("leader_id"))
	
	# Add members one-by-one instead of direct assignment
	var member_ids = members_info.map(func(m): return m.id)
	for member_id in member_ids:
		if not new_party_data.members.has(member_id):
			new_party_data.add_member(member_id)

	new_party_data.invites = party_data_dict.get("invites", {})

	_parties[party_id] = new_party_data
	for member_id in member_ids:
		_player_party_map[member_id] = party_id
		
	#print("Client received party data for party %d: %s" % [party_id, party_data_dict])
	party_created.emit(party_id)

func _send_party_data_to_members(party_id: int):
	if not multiplayer.is_server():
		return

	var party: PartyData = _parties.get(party_id)
	if not party:
		return

	var members_with_info = []
	for member_id in party.members:
		var player_info = PlayerManager.get_player_info(member_id)
		var player_node = PlayerManager.get_player_node(member_id) # Get player node on server
		
		var player_class = "N/A"
		if player_node and player_node.class_component:
			player_class = player_node.class_component.get_class_name()
		var level = 1
		if player_node and player_node.level_component:
			level = player_node.level_component.level

		members_with_info.append({
			"id": member_id,
			"username": player_info.get("username", "Player " + str(member_id)),
			"level": level,
			"class_name": player_class
		})

	var party_data_to_send = {
		"party_id": party.party_id,
		"leader_id": party.leader_id,
		"members": members_with_info,
		"invites": party.invites
	}

	for member_id in party.members:
		if not BotManager.is_bot(member_id):
			rpc_id(member_id, "_client_update_party_data", party_data_to_send)

@rpc("reliable", "call_local")
func _client_clear_my_party_status():
	if multiplayer.is_server():
		return # Only clients should receive this
	var my_id = multiplayer.get_unique_id()
	if _player_party_map.has(my_id):
		var old_party_id = _player_party_map[my_id]
		_player_party_map.erase(my_id)
		# Also clear the party data if it was the only one the client knew about
		# This might be too aggressive if the client is tracking multiple parties (e.g., for invites)
		# For now, we'll just clear the player's own party membership.
		# If the party itself is disbanded, _client_update_party_data will not be sent for it.
		#print("Client: Cleared my party status. Was in party %d." % old_party_id)
		# Emit a signal to trigger UI update
		party_left.emit(my_id, old_party_id) # Re-use party_left signal for UI update

# Placeholder for PlayerManager integration
func _on_player_disconnected(player_id: int):
	if _player_party_map.has(player_id):
		leave_party(player_id)

# Placeholder for Quest System integration
func add_quest_to_party(party_id: int, quest_id: String):
	if not multiplayer.is_server():
		return

	if not _parties.has(party_id):
		#print("Party %d does not exist." % party_id)
		return

	var party: PartyData = _parties[party_id]
	if not party.has("active_quests"): # PartyData does not directly have active_quests. Need to add this to PartyData or handle differently.
		party["active_quests"] = [] # This line will cause an error on PartyData
	if not quest_id in party["active_quests"]:
		party["active_quests"].append(quest_id)
		_send_party_data_to_members(party_id)
		#print("Quest %s added to party %d." % [quest_id, party_id])

func remove_quest_from_party(party_id: int, quest_id: String):
	if not multiplayer.is_server():
		return

	if not _parties.has(party_id):
		#print("Party %d does not exist." % party_id)
		return

	var party: PartyData = _parties[party_id]
	if party.has("active_quests") and quest_id in party["active_quests"]:
		party["active_quests"].erase(quest_id)
		_send_party_data_to_members(party_id)
		#print("Quest %s removed from party %d." % [quest_id, party_id])

func notify_player_data_changed(player_id: int):
	if not multiplayer.is_server():
		return

	var party_id = _player_party_map.get(player_id)
	if not party_id:
		return

	# Skip sync for bot-only parties — no client needs the update
	var party: PartyData = _parties.get(party_id)
	if party:
		var has_real_player := false
		for mid in party.members:
			if not BotManager.is_bot(mid):
				has_real_player = true
				break
		if not has_real_player:
			return

	_send_party_data_to_members(party_id)
	host_party_data_updated.emit()
