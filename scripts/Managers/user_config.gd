extends Node

const SAVE_FILE_PATH = "user://user_config.cfg"
const KEYBIND_CONFIG_SECTION = "Keybinds"
const SOUND_CONFIG_SECTION = "SoundSettings"
const SERVER_CONFIG_SECTION = "ServerSettings"
const GAMEPLAY_CONFIG_SECTION = "GameplaySettings"
const DEFAULT_API_URL = "http://127.0.0.1:5000/api"

var custom_keybinds: Dictionary = {}
var default_hotbar_actions: Array[String] = []
var _all_managed_actions: Array[String] = []

# Sound settings
var master_volume_db: float = 1
var music_volume_db: float = -8
var sfx_volume_db: float = -8

# Server settings
var backend_api_url: String = DEFAULT_API_URL
var game_server_port: int = 8080

# Gameplay settings
var screen_shake_enabled: bool = true

func _init():
	# Define default hotbar actions
	for i in range(1, 9): # hotbar_1 to hotbar_8
		default_hotbar_actions.append("hotbar_" + str(i))
	
	# Combine all actions to be managed
	_all_managed_actions = default_hotbar_actions.duplicate() # Start with hotbar actions
	_all_managed_actions.append_array([
		"Jump", "Attack", "Move Left", "Move Right", "Move Down", "Pickup",
		"OpenStatsWindow", "OpenInventoryWindow", "OpenEquipmentWindow", "OpenAbilityWindow"
	])


func _ready():
	load_config()


func load_config():
	var config = ConfigFile.new()
	var error = config.load(SAVE_FILE_PATH)
	
	if error != OK:
		if error == ERR_FILE_NOT_FOUND:
			#print("User config file not found. Creating with default keybinds and sound settings.")
			_prefill_default_keybinds() # Populate custom_keybinds
			_apply_sound_settings() # Apply default sound settings immediately
			save_config() # Save these defaults to the file
			# Now that the file is created, attempt to load it again
			error = config.load(SAVE_FILE_PATH)
			if error != OK:
				push_error("Failed to load newly created user config file: ", error)
				return
		else:
			push_error("Failed to load user config: ", error)
		return

	_load_keybinds_from_config(config)
	_load_sound_settings_from_config(config)
	_load_server_settings_from_config(config)
	_load_gameplay_settings_from_config(config)
	
	#print("User config loaded.")


func save_config():
	var config = ConfigFile.new()
	var file_existed_before_save = FileAccess.file_exists(SAVE_FILE_PATH)
	var error
	
	if file_existed_before_save:
		error = config.load(SAVE_FILE_PATH)
		if error != OK:
			push_error("Failed to load existing user config for merging: ", error)
	
	_save_keybinds_to_config(config, file_existed_before_save)
	_save_sound_settings_to_config(config, file_existed_before_save)
	_save_server_settings_to_config(config, file_existed_before_save)
	_save_gameplay_settings_to_config(config, file_existed_before_save)
	
	error = config.save(SAVE_FILE_PATH)
	if error != OK:
		push_error("Failed to save user config: ", error)
	else:
		print("User config saved to ", SAVE_FILE_PATH)


func _load_keybinds_from_config(config: ConfigFile):
	# Load all managed keybinds
	if config.has_section(KEYBIND_CONFIG_SECTION):
		for action_name in _all_managed_actions:
			if config.has_section_key(KEYBIND_CONFIG_SECTION, action_name):
				var loaded_events_data = config.get_value(KEYBIND_CONFIG_SECTION, action_name)
				var key_events: Array[int] = []
				
				if loaded_events_data is Array:
					for physical_keycode_int in loaded_events_data:
						if physical_keycode_int is int:
							key_events.append(physical_keycode_int)
						else:
							push_warning("Invalid event data format for action '%s'. Expected int, got %s." % [action_name, typeof(physical_keycode_int)])
							key_events.append(_create_unset_key_event())

				else:
					push_warning("Invalid event data loaded for action '%s'. Expected Array, got %s." % [action_name, typeof(loaded_events_data)])
				
				while key_events.size() < 2:
					key_events.append(_create_unset_key_event())
				
				custom_keybinds[action_name] = key_events
				#print("Loaded custom keybinds for '%s': %s" % [action_name, get_keybind_text(action_name, -1)])
			else:
				# If action not in config, prefill with unset events
				var key_events: Array[int] = [_create_unset_key_event(), _create_unset_key_event()]
				custom_keybinds[action_name] = key_events
				push_warning("Action '%s' not found in config. Prefilling with [Unset]." % action_name)
		KeybindManager.apply_keybinds_to_input_map()
	else:
		# If the Keybinds section doesn't exist, prefill with defaults and save
		push_warning("Keybinds section not found in config file. Prefilling with default keybinds.")
		_prefill_default_keybinds()
		save_config() # Save the newly prefilled defaults


func _save_keybinds_to_config(config: ConfigFile, _file_existed_before_save: bool):

	for action_name in _all_managed_actions:
		if custom_keybinds.has(action_name):
			var key_events: Array[int] = custom_keybinds[action_name]
			var events_data: Array[int] = []
			
			for event_keycode in key_events:
				events_data.append(event_keycode)
			config.set_value(KEYBIND_CONFIG_SECTION, action_name, events_data)


func _prefill_default_keybinds():
	#print("Prefilling custom_keybinds with InputMap defaults.")
	for action_name in _all_managed_actions:
		var key_events: Array[int] = []
		var events = InputMap.action_get_events(action_name)
		for event in events:
			if event is InputEventKey:
				key_events.append(event.physical_keycode)
				if key_events.size() >= 2: # Limit to 2 default keybinds
					break
		
		# Ensure there are always two entries, filling with unset events if less than 2 defaults
		while key_events.size() < 2:
			key_events.append(_create_unset_key_event())
		
		custom_keybinds[action_name] = key_events
		#print("Prefilled '%s' with defaults: %s" % [action_name, get_keybind_text(action_name, -1)])


func get_keybind_event(action_name: String, key_index: int = 0) -> InputEventKey:
	var unset_event = InputEventKey.new()
	
	if custom_keybinds.has(action_name):
		var key_codes: Array[int] = custom_keybinds[action_name]
		if key_index >= 0 and key_index < key_codes.size():
			var event = InputEventKey.new()
			event.physical_keycode = key_codes[key_index]
			event.pressed = true
			return event
		else:
			push_warning("Invalid key_index %d for action '%s'. Returning unset event." % [key_index, action_name])
			unset_event.physical_keycode = KEY_NONE
			unset_event.pressed = true
			return unset_event
	
	# Fallback to InputMap if not in custom_keybinds (shouldn't happen if prefilled correctly)
	# This fallback will only return the first event, so it's less useful for two keybinds
	var events = InputMap.action_get_events(action_name)
	for event in events:
		if event is InputEventKey:
			return event
	unset_event = InputEventKey.new()
	unset_event.physical_keycode = KEY_NONE
	unset_event.pressed = true
	return unset_event # Return an unset event if nothing found


func get_keybind_text(action_name: String, key_index: int = -1) -> String:
	if not custom_keybinds.has(action_name):
		return "[Unset]" # Action not managed
	
	var key_codes: Array[int] = custom_keybinds[action_name]
	
	if key_index == -1: # Return combined text for both
		var text1 = _get_single_key_text(key_codes[0] if key_codes.size() > 0 else KEY_NONE)
		var text2 = _get_single_key_text(key_codes[1] if key_codes.size() > 1 else KEY_NONE)
		
		if text1 == "[Unset]" and text2 == "[Unset]":
			return "[Unset]"
		elif text1 == "[Unset]":
			return text2
		elif text2 == "[Unset]":
			return text1
		else:
			return text1 + " / " + text2
	elif key_index >= 0 and key_index < key_codes.size():
		return _get_single_key_text(key_codes[key_index])
	else:
		push_warning("Invalid key_index %d for action '%s'. Returning [Unset]." % [key_index, action_name])
		return "[Unset]"


func _get_single_key_text(physical_keycode: int) -> String:
	if physical_keycode != KEY_NONE:
		return OS.get_keycode_string(physical_keycode)
	return "[Unset]"


func set_keybind_data(action_name: String, new_event: InputEventKey, key_index: int):
	if custom_keybinds.has(action_name):
		var key_codes: Array[int] = custom_keybinds[action_name]
		if key_index >= 0 and key_index < key_codes.size():
			key_codes[key_index] = new_event.physical_keycode
			save_config()
			#print("Keybind %d for '%s' changed to '%s'." % [key_index, action_name, _get_single_key_text(new_event.physical_keycode)])
		else:
			push_error("Invalid key_index %d for action '%s'. Keybind not set." % [key_index, action_name])
	else:
		push_error("Action '%s' not found in custom_keybinds. Keybind not set." % action_name)


func _create_unset_key_event() -> int:
	return KEY_NONE


func _load_sound_settings_from_config(config: ConfigFile):
	if config.has_section(SOUND_CONFIG_SECTION):
		master_volume_db = config.get_value(SOUND_CONFIG_SECTION, "master_volume_db", master_volume_db)
		music_volume_db = config.get_value(SOUND_CONFIG_SECTION, "music_volume_db", music_volume_db)
		sfx_volume_db = config.get_value(SOUND_CONFIG_SECTION, "sfx_volume_db", sfx_volume_db)
		
		#print("Sound settings loaded.")
		
	_apply_sound_settings()

func _save_sound_settings_to_config(config: ConfigFile, file_existed_before_save: bool):
	config.set_value(SOUND_CONFIG_SECTION, "master_volume_db", master_volume_db)
	config.set_value(SOUND_CONFIG_SECTION, "music_volume_db", music_volume_db)
	config.set_value(SOUND_CONFIG_SECTION, "sfx_volume_db", sfx_volume_db)


func _apply_sound_settings():
	# Assuming you have audio bus names like "Master", "Music", "SFX"
	var master_bus_idx = AudioServer.get_bus_index("Master")
	var music_bus_idx = AudioServer.get_bus_index("Music")
	var sfx_bus_idx = AudioServer.get_bus_index("SFX")
	
	if master_bus_idx != -1: AudioServer.set_bus_volume_db(master_bus_idx, master_volume_db)
	if music_bus_idx != -1: AudioServer.set_bus_volume_db(music_bus_idx, music_volume_db)
	if sfx_bus_idx != -1: AudioServer.set_bus_volume_db(sfx_bus_idx, sfx_volume_db)


func set_master_volume(value_db: float):
	master_volume_db = value_db
	_apply_sound_settings()
	save_config()


func set_music_volume(value_db: float):
	music_volume_db = value_db
	_apply_sound_settings()
	save_config()


func set_sfx_volume(value_db: float):
	sfx_volume_db = value_db
	_apply_sound_settings()
	save_config()


func _load_server_settings_from_config(config: ConfigFile):
	if config.has_section(SERVER_CONFIG_SECTION):
		backend_api_url = config.get_value(SERVER_CONFIG_SECTION, "backend_api_url", DEFAULT_API_URL)
		game_server_port = config.get_value(SERVER_CONFIG_SECTION, "game_server_port", 8080)
		#print("Server settings loaded. API URL: %s" % backend_api_url)
	else:
		# Initialize with defaults if section doesn't exist
		backend_api_url = DEFAULT_API_URL
		game_server_port = 8080


func _save_server_settings_to_config(config: ConfigFile, file_existed_before_save: bool):
	config.set_value(SERVER_CONFIG_SECTION, "backend_api_url", backend_api_url)
	config.set_value(SERVER_CONFIG_SECTION, "game_server_port", game_server_port)


func set_backend_api_url(url: String):
	backend_api_url = url
	save_config()
	#print("Backend API URL updated to: %s" % url)


func get_backend_api_url() -> String:
	# Check for environment variable override
	var env_url = OS.get_environment("BACKEND_API_URL")
	if not env_url.is_empty():
		return env_url
	return backend_api_url


func set_game_server_port(port: int):
	game_server_port = port
	save_config()
	#print("Game server port updated to: %d" % port)


func _load_gameplay_settings_from_config(config: ConfigFile):
	if config.has_section(GAMEPLAY_CONFIG_SECTION):
		screen_shake_enabled = config.get_value(GAMEPLAY_CONFIG_SECTION, "screen_shake_enabled", screen_shake_enabled)


func _save_gameplay_settings_to_config(config: ConfigFile, _file_existed_before_save: bool):
	config.set_value(GAMEPLAY_CONFIG_SECTION, "screen_shake_enabled", screen_shake_enabled)


func set_screen_shake_enabled(enabled: bool):
	screen_shake_enabled = enabled
	save_config()
