extends PanelContainer
class_name KeybindsMenu

signal back_pressed

@onready var keybind_list: VBoxContainer = %KeybindList
@onready var back_button: Button = %BackButton

var current_rebind_button: Button = null
var current_rebind_key_index: int = 0 # New variable to store key_index
var listening_for_key: bool = false

func _ready():
	back_button.pressed.connect(func(): back_pressed.emit())
	visible = false # Start hidden
	KeybindManager.keybind_changed.connect(_on_keybind_changed)

func _notification(what: int) -> void:
	if what == NOTIFICATION_EXIT_TREE:
		KeybindManager.keybind_changed.disconnect(_on_keybind_changed)

func _on_keybind_changed(action_name: String, _new_event: InputEventKey, key_index: int):
	# Find the buttons for this action and update their text
	for child in keybind_list.get_children():
		if child is HBoxContainer:
			var button1 = child.get_node_or_null("KeyButton1")
			var button2 = child.get_node_or_null("KeyButton2")
			if button1 and button1.get_meta("action_name") == action_name:
				button1.text = KeybindManager.get_keybind_text(action_name, 0)
			if button2 and button2.get_meta("action_name") == action_name:
				button2.text = KeybindManager.get_keybind_text(action_name, 1)

func show_menu():
	visible = true
	_populate_keybinds()

func hide_menu():
	visible = false
	_stop_listening_for_key()

func _populate_keybinds():
	# Clear existing keybind entries
	for child in keybind_list.get_children():
		child.queue_free()
		
	# Add hotbar keybinds
	for i in range(1, 9):
		var action_name = "hotbar_" + str(i)
		_add_keybind_entry(action_name, "Hotbar Slot " + str(i))
	
	# Add other common actions (e.g., Jump, Attack, Move Left/Right)
	_add_keybind_entry("Jump", "Jump")
	_add_keybind_entry("Attack", "Attack")
	_add_keybind_entry("Move Left", "Move Left")
	_add_keybind_entry("Move Right", "Move Right")
	_add_keybind_entry("Move Down", "Move Down")
	_add_keybind_entry("Pickup", "Pickup")
	_add_keybind_entry("OpenStatsWindow", "Open Stats")
	_add_keybind_entry("OpenInventoryWindow", "Open Inventory")
	_add_keybind_entry("OpenEquipmentWindow", "Open Equipment")
	_add_keybind_entry("OpenAbilityWindow", "Open Abilities")
	_add_keybind_entry("OpenSkillTreeWindow", "Open Skill Tree")

func _add_keybind_entry(action_name: String, display_name: String): 
	var hbox = HBoxContainer.new()
	hbox.alignment = HBoxContainer.ALIGNMENT_CENTER
	hbox.add_theme_constant_override("separation", 10) # Reduced separation for two buttons
	
	var name_label = Label.new()
	name_label.text = display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hbox.add_child(name_label)
	
	var key_button1 = Button.new()
	key_button1.name = "KeyButton1" # Name for easy lookup
	key_button1.text = KeybindManager.get_keybind_text(action_name, 0)
	key_button1.custom_minimum_size = Vector2(100, 0)
	key_button1.gui_input.connect(func(event): _on_keybind_button_gui_input(event, key_button1, action_name, 0))
	key_button1.set_meta("action_name", action_name)
	key_button1.set_meta("key_index", 0)
	key_button1.focus_mode = Control.FOCUS_NONE
	hbox.add_child(key_button1)

	var key_button2 = Button.new()
	key_button2.name = "KeyButton2" # Name for easy lookup
	key_button2.text = KeybindManager.get_keybind_text(action_name, 1)
	key_button2.custom_minimum_size = Vector2(100, 0)
	key_button2.gui_input.connect(func(event): _on_keybind_button_gui_input(event, key_button2, action_name, 1))
	key_button2.set_meta("action_name", action_name)
	key_button2.set_meta("key_index", 1)
	key_button2.focus_mode = Control.FOCUS_NONE
	hbox.add_child(key_button2)
	
	keybind_list.add_child(hbox)

func _on_rebind_button_pressed(button: Button, action_name: String, key_index: int):
	if listening_for_key:
		_stop_listening_for_key()
	
	current_rebind_button = button
	current_rebind_key_index = key_index # Store the key_index
	current_rebind_button.text = "Press a key..."
	listening_for_key = true
	
	get_viewport().set_input_as_handled()

func _on_keybind_button_gui_input(event: InputEvent, button: Button, action_name: String, key_index: int):
	if event is InputEventMouseButton and event.is_pressed():
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_clear_keybind(button, action_name, key_index)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			_on_rebind_button_pressed(button, action_name, key_index)
			get_viewport().set_input_as_handled()

func _clear_keybind(button: Button, action_name: String, key_index: int):
	if listening_for_key:
		_stop_listening_for_key() # Stop any active rebind process
	
	var unset_event = InputEventKey.new()
	unset_event.keycode = KEY_NONE
	unset_event.physical_keycode = KEY_NONE
	
	KeybindManager.set_keybind(action_name, unset_event, key_index)
	# The button text will be updated by the _on_keybind_changed signal

func _unhandled_input(event: InputEvent):
	if listening_for_key and event is InputEventKey and event.is_pressed():
		_set_new_keybind(event)
		get_viewport().set_input_as_handled() # Consume the event

func _set_new_keybind(new_event: InputEventKey):
	if current_rebind_button:
		var action_name = current_rebind_button.get_meta("action_name")
		if action_name:
			KeybindManager.set_keybind(action_name, new_event, current_rebind_key_index) # Pass key_index
			# Button text will be updated by _on_keybind_changed signal
		_stop_listening_for_key()

func _stop_listening_for_key():
	if current_rebind_button:
		var action_name = current_rebind_button.get_meta("action_name")
		var key_index = current_rebind_button.get_meta("key_index") # Get key_index from meta
		if action_name != null and key_index != null:
			current_rebind_button.text = KeybindManager.get_keybind_text(action_name, key_index)
	
	current_rebind_button = null
	current_rebind_key_index = 0 # Reset key_index
	listening_for_key = false
