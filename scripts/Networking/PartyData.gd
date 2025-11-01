extends RefCounted

class_name PartyData

var party_id: int
var leader_id: int
var members: Array[int] = []
var invites: Dictionary = {} # { inviter_id: Array[int] (list of invitee_ids) }

func _init(p_party_id: int, p_leader_id: int):
	party_id = p_party_id
	leader_id = p_leader_id
	members.append(p_leader_id)

func add_member(player_id: int) -> void:
	if not members.has(player_id):
		members.append(player_id)

func remove_member(player_id: int) -> void:
	if members.has(player_id):
		members.erase(player_id)

func is_member(player_id: int) -> bool:
	return members.has(player_id)

func is_leader(player_id: int) -> bool:
	return leader_id == player_id

func add_invite(inviter_id: int, invitee_id: int) -> void:
	if not invites.has(inviter_id):
		invites[inviter_id] = []
	if not invites[inviter_id].has(invitee_id):
		invites[inviter_id].append(invitee_id)

func remove_invite(inviter_id: int, invitee_id: int) -> void:
	if invites.has(inviter_id) and invites[inviter_id].has(invitee_id):
		invites[inviter_id].erase(invitee_id)
		if invites[inviter_id].is_empty():
			invites.erase(inviter_id)

func has_invite(inviter_id: int, invitee_id: int) -> bool:
	return invites.has(inviter_id) and invites[inviter_id].has(invitee_id)

func get_all_invitees_for_inviter(inviter_id: int) -> Array[int]:
	return invites.get(inviter_id, [])
