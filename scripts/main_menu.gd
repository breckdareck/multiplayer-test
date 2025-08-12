extends Node

@onready var main_menu: Control = $"."
@onready var _host_button: Button = $MenuPanel/VBoxContainer/Host
@onready var _join_button: Button = $MenuPanel/VBoxContainer/Join
@onready var ip_address_input: LineEdit = $MenuPanel/VBoxContainer/IPAddress
@onready var _connection_status_label: Label = $MenuPanel/VBoxContainer/ConnectionStatus

@onready var connection_panel: Panel = $"../ConnectionPanel"
@onready var player_id_label: Label = $"../ConnectionPanel/PlayerIDLabel"


func host_game():
	MultiplayerManager.host_game()


func join_game():
	MultiplayerManager.join_game()
	
		
func disconnect_from_server():
	MultiplayerManager.reset_data()
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func setup_PID_label(is_host: bool, pid: int):
	if is_host:
		player_id_label.text = "HOST
		%s" % str(pid)
	else:
		player_id_label.text = "CLIENT
		%s" % str(pid)
