extends Node

signal login_success(account_id, username)
signal login_failed(error_message)
signal registration_success(account_id)
signal registration_failed(error_message)
signal characters_received(characters)
signal character_created(character_name)
signal character_creation_failed(error_message)
signal character_deleted(character_name)
signal character_deletion_failed(error_message)

var account_id: int = -1
var account_username: String = ""
# Computed property so a runtime change via UserConfig.set_backend_api_url(...)
# takes effect immediately on the next request. Previously this was cached at
# _ready, so switching the URL in-game (e.g. dev pointing at a port-shifted
# backend) had no effect until the next process restart.
var api_url: String:
	get: return UserConfig.get_backend_api_url()
var is_dev_mode: bool = false
var use_local_save: bool = false

func _ready():
	pass  # api_url is now computed on demand from UserConfig.

func register(username, password):
	var http := HTTPRequest.new()
	add_child(http)
	var r: Dictionary = await BackendHttp.post_json(http, api_url + "/account/register", {"username": username, "password": password})
	http.queue_free()

	if not r.started:
		registration_failed.emit("Connection error")
		return
	if r.json == null:
		registration_failed.emit("Failed to parse server response")
		return
	if r.code == 201:
		registration_success.emit(r.json.get("account_id"))
	else:
		registration_failed.emit(r.json.get("error", "Unknown error"))

func login(username, password):
	if use_local_save:
		account_id = 9998
		account_username = username
		login_success.emit(account_id, account_username)
		return

	var http := HTTPRequest.new()
	add_child(http)
	var r: Dictionary = await BackendHttp.post_json(http, api_url + "/account/login", {"username": username, "password": password})
	http.queue_free()

	if not r.started:
		login_failed.emit("Connection error")
		return
	if r.json == null:
		login_failed.emit("Failed to parse server response")
		return
	if r.code == 200:
		account_id = r.json.get("account_id")
		account_username = r.json.get("username")
		login_success.emit(account_id, account_username)
	else:
		login_failed.emit(r.json.get("error", "Unknown error"))

func dev_login():
	is_dev_mode = true
	account_id = 9999
	account_username = "DevUser"
	login_success.emit(account_id, account_username)

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
					var save_data = PlayerSaveSchema.new_character(dev_char_name, class_enum)
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

	var http := HTTPRequest.new()
	add_child(http)
	var r: Dictionary = await BackendHttp.post_json(http, api_url + "/account/characters", {"account_id": account_id})
	http.queue_free()

	# Matches the prior behaviour: emit only on a 200 with a parseable body;
	# stay silent on transport/parse failure (the select screen handles that).
	if r.started and r.code == 200 and r.json != null:
		characters_received.emit(r.json.get("characters", []))

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
		var save_data = PlayerSaveSchema.new_character(char_name, class_id)
		file.store_string(JSON.stringify(save_data, "\t"))
		file.close()
		character_created.emit(char_name)
		return

	var http := HTTPRequest.new()
	add_child(http)
	var r: Dictionary = await BackendHttp.post_json(http, api_url + "/character/create", {
		"account_id": account_id,
		"name": char_name,
		"class_id": class_id,
	})
	http.queue_free()

	if not r.started:
		character_creation_failed.emit("Connection error")
		return
	if r.result != HTTPRequest.RESULT_SUCCESS:
		character_creation_failed.emit("Connection failed (result: %d)" % r.result)
		return
	if r.body.is_empty():
		character_creation_failed.emit("Empty response from server (HTTP %d)" % r.code)
		return
	if r.json == null:
		character_creation_failed.emit("Failed to parse server response")
		return
	if r.code == 201:
		character_created.emit(r.json.get("name"))
	else:
		character_creation_failed.emit(r.json.get("error", "Unknown error"))

func delete_character(char_name: String):
	if account_id == -1:
		return

	if is_dev_mode or use_local_save:
		var saves_dir = ProjectSettings.globalize_path("res://saves")
		var file_path = saves_dir.path_join("player_%s.json" % char_name)
		if not FileAccess.file_exists(file_path):
			character_deletion_failed.emit("Character save file not found")
			return
		var err = DirAccess.remove_absolute(file_path)
		if err != OK:
			character_deletion_failed.emit("Failed to delete save file (error %d)" % err)
			return
		character_deleted.emit(char_name)
		return

	var http := HTTPRequest.new()
	add_child(http)
	var r: Dictionary = await BackendHttp.post_json(http, api_url + "/character/delete", {
		"account_id": account_id,
		"name": char_name,
	})
	http.queue_free()

	if not r.started:
		character_deletion_failed.emit("Connection error")
		return
	if r.result != HTTPRequest.RESULT_SUCCESS:
		character_deletion_failed.emit("Connection failed (result: %d)" % r.result)
		return
	if r.code == 200:
		var deleted_name = char_name
		if r.json != null and r.json.has("name"):
			deleted_name = r.json.get("name")
		character_deleted.emit(deleted_name)
	else:
		var err_msg = "Delete failed (HTTP %d)" % r.code
		if r.json != null and r.json.has("error"):
			err_msg = r.json.get("error")
		character_deletion_failed.emit(err_msg)


# The new-character save template now lives in PlayerSaveSchema.new_character()
# (the single source of truth for the Player-save shape) — see
# scripts/Networking/player_save_schema.gd.
