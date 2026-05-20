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
	#print("NetworkManager: Using API URL: %s" % api_url)

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
	#print("Register Response Code: ", response_code)
	#print("Register Response Body: ", response_text)
	
	var json = JSON.new()
	var error = json.parse(response_text)
	
	if error != OK:
		#print("JSON Parse Error: ", error)
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
	if use_local_save:
		account_id = 9998
		account_username = username
		login_success.emit(account_id, account_username)
		return

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
	#print("Login Response Code: ", response_code)
	#print("Login Response Body: ", response_text)
	
	var json = JSON.new()
	var error = json.parse(response_text)
	
	if error != OK:
		#print("JSON Parse Error: ", error)
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
	if is_dev_mode or use_local_save:
		var characters = []
		var saves_path = ProjectSettings.globalize_path("res://saves")
		if not DirAccess.dir_exists_absolute(saves_path):
			DirAccess.make_dir_recursive_absolute(saves_path)

		# In dev mode, ensure a save file exists for each class
		if is_dev_mode:
			var classes = Constants.ClassType.values()
			for i in range(classes.size()):
				var class_enum = classes[i]
				var class_name_str = Constants.ClassType.keys()[class_enum].capitalize()
				var dev_char_name = "Dev" + class_name_str
				var dev_file_path = saves_path.path_join("player_%s.json" % dev_char_name)
				if not FileAccess.file_exists(dev_file_path):
					var is_advanced = class_enum >= Constants.ClassType.CRUSADER
					var starting_level = 30 if is_advanced else 1
					var save_data = {
							"username": dev_char_name,
							"level": starting_level,
							"experience": 0,
							"character_class": class_enum,
							"current_health": 100,
							"max_health": 100,
							"current_mana": 100,
							"max_mana": 100,
							"monies": 0,
							"inventory": {},
							"equipment": {},
							"abilities": {"available_points": (starting_level - 1) * 3},
							"buffs": {},
							"quests": {}
						}
					var file = FileAccess.open(dev_file_path, FileAccess.WRITE)
					if file:
						file.store_string(JSON.stringify(save_data, "\t"))
						file.close()
						#print("Dev mode: Created save for %s" % dev_char_name)

		var dir = DirAccess.open(saves_path)
		if dir == null:
			#print("Local save: Failed to open saves directory: ", saves_path, " error: ", DirAccess.get_open_error())
			characters_received.emit(characters)
			return
		dir.list_dir_begin()
		var file_name = dir.get_next()
		var idx = 0
		while file_name != "":
			if file_name.begins_with("player_") and file_name.ends_with(".json"):
				var char_name = file_name.trim_prefix("player_").trim_suffix(".json")
				var file_path = saves_path.path_join(file_name)
				var file = FileAccess.open(file_path, FileAccess.READ)
				if file == null:
					#print("Local save: Failed to open file: ", file_path)
					file_name = dir.get_next()
					continue
				var loaded_data = JSON.parse_string(file.get_as_text())
				file.close()
				var char_data = {
					"name": char_name,
					"level": 1,
					"character_class": 0,
					"id": 8000 + idx
				}
				if loaded_data is Dictionary:
					char_data["level"] = loaded_data.get("level", 1)
					char_data["character_class"] = loaded_data.get("character_class", 0)
				characters.append(char_data)
				#print("Local save: Found character '%s' (level %d)" % [char_name, char_data["level"]])
				idx += 1
			file_name = dir.get_next()
		dir.list_dir_end()
		#print("Local save: Emitting %d characters" % characters.size())
		characters_received.emit(characters)
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

	if is_dev_mode or use_local_save:
		var saves_dir = ProjectSettings.globalize_path("res://saves")
		var file_path = saves_dir.path_join("player_%s.json" % char_name)
		#print("Create character: saving to ", file_path)
		if FileAccess.file_exists(file_path):
			character_creation_failed.emit("Character name already exists")
			return
		# Ensure saves directory exists
		if not DirAccess.dir_exists_absolute(saves_dir):
			DirAccess.make_dir_recursive_absolute(saves_dir)
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if file == null:
			#print("Create character: FileAccess.open failed, error: ", FileAccess.get_open_error())
			character_creation_failed.emit("Failed to create save file")
			return
		var is_advanced = class_id >= Constants.ClassType.CRUSADER
		var starting_level = 30 if is_advanced else 1
		var save_data = {
			"username": char_name,
			"level": starting_level,
			"experience": 0,
			"character_class": class_id,
			"current_health": 100,
			"max_health": 100,
			"current_mana": 100,
			"max_mana": 100,
			"monies": 0,
			"inventory": {},
			"equipment": {},
			"abilities": {"available_points": (starting_level - 1) * 3},
			"buffs": {},
			"quests": {}
		}
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		character_created.emit(char_name)
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
	if result != HTTPRequest.RESULT_SUCCESS:
		character_creation_failed.emit("Connection failed (result: %d)" % result)
		http.queue_free()
		return

	var response_text = body.get_string_from_utf8()
	if response_text.is_empty():
		character_creation_failed.emit("Empty response from server (HTTP %d)" % response_code)
		http.queue_free()
		return

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
