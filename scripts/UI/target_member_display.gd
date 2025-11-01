extends HBoxContainer

class_name TargetMemberDisplay

@onready var name_label: Label = %NameLabel
@onready var health_bar: ProgressBar = %HealthBar

var _player_node: Node = null

func set_player_node(player_node: Node):
	if _player_node and is_instance_valid(_player_node) and _player_node.find_child("Health"):
		if _player_node.health_component.health_changed.is_connected(_on_health_changed):
			_player_node.health_component.health_changed.disconnect(_on_health_changed)

	_player_node = player_node

	if not is_instance_valid(_player_node) or not _player_node.find_child("Health"):
		name_label.text = "Invalid Target"
		health_bar.value = 0
		return

	name_label.text = _player_node.username # Assuming username property exists
	_player_node.health_component.health_changed.connect(_on_health_changed)
	_on_health_changed(_player_node.health_component.current_health, _player_node.health_component.max_health)

func _on_health_changed(current: float, max_value: float):
	health_bar.max_value = max_value
	health_bar.value = current
