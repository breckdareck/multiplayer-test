extends Control

@onready var character_list = $Panel/VBoxContainer/CharacterList
@onready var create_button = $Panel/VBoxContainer/CreateButton
@onready var logout_button = $Panel/VBoxContainer/LogoutButton
@onready var host_button = $Panel/VBoxContainer/HostButton
@onready var join_button = $Panel/VBoxContainer/JoinButton
@onready var ip_input = $Panel/VBoxContainer/IPInput
@onready var status_label = $Panel/VBoxContainer/StatusLabel

var characters = []
var selected_character_name = ""

func _ready():
	create_button.pressed.connect(_on_create_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	
	NetworkManager.characters_received.connect(_on_characters_received)
	
	# Connect to connection signals
	MultiplayerManager.server_has_started.connect(_on_server_started)
	ClientManager.connection_succeeded.connect(_on_connection_succeeded)
	ClientManager.connection_failed.connect(_on_connection_failed)
	
	# Fetch characters on load
	NetworkManager.get_characters()

func _on_characters_received(chars):
	characters = chars
	character_list.clear()
	for char_data in characters:
		var text = "%s (Lvl %d)" % [char_data.name, char_data.level]
		character_list.add_item(text)

func _get_selected_character_data() -> Dictionary:
	var selected = character_list.get_selected_items()
	if selected.size() == 0:
		return {}
	
	var index = selected[0]
	return characters[index]

func _on_host_pressed():
	var char_data = _get_selected_character_data()
	if char_data.is_empty():
		status_label.text = "Please select a character first."
		return
	
	var char_name = char_data.name
	var char_class = char_data.get("character_class", 0)
	
	# Store selected character name and class
	selected_character_name = char_name
	NetworkManager.set_meta("selected_character_name", char_name)
	NetworkManager.set_meta("selected_character_class", char_class)
	
	status_label.text = "Starting server..."
	_set_buttons_enabled(false)
	
	# Host the game
	MultiplayerManager.host_game()
	
func _on_join_pressed():
	var char_data = _get_selected_character_data()
	if char_data.is_empty():
		status_label.text = "Please select a character first."
		return
	
	var char_name = char_data.name
	var char_class = char_data.get("character_class", 0)
	
	var ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	
	# Store selected character name and class
	selected_character_name = char_name
	NetworkManager.set_meta("selected_character_name", char_name)
	NetworkManager.set_meta("selected_character_class", char_class)
	
	status_label.text = "Connecting to %s..." % ip
	_set_buttons_enabled(false)
	
	# Join the game with IP
	MultiplayerManager.join_game(ip)

func _on_server_started():
	status_label.text = "Server started!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Give a moment for the user to see the success message? 
	# Or just switch immediately. Immediate switch is better for UX usually.
	queue_free()

func _on_connection_succeeded():
	status_label.text = "Connected!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	queue_free()

func _on_connection_failed():
	status_label.text = "Connection failed!"
	status_label.add_theme_color_override("font_color", Color.RED)
	_set_buttons_enabled(true)

func _set_buttons_enabled(enabled: bool):
	host_button.disabled = !enabled
	join_button.disabled = !enabled
	create_button.disabled = !enabled
	logout_button.disabled = !enabled

func _on_create_pressed():
	get_tree().change_scene_to_file("res://scenes/UI/CharacterCreationScreen.tscn")

func _on_logout_pressed():
	NetworkManager.account_id = -1
	get_tree().change_scene_to_file("res://scenes/UI/LoginScreen.tscn")
