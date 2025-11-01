extends Window

class_name PartyInvitePopup

signal invite_responded(accepted: bool, party_id: int)

@onready var message_label = $"VBoxContainer/MessageLabel"
@onready var accept_button = $"VBoxContainer/HBoxContainer/AcceptButton"
@onready var decline_button = $"VBoxContainer/HBoxContainer/DeclineButton"

var _inviter_id: int
var _party_id: int

func _ready():
	accept_button.pressed.connect(self._on_accept_button_pressed)
	decline_button.pressed.connect(self._on_decline_button_pressed)

func set_invite_data(inviter_id: int, inviter_username: String, party_id: int):
	_inviter_id = inviter_id
	_party_id = party_id
	message_label.text = "%s (ID: %d) has invited you to join their party (ID: %d)." % [inviter_username, inviter_id, party_id]

func _on_accept_button_pressed():
	print("PartyInvitePopup: Attempting to accept invite for party ", _party_id, " as player ", multiplayer.get_unique_id())
	PartyManager.rpc_id(1, "rpc_accept_invite", _party_id)
	hide()
	queue_free()

func _on_decline_button_pressed():
	# TODO: Implement decline logic in PartyManager
	print("Declined invite from %d for party %d." % [_inviter_id, _party_id])
	hide()
	queue_free()
