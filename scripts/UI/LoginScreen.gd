extends Control

@onready var username_input = $Panel/VBoxContainer/UsernameInput
@onready var password_input = $Panel/VBoxContainer/PasswordInput
@onready var login_button = $Panel/VBoxContainer/LoginButton
@onready var register_button = $Panel/VBoxContainer/RegisterButton
@onready var dev_login_button = $Panel/VBoxContainer/DevLoginButton
@onready var local_save_checkbox = $Panel/VBoxContainer/LocalSaveCheckbox
@onready var status_label = $Panel/VBoxContainer/StatusLabel

# Backend settings (from scene)
@onready var backend_settings_button = $Panel/VBoxContainer/BackendSettingsButton
@onready var preset_label = $Panel/VBoxContainer/PresetLabel
@onready var preset_button_box = $Panel/VBoxContainer/PresetButtonBox
@onready var local_button = $Panel/VBoxContainer/PresetButtonBox/LocalButton
@onready var cloud_button = $Panel/VBoxContainer/PresetButtonBox/CloudButton
@onready var api_url_input = $Panel/VBoxContainer/APIUrlInput
@onready var apply_button = $Panel/VBoxContainer/ApplyButton
@onready var api_status_label = $Panel/VBoxContainer/APIStatusLabel

var settings_expanded: bool = false

# Presets for quick switching
var api_presets = {
	"Local": "http://127.0.0.1:5000/api",
	"Cloud": "http://72.84.198.233:5000/api",
}

func _ready():
	login_button.pressed.connect(_on_login_pressed)
	register_button.pressed.connect(_on_register_pressed)
	dev_login_button.pressed.connect(_on_dev_login_pressed)
	local_save_checkbox.toggled.connect(_on_local_save_toggled)
	
	backend_settings_button.pressed.connect(_toggle_backend_settings)
	local_button.pressed.connect(_on_preset_selected.bind("Local"))
	cloud_button.pressed.connect(_on_preset_selected.bind("Cloud"))
	apply_button.pressed.connect(_on_apply_api_url)
	
	NetworkManager.login_success.connect(_on_login_success)
	NetworkManager.login_failed.connect(_on_login_failed)
	NetworkManager.registration_success.connect(_on_registration_success)
	NetworkManager.registration_failed.connect(_on_registration_failed)
	
	_setup_backend_display()

	if MultiplayerManager.disconnect_reason != "":
		status_label.text = MultiplayerManager.disconnect_reason
		status_label.add_theme_color_override("font_color", Color.RED)
		MultiplayerManager.disconnect_reason = ""


func _setup_backend_display():
	# Initialize with current backend URL
	api_url_input.text = UserConfig.get_backend_api_url()
	api_status_label.text = "API URL: %s" % UserConfig.get_backend_api_url()


func _toggle_backend_settings():
	settings_expanded = !settings_expanded
	preset_label.visible = settings_expanded
	preset_button_box.visible = settings_expanded
	api_url_input.visible = settings_expanded
	apply_button.visible = settings_expanded
	backend_settings_button.text = "Backend Settings ▼" if settings_expanded else "Backend Settings ▶"


func _on_preset_selected(preset_name: String):
	var preset_url = api_presets[preset_name]
	
	if preset_url.is_empty():
		status_label.text = "Please configure Cloud URL first"
		status_label.add_theme_color_override("font_color", Color.YELLOW)
		return
	
	# Apply the preset
	UserConfig.set_backend_api_url(preset_url)
	api_url_input.text = preset_url
	api_status_label.text = "API URL: %s" % preset_url
	NetworkManager.api_url = preset_url
	
	status_label.text = "Switched to %s backend" % preset_name
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_toggle_backend_settings()  # Collapse the settings


func _on_apply_api_url():
	var new_url = api_url_input.text.strip_edges()
	if new_url.is_empty():
		status_label.text = "API URL cannot be empty"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	# Basic validation
	if not new_url.begins_with("http://") and not new_url.begins_with("https://"):
		status_label.text = "API URL must start with http:// or https://"
		status_label.add_theme_color_override("font_color", Color.RED)
		return
	
	UserConfig.set_backend_api_url(new_url)
	api_presets["Cloud"] = new_url  # Save as Cloud preset
	api_status_label.text = "API URL: %s" % new_url
	
	# Reconnect NetworkManager to use new URL
	NetworkManager.api_url = UserConfig.get_backend_api_url()
	
	status_label.text = "Backend API URL updated!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_toggle_backend_settings()  # Collapse the settings


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

func _on_dev_login_pressed():
	status_label.text = "Logging in as Dev..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.dev_login()

func _on_local_save_toggled(toggled_on: bool):
	NetworkManager.use_local_save = toggled_on
	if toggled_on:
		status_label.text = "Local Save Enabled"
		status_label.add_theme_color_override("font_color", Color.YELLOW)
	else:
		status_label.text = "Local Save Disabled"
		status_label.add_theme_color_override("font_color", Color.WHITE)

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
