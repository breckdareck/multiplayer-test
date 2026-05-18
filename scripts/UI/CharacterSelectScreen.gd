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
var _server_info_label: Label = null
var _backend_status_label: Label = null
var _status_request: HTTPRequest = null

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
	
	_setup_server_info_display()
	_setup_backend_info_display()
	
	# Fetch characters on load
	NetworkManager.get_characters()


func _setup_server_info_display():
	# Create a label to show server info (hidden until host starts)
	_server_info_label = Label.new()
	_server_info_label.add_theme_color_override("font_color", Color.YELLOW)
	_server_info_label.text = "Share this IP with friends: (waiting...)"
	_server_info_label.visible = false
	$Panel/VBoxContainer.add_child(_server_info_label)


func _setup_backend_info_display():
	var backend_url = UserConfig.get_backend_api_url()
	_backend_status_label = Label.new()
	_backend_status_label.add_theme_color_override("font_color", Color.GRAY)
	_backend_status_label.text = "Backend: %s (checking...)" % backend_url
	$Panel/VBoxContainer.add_child(_backend_status_label)

	_status_request = HTTPRequest.new()
	_status_request.request_completed.connect(_on_status_check_completed)
	add_child(_status_request)
	_check_server_status()


func _check_server_status():
	var api_url = UserConfig.get_backend_api_url()
	var error = _status_request.request(api_url + "/health")
	if error != OK:
		_update_server_status(false)


func _on_status_check_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	_update_server_status(response_code == 200)


func _update_server_status(online: bool):
	var backend_url = UserConfig.get_backend_api_url()
	if online:
		_backend_status_label.text = "Backend: %s (Online)" % backend_url
		_backend_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_backend_status_label.text = "Backend: %s (Offline)" % backend_url
		_backend_status_label.add_theme_color_override("font_color", Color.RED)


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
	
	# Show server info (will display once we determine the IP)
	_display_server_info()
	
	# Host the game
	MultiplayerManager.host_game()


func _display_server_info():
	# Get local IP (show LAN address first)
	var local_ip = IP.get_local_addresses()[0] if IP.get_local_addresses().size() > 0 else "127.0.0.1"
	var game_port = UserConfig.game_server_port
	
	_server_info_label.visible = true
	_server_info_label.text = "🎮 Server Info:\n  LAN: %s:%d\n  ⏳ Finding public IP..." % [local_ip, game_port]
	
	# Try to get external IP (non-blocking, best effort)
	_fetch_external_ip.call_deferred()


func _fetch_external_ip():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_external_ip_received.bind(http))
	
	# Use a public IP detection service
	var error = http.request("https://api.ipify.org?format=json")
	if error != OK:
		http.queue_free()


func _on_external_ip_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response != null and response.has("ip"):
			var external_ip = response["ip"]
			var game_port = UserConfig.game_server_port
			var local_ip = IP.get_local_addresses()[0] if IP.get_local_addresses().size() > 0 else "127.0.0.1"
			
			_server_info_label.text = "🎮 Server Info:\n  LAN: %s:%d\n  Internet: %s:%d\n  (Note: Port forwarding may be needed)" % [local_ip, game_port, external_ip, game_port]
	
	http.queue_free()

	
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
