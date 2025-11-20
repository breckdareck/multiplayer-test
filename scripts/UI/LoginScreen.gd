extends Control

@onready var username_input = $Panel/VBoxContainer/UsernameInput
@onready var password_input = $Panel/VBoxContainer/PasswordInput
@onready var login_button = $Panel/VBoxContainer/LoginButton
@onready var register_button = $Panel/VBoxContainer/RegisterButton
@onready var status_label = $Panel/VBoxContainer/StatusLabel

func _ready():
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.login_failed.connect(_on_login_failed)
	NetworkManager.registration_success.connect(_on_registration_success)
	NetworkManager.registration_failed.connect(_on_registration_failed)

func _on_login_pressed():
	var user = username_input.text
	var passw = password_input.text
	if user == "" or passw == "":
		status_label.text = "Please enter username and password."
		return
		
	status_label.text = "Logging in..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.login(user, passw)

func _on_register_pressed():
	var user = username_input.text
	var passw = password_input.text
	if user == "" or passw == "":
		status_label.text = "Please enter username and password."
		return
		
	status_label.text = "Registering..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.register(user, passw)

func _on_login_success(account_id, username):
	status_label.text = "Login Successful!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Transition to Character Select
	get_tree().change_scene_to_file("res://scenes/UI/CharacterSelectScreen.tscn")

func _on_login_failed(error):
	status_label.text = "Login Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)

func _on_registration_success(account_id):
	status_label.text = "Registration Successful! Please Login."
	status_label.add_theme_color_override("font_color", Color.GREEN)

func _on_registration_failed(error):
	status_label.text = "Registration Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)
