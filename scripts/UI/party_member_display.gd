extends HBoxContainer

class_name PartyMemberDisplay

@onready var name_label = $"NameLabel"
@onready var health_bar = $"HealthBar"

var _player_node: MultiplayerPlayerV2
var _username: String
var _is_leader: bool

func _ready():
	# Assign stored data to UI elements after nodes are ready
	name_label.text = _username + (" (L)" if _is_leader else "")

	if is_instance_valid(_player_node) and is_instance_valid(_player_node.health_component):
		health_bar.max_value = _player_node.get_max_health()
		health_bar.value = _player_node.get_current_health()
		_player_node.health_component.health_changed.connect(_on_health_changed)

func set_player_data(player_node: MultiplayerPlayerV2, username: String, is_leader: bool):
	_player_node = player_node
	_username = username
	_is_leader = is_leader

	# If _ready has already been called, update immediately
	if is_node_ready():
		_ready()

func _on_health_changed(current_health: int, max_health: int):
	health_bar.max_value = max_health
	health_bar.value = current_health
