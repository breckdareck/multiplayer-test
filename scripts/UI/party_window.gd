extends Window


var party_member_display_scene = preload("res://scenes/UI/party_member_display.tscn")

@onready var create_party_button = $"VBoxContainer/CreatePartyButton"
@onready var player_id_input = $"VBoxContainer/PlayerIDInput"
@onready var invite_player_button = $"VBoxContainer/InvitePlayerButton"
@onready var leave_party_button = $"VBoxContainer/LeavePartyButton"
@onready var party_members_container = $"VBoxContainer/PartyMembersContainer"

func _ready():
	create_party_button.pressed.connect(self._on_create_party_button_pressed)
	invite_player_button.pressed.connect(self._on_invite_player_button_pressed)
	leave_party_button.pressed.connect(self._on_leave_party_button_pressed)

	# Connect to PartyManager signals
	PartyManager.party_created.connect(self._on_party_created)
	PartyManager.party_joined.connect(self._on_party_joined)
	PartyManager.party_left.connect(self._on_party_left)
	PartyManager.member_added.connect(self._on_member_added)
	PartyManager.member_removed.connect(self._on_member_removed)
	PartyManager.leader_changed.connect(self._on_leader_changed)

	_update_party_display()

func _on_create_party_button_pressed():
	print("My unique ID: ", multiplayer.get_unique_id())
	print("Attempting to create party...")
	PartyManager.rpc_id(1, "rpc_create_party")

func _on_invite_player_button_pressed():
	var invitee_id_text = player_id_input.text
	if invitee_id_text.is_empty() or not invitee_id_text.is_valid_int():
		print("Invalid player ID for invite.")
		return
	var invitee_id = int(invitee_id_text)
	print("Attempting to invite player %d..." % invitee_id)
	PartyManager.rpc("rpc_send_invite", invitee_id)

func _on_leave_party_button_pressed():
	print("Attempting to leave party...")
	PartyManager.rpc_id(1, "rpc_leave_party")

func _on_party_created(party_id: int):
	print("UI: Party %d created!" % party_id)
	_update_party_display()

func _on_party_joined(player_id: int, party_id: int):
	print("UI: Player %d joined party %d!" % [player_id, party_id])
	_update_party_display()

func _on_party_left(player_id: int, party_id: int):
	print("UI: Player %d left party %d!" % [player_id, party_id])
	_update_party_display()

func _on_member_added(party_id: int, player_id: int):
	print("UI: Member %d added to party %d!" % [player_id, party_id])
	_update_party_display()

func _on_member_removed(party_id: int, player_id: int):
	print("UI: Member %d removed from party %d!" % [player_id, party_id])
	_update_party_display()

func _on_leader_changed(party_id: int, new_leader_id: int):
	print("UI: Party %d leader changed to %d!" % [party_id, new_leader_id])
	_update_party_display()

func _update_party_display():
	var my_id = multiplayer.get_unique_id()
	print("UI: _update_party_display called. My ID: ", my_id)
	var my_party_id = PartyManager.get_player_party_id(my_id)
	print("UI: My Party ID: ", my_party_id)

	# Clear existing member displays
	for child in party_members_container.get_children():
		child.queue_free()

	if my_party_id != -1:
		var members = PartyManager.get_party_members(my_id)
		var leader_id = PartyManager.get_party_leader(my_party_id)
		print("UI: Party Members: ", members, ", Leader ID: ", leader_id)
		
		for member_id in members:
			var player_node = PlayerManager.get_player_node(member_id)
			if player_node:
				var member_display = party_member_display_scene.instantiate()
				var username = player_node.username # Assuming username is directly accessible
				var current_health = player_node.get_current_health()
				var max_health = player_node.get_max_health()
				var is_leader = (member_id == leader_id)
				member_display.set_player_data(player_node, username, is_leader)
				party_members_container.add_child(member_display)
			else:
				print("UI: Could not find player node for member ID: ", member_id)
	else:
		var no_party_label = Label.new()
		no_party_label.text = "Not in a party."
		party_members_container.add_child(no_party_label)

	# Enable/disable buttons based on party status
	create_party_button.disabled = (my_party_id != -1)
	invite_player_button.disabled = (my_party_id == -1 or PartyManager.get_party_leader(my_party_id) != my_id)
	leave_party_button.disabled = (my_party_id == -1)
