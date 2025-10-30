extends Node

signal keybind_changed(action_name: String, new_event: InputEventKey, key_index: int)

func _ready():
	apply_keybinds_to_input_map()

func apply_keybinds_to_input_map():
	for action_name in UserConfig.custom_keybinds:
		var key_codes: Array[int] = UserConfig.custom_keybinds[action_name]
		
		# Remove the action completely if it exists, then re-add it.
		if InputMap.has_action(action_name):
			InputMap.erase_action(action_name)
		InputMap.add_action(action_name)
		
		for physical_keycode in key_codes:
			if physical_keycode != KEY_NONE:
				var event = InputEventKey.new()
				event.physical_keycode = physical_keycode
				event.pressed = true
				InputMap.action_add_event(action_name, event)

func get_keybind_text(action_name: String, key_index: int = -1) -> String:
	return UserConfig.get_keybind_text(action_name, key_index)

func set_keybind(action_name: String, new_event: InputEventKey, key_index: int):
	if not InputMap.has_action(action_name):
		push_error("Action '%s' does not exist in InputMap." % action_name)
		return
	
	if not UserConfig.custom_keybinds.has(action_name):
		push_error("Action '%s' not found in UserConfig.custom_keybinds. Keybind not set." % action_name)
		return
	
	# Update in-memory custom_keybinds and save via UserConfig
	UserConfig.set_keybind_data(action_name, new_event, key_index)
	
	# Apply the new keybind to InputMap
	# We need to re-apply all keybinds for this action to ensure consistency
	# as InputMap.action_add_event doesn't replace, it adds.
	var current_key_codes: Array[int] = UserConfig.custom_keybinds[action_name]
	InputMap.action_erase_events(action_name)
	for physical_keycode in current_key_codes:
		if physical_keycode != KEY_NONE:
			var event = InputEventKey.new()
			event.physical_keycode = physical_keycode
			event.pressed = true
			InputMap.action_add_event(action_name, event)
	
	keybind_changed.emit(action_name, new_event, key_index)
