extends Window

class_name PartyInvitePopup

@warning_ignore("unused_signal")
signal invite_responded(accepted: bool, party_id: int)

@onready var message_label: Label = %MessageLabel
@onready var accept_button: Button = %AcceptButton
@onready var decline_button: Button = %DeclineButton

var _inviter_id: int
var _party_id: int

## The popup answers or it expires — a stale invite outlives the party that
## sent it (a bot abandons an unanswered invite after 30s), and accepting a
## dead party is a silent no-op. Kept under the bot's 30s window.
const INVITE_TTL: float = 25.0

func _ready():
	accept_button.pressed.connect(_on_accept_button_pressed)
	decline_button.pressed.connect(_on_decline_button_pressed)
	get_tree().create_timer(INVITE_TTL).timeout.connect(func():
		if is_instance_valid(self):
			hide()
			queue_free())

func set_invite_data(inviter_id: int, inviter_username: String, party_id: int):
	_inviter_id = inviter_id
	_party_id = party_id
	message_label.text = "%s has invited you to join their party." % inviter_username

func _on_accept_button_pressed():
	PartyManager.rpc_id(1, "rpc_accept_invite", _party_id)
	hide()
	queue_free()

func _on_decline_button_pressed():
	# Optional: Notify PartyManager that the invite was declined.
	# PartyManager.rpc_id(1, "rpc_decline_invite", _party_id)
	#print("Declined invite from %d for party %d." % [_inviter_id, _party_id])
	hide()
	queue_free()
