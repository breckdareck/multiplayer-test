extends Node

signal login_success(account_id, username)
signal login_failed(error_message)
signal registration_success(account_id)
signal registration_failed(error_message)
signal characters_received(characters)
signal character_created(character_name)
signal character_creation_failed(error_message)

var account_id: int = -1
var account_username: String = ""
var api_url = ""  # Will be loaded from UserConfig
var is_dev_mode: bool = false
var use_local_save: bool = false

func _ready():
	# Load API URL from config (supports environment variable override)
	api_url = UserConfig.get_backend_api_url()
	print("NetworkManager: Using API URL: %s" % api_url)

func register(username, password):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_register_completed.bind(http))
	
	var body = JSON.stringify({"username": username, "password": password})
	var headers = ["Content-Type: application/json"]
	var error = http.request(api_url + "/account/register", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		registration_failed.emit("Connection error")
		http.queue_free()

func _on_register_completed(result, response_code, headers, body, http):
	var response_text = body.get_string_from_utf8()
	print("Register Response Code: ", response_code)
	print("Register Response Body: ", response_text)
	
	var json = JSON.new()
	var error = json.parse(response_text)
	
	if error != OK:
		print("JSON Parse Error: ", error)
		registration_failed.emit("Failed to parse server response")
		http.queue_free()
		return
	
	var response = json.get_data()
	
	if response_code == 201:
		registration_success.emit(response.get("account_id"))
	else:
		registration_failed.emit(response.get("error", "Unknown error"))
	
	http.queue_free()

func login(username, password):
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_login_completed.bind(http))
	
	var body = JSON.stringify({"username": username, "password": password})
	var headers = ["Content-Type: application/json"]
	var error = http.request(api_url + "/account/login", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		login_failed.emit("Connection error")
		http.queue_free()

func dev_login():
	is_dev_mode = true
	account_id = 9999
	account_username = "DevUser"
	login_success.emit(account_id, account_username)

func _on_login_completed(result, response_code, headers, body, http):
	var response_text = body.get_string_from_utf8()
	print("Login Response Code: ", response_code)
	print("Login Response Body: ", response_text)
	
	var json = JSON.new()
	var error = json.parse(response_text)
	
	if error != OK:
		print("JSON Parse Error: ", error)
		login_failed.emit("Failed to parse server response")
		http.queue_free()
		return
	
	var response = json.get_data()
	
	if response_code == 200:
		account_id = response.get("account_id")
		account_username = response.get("username")
		login_success.emit(account_id, account_username)
	else:
		login_failed.emit(response.get("error", "Unknown error"))
	
	http.queue_free()

func get_characters():
	if is_dev_mode:
		var dev_characters = []
		var classes = Constants.ClassType.values()
		
		# First, try to load any existing save files
		for i in range(classes.size()):
			var class_enum = classes[i]
			var class_name_str = Constants.ClassType.keys()[class_enum].capitalize()
			var dev_char_name = "Dev" + class_name_str
			var file_path = "res://saves/player_%s.json" % dev_char_name
			
			var char_data = {
				"name": dev_char_name,
				"level": 1,
				"character_class": class_enum,
				"id": 9000 + i
			}
			
			# Try to load existing save
			if FileAccess.file_exists(file_path):
				var file = FileAccess.open(file_path, FileAccess.READ)
				var loaded_data = JSON.parse_string(file.get_as_text())
				file.close()
				if loaded_data is Dictionary:
					# Merge loaded data with our template to preserve level, class, etc.
					if loaded_data.has("level"):
						char_data["level"] = loaded_data["level"]
					if loaded_data.has("experience"):
						char_data["experience"] = loaded_data["experience"]
					print("Loaded dev character %s from file: level %d" % [dev_char_name, char_data["level"]])
			
			dev_characters.append(char_data)
		
		characters_received.emit(dev_characters)
		return

	if account_id == -1:
		return
		
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_get_characters_completed.bind(http))
	
	var body = JSON.stringify({"account_id": account_id})
	var headers = ["Content-Type: application/json"]
	var error = http.request(api_url + "/account/characters", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		http.queue_free()

func _on_get_characters_completed(result, response_code, headers, body, http):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		
		if response != null:
			characters_received.emit(response.get("characters", []))
	
	http.queue_free()

func create_character(char_name, class_id):
	if account_id == -1:
		return
		
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_create_character_completed.bind(http))
	
	var body = JSON.stringify({
		"account_id": account_id,
		"name": char_name,
		"class_id": class_id
	})
	var headers = ["Content-Type: application/json"]
	var error = http.request(api_url + "/character/create", headers, HTTPClient.METHOD_POST, body)
	
	if error != OK:
		character_creation_failed.emit("Connection error")
		http.queue_free()

func _on_create_character_completed(result, response_code, headers, body, http):
	var response_text = body.get_string_from_utf8()
	var response = JSON.parse_string(response_text)
	
	if response == null:
		character_creation_failed.emit("Failed to parse server response")
		http.queue_free()
		return
	
	if response_code == 201:
		character_created.emit(response.get("name"))
	else:
		character_creation_failed.emit(response.get("error", "Unknown error"))
	
	http.queue_free()
