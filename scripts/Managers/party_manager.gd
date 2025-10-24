class_name PartyManager
extends Node

## Manages party relationships between players
## This is a simple implementation - you can expand it as needed

var parties: Dictionary = {}  # party_id -> Array of player_ids
var player_parties: Dictionary = {}  # player_id -> party_id

func _ready():
	# Add to group for easy access
	add_to_group("party_manager")

func create_party(leader_player_id: int) -> String:
	"""Create a new party with the given leader"""
	var party_id = "party_" + str(leader_player_id) + "_" + str(Time.get_unix_time_from_system())
	parties[party_id] = [leader_player_id]
	player_parties[leader_player_id] = party_id
	print("PartyManager: Created party %s with leader %d" % [party_id, leader_player_id])
	return party_id

func join_party(player_id: int, party_id: String) -> bool:
	"""Add a player to an existing party"""
	if party_id not in parties:
		print("PartyManager: Party %s does not exist" % party_id)
		return false
	
	if player_id in parties[party_id]:
		print("PartyManager: Player %d already in party %s" % [player_id, party_id])
		return true
	
	parties[party_id].append(player_id)
	player_parties[player_id] = party_id
	print("PartyManager: Player %d joined party %s" % [player_id, party_id])
	return true

func leave_party(player_id: int) -> bool:
	"""Remove a player from their current party"""
	if player_id not in player_parties:
		print("PartyManager: Player %d is not in any party" % player_id)
		return false
	
	var party_id = player_parties[player_id]
	parties[party_id].erase(player_id)
	player_parties.erase(player_id)
	
	# If party is empty, remove it
	if parties[party_id].is_empty():
		parties.erase(party_id)
		print("PartyManager: Party %s disbanded" % party_id)
	else:
		print("PartyManager: Player %d left party %s" % [player_id, party_id])
	
	return true

func get_party_members(player_id: int) -> Array:
	"""Get all party members for a given player"""
	if player_id not in player_parties:
		return []
	
	var party_id = player_parties[player_id]
	return parties.get(party_id, [])

func get_party_member_players(player_id: int) -> Array[MultiplayerPlayerV2]:
	"""Get all party member player objects for a given player"""
	var member_ids = get_party_members(player_id)
	var member_players: Array[MultiplayerPlayerV2] = []
	
	for member_id in member_ids:
		var player = _get_player_by_id(member_id)
		if player:
			member_players.append(player)
	
	return member_players

func is_in_party(player_id: int) -> bool:
	"""Check if a player is in any party"""
	return player_id in player_parties

func _get_player_by_id(player_id: int) -> MultiplayerPlayerV2:
	"""Helper to find a player by their ID"""
	var all_players = get_tree().get_nodes_in_group("Players")
	for player in all_players:
		if player.has_method("get") and player.get("player_id") == player_id:
			return player
	return null
