class_name MainMenu
extends Node

func _ready():
	AudioManager.play_song("res://assets/music/main_menu.mp3")

const SWORDSMAN_PORTRAIT = preload("res://assets/UI/swordsman_portrait.tres")
const ARCHER_PORTRAIT = preload("res://assets/UI/archer_portrait.tres")
const MAGE_PORTRAIT = preload("res://assets/UI/mage_portrait.tres")
const BEGINNER_PORTRAIT = preload("uid://c7usopkgeat5h")
const ROGUE_PORTRAIT = preload("uid://cgx33w5mdt6ar")

var selected_character: Constants.ClassType = Constants.ClassType.SWORDSMAN

@onready var main_menu: Control = $"."
@onready var username_input: LineEdit = $MenuPanel/VBoxContainer/Username
@onready var host_button: Button = $MenuPanel/VBoxContainer/Host
@onready var join_button: Button = $MenuPanel/VBoxContainer/Join
@onready var ip_address_input: LineEdit = $MenuPanel/VBoxContainer/IPAddress
@onready var connection_status_label: Label = $MenuPanel/VBoxContainer/ConnectionStatus

@onready var connection_panel: Panel = $"../ConnectionPanel"
@onready var player_id_label: Label = $"../ConnectionPanel/PlayerIDLabel"

@onready var left_button: Button = $CharacterSelectPanel/LeftButton
@onready var character_portrait: TextureRect = $CharacterSelectPanel/CharacterPortrait
@onready var right_button: Button = $CharacterSelectPanel/RightButton


func host_game():
	MultiplayerManager.host_game()


func join_game():
	MultiplayerManager.join_game()
	
		
func disconnect_from_server():
	MultiplayerManager.reset_data()
	MapManager.reset_client_state()
	get_tree().change_scene_to_file("res://scenes/UI/LoginScreen.tscn")
	

func change_channel(value: int):
	MultiplayerManager.switch_channel(ClientManager.current_server_port + value)


func setup_PID_label(is_host: bool, pid: int):
	if is_host:
		player_id_label.text = "HOST
		%s" % str(pid)
	else:
		player_id_label.text = "CLIENT
		%s" % str(pid)


func get_username() -> String:
	#print("MainMenu: Returning username: ", username_input.text)
	return username_input.text

func change_character(value: int):
	selected_character += value
	if selected_character > len(Constants.ClassType) - 1:
		selected_character = 0
	elif selected_character < 0:
		selected_character = len(Constants.ClassType) - 1
	match selected_character:
		Constants.ClassType.SWORDSMAN:
			character_portrait.texture = SWORDSMAN_PORTRAIT
		Constants.ClassType.ARCHER:
			character_portrait.texture = ARCHER_PORTRAIT
		Constants.ClassType.MAGE:
			character_portrait.texture = MAGE_PORTRAIT
		Constants.ClassType.BEGINNER:
			character_portrait.texture = BEGINNER_PORTRAIT
		Constants.ClassType.ROGUE:
			character_portrait.texture = ROGUE_PORTRAIT
