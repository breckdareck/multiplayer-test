class_name CheatUI
extends CanvasLayer

# UI References
@onready var cheat_toggle: CheckBox = $MainContainer/VBoxContainer/Header/CheatToggle
@onready var item_container: GridContainer = $MainContainer/VBoxContainer/ItemSection/ItemContainer
@onready var player_container: GridContainer = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer
@onready var console_container: VBoxContainer = $MainContainer/VBoxContainer/ConsoleSection/ConsoleContainer
@onready var console_input: LineEdit = $MainContainer/VBoxContainer/ConsoleSection/ConsoleContainer/ConsoleInput
@onready var console_output: RichTextLabel = $MainContainer/VBoxContainer/ConsoleSection/ConsoleContainer/ConsoleOutput
@onready var player_info_label: RichTextLabel = $MainContainer/VBoxContainer/PlayerSection/PlayerInfo
@onready var close_button: Button = $MainContainer/VBoxContainer/Header/CloseButton

# Item spawning controls
@onready var item_name_input: LineEdit = $MainContainer/VBoxContainer/ItemSection/ItemContainer/ItemNameInput
@onready var item_amount_input: SpinBox = $MainContainer/VBoxContainer/ItemSection/ItemContainer/ItemAmountInput
@onready var add_item_button: Button = $MainContainer/VBoxContainer/ItemSection/ItemContainer/AddItemButton
@onready var item_type_dropdown: OptionButton = $MainContainer/VBoxContainer/ItemSection/ItemContainer/ItemTypeDropdown
@onready var add_type_button: Button = $MainContainer/VBoxContainer/ItemSection/ItemContainer/AddTypeButton

# Player modification controls
@onready var health_input: SpinBox = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/HealthInput
@onready var set_health_button: Button = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/SetHealthButton
@onready var level_input: SpinBox = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/LevelInput
@onready var set_level_button: Button = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/SetLevelButton
@onready var exp_input: SpinBox = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/ExpInput
@onready var add_exp_button: Button = $MainContainer/VBoxContainer/PlayerSection/PlayerContainer/AddExpButton

# Quick action buttons
@onready var fill_inv_button: Button = $MainContainer/VBoxContainer/QuickActions/FillInvButton
@onready var clear_inv_button: Button = $MainContainer/VBoxContainer/QuickActions/ClearInvButton
@onready var god_mode_button: Button = $MainContainer/VBoxContainer/QuickActions/GodModeButton
@onready var teleport_button: Button = $MainContainer/VBoxContainer/QuickActions/TeleportButton

var cheat_manager: CheatManager

func _ready() -> void:
	# Get reference to cheat manager
	cheat_manager = CheatManager.instance
	if not cheat_manager:
		push_error("CheatManager not found!")
		return
	
	# Connect signals
	cheat_manager.cheats_toggled.connect(_on_cheats_toggled)
	cheat_manager.item_added.connect(_on_item_added)
	cheat_manager.player_stats_modified.connect(_on_player_stats_modified)
	
	# Connect UI signals
	cheat_toggle.toggled.connect(_on_cheat_toggle_toggled)
	add_item_button.pressed.connect(_on_add_item_pressed)
	add_type_button.pressed.connect(_on_add_type_pressed)
	set_health_button.pressed.connect(_on_set_health_pressed)
	set_level_button.pressed.connect(_on_set_level_pressed)
	add_exp_button.pressed.connect(_on_add_exp_pressed)
	fill_inv_button.pressed.connect(_on_fill_inv_pressed)
	clear_inv_button.pressed.connect(_on_clear_inv_pressed)
	god_mode_button.pressed.connect(_on_god_mode_pressed)
	teleport_button.pressed.connect(_on_teleport_pressed)
	console_input.text_submitted.connect(_on_console_input_submitted)
	close_button.pressed.connect(_on_close_button_pressed)
	
	# Setup item type dropdown
	_setup_item_type_dropdown()
	
	# Setup initial state
	_update_ui_state()
	_update_player_info()
	
	# Set this UI in the cheat manager
	cheat_manager.set_cheat_ui(self)
	
	# Hide by default
	visible = false

func _setup_item_type_dropdown() -> void:
	item_type_dropdown.clear()
	item_type_dropdown.add_item("ANY")
	item_type_dropdown.add_item("EQUIPMENT")
	item_type_dropdown.add_item("CONSUMABLE")
	item_type_dropdown.add_item("MATERIAL")

func _update_ui_state() -> void:
	var cheats_enabled = cheat_manager.cheats_enabled
	
	# Temporarily disconnect the signal to prevent infinite recursion
	cheat_toggle.toggled.disconnect(_on_cheat_toggle_toggled)
	cheat_toggle.button_pressed = cheats_enabled
	cheat_toggle.toggled.connect(_on_cheat_toggle_toggled)
	
	# Enable/disable all controls based on cheat state
	item_container.modulate = Color.WHITE if cheats_enabled else Color.GRAY
	player_container.modulate = Color.WHITE if cheats_enabled else Color.GRAY
	console_container.modulate = Color.WHITE if cheats_enabled else Color.GRAY
	
	# Disable individual controls
	item_name_input.editable = cheats_enabled
	item_amount_input.editable = cheats_enabled
	add_item_button.disabled = !cheats_enabled
	item_type_dropdown.disabled = !cheats_enabled
	add_type_button.disabled = !cheats_enabled
	
	health_input.editable = cheats_enabled
	set_health_button.disabled = !cheats_enabled
	level_input.editable = cheats_enabled
	set_level_button.disabled = !cheats_enabled
	exp_input.editable = cheats_enabled
	add_exp_button.disabled = !cheats_enabled
	
	fill_inv_button.disabled = !cheats_enabled
	clear_inv_button.disabled = !cheats_enabled
	god_mode_button.disabled = !cheats_enabled
	teleport_button.disabled = !cheats_enabled
	
	console_input.editable = cheats_enabled

func _update_player_info() -> void:
	if not cheat_manager.current_player:
		player_info_label.text = "No player found"
		return
	
	var info = cheat_manager.get_player_info()
	player_info_label.text = """[b]Player Info:[/b]
ID: %d
Username: %s
Position: %s
Health: %d/%d
Level: %d
Experience: %d
Inventory: %d/%d items""" % [
		info.get("player_id", 0),
		info.get("username", "Unknown"),
		info.get("position", Vector2.ZERO),
		info.get("health", 0),
		info.get("max_health", 0),
		info.get("level", 0),
		info.get("experience", 0),
		info.get("inventory_items", 0),
		info.get("inventory_slots", 0)
	]

func _on_cheat_toggle_toggled(button_pressed: bool) -> void:
	cheat_manager.toggle_cheats()

func _on_add_item_pressed() -> void:
	var item_name = item_name_input.text.strip_edges()
	var amount = int(item_amount_input.value)
	
	if item_name.is_empty():
		_add_console_message("Error: Please enter an item name", Color.RED)
		return
	
	var success = cheat_manager.add_item_to_inventory(item_name, amount)
	if success:
		_add_console_message("Added %dx %s to inventory" % [amount, item_name], Color.GREEN)
		item_name_input.clear()
	else:
		_add_console_message("Failed to add item: %s" % item_name, Color.RED)

func _on_add_type_pressed() -> void:
	var item_type_name = item_type_dropdown.get_item_text(item_type_dropdown.selected)
	var amount = int(item_amount_input.value)
	
	var item_type = Constants.ItemType[item_type_name]
	var success = cheat_manager.add_item_by_type(item_type, amount)
	
	if success:
		_add_console_message("Added %dx random %s item to inventory" % [amount, item_type_name], Color.GREEN)
	else:
		_add_console_message("Failed to add %s item" % item_type_name, Color.RED)

func _on_set_health_pressed() -> void:
	var health = int(health_input.value)
	var success = cheat_manager.set_player_health(health)
	
	if success:
		_add_console_message("Health set to %d" % health, Color.GREEN)
		_update_player_info()
	else:
		_add_console_message("Failed to set health", Color.RED)

func _on_set_level_pressed() -> void:
	var level = int(level_input.value)
	var success = cheat_manager.set_player_level(level)
	
	if success:
		_add_console_message("Level set to %d" % level, Color.GREEN)
		_update_player_info()
	else:
		_add_console_message("Failed to set level", Color.RED)

func _on_add_exp_pressed() -> void:
	var exp = int(exp_input.value)
	var success = cheat_manager.modify_player_experience(exp)
	
	if success:
		_add_console_message("Added %d experience" % exp, Color.GREEN)
		_update_player_info()
	else:
		_add_console_message("Failed to add experience", Color.RED)

func _on_fill_inv_pressed() -> void:
	var success = cheat_manager.fill_inventory_with_items()
	
	if success:
		_add_console_message("Inventory filled with random items", Color.GREEN)
	else:
		_add_console_message("Failed to fill inventory", Color.RED)

func _on_clear_inv_pressed() -> void:
	var success = cheat_manager.clear_inventory()
	
	if success:
		_add_console_message("Inventory cleared", Color.GREEN)
	else:
		_add_console_message("Failed to clear inventory", Color.RED)

func _on_god_mode_pressed() -> void:
	var enabled = cheat_manager.toggle_god_mode()
	
	if enabled:
		_add_console_message("God mode enabled", Color.YELLOW)
		god_mode_button.text = "Disable God Mode"
	else:
		_add_console_message("God mode disabled", Color.WHITE)
		god_mode_button.text = "Enable God Mode"

func _on_teleport_pressed() -> void:
	var success = cheat_manager.teleport_player_to_spawn()
	
	if success:
		_add_console_message("Player teleported to spawn", Color.GREEN)
	else:
		_add_console_message("Failed to teleport player", Color.RED)

func _on_console_input_submitted(new_text: String) -> void:
	if new_text.strip_edges().is_empty():
		return
	
	# Add user input to console
	_add_console_message("> " + new_text, Color.CYAN)
	
	# Parse command
	var parts = new_text.split(" ")
	var command = parts[0]
	var args = parts.slice(1)
	
	# Execute command
	var result = cheat_manager.execute_cheat_command(command, args)
	_add_console_message(result, Color.WHITE)
	
	# Clear input
	console_input.clear()
	
	# Update player info if stats were modified
	if result.contains("successfully") or result.contains("set") or result.contains("added"):
		_update_player_info()

func _on_close_button_pressed() -> void:
	visible = false

func _add_console_message(message: String, color: Color = Color.WHITE) -> void:
	var timestamp = Time.get_time_string_from_system()
	var formatted_message = "[color=#888888][%s][/color] %s" % [timestamp, message]
	
	console_output.append_text(formatted_message)
	console_output.newline()
	
	# Auto-scroll to bottom
	console_output.scroll_to_line(console_output.get_line_count() - 1)

func _on_cheats_toggled(enabled: bool) -> void:
	_update_ui_state()
	_add_console_message("Cheats %s" % ("enabled" if enabled else "disabled"), 
		Color.GREEN if enabled else Color.RED)

func _on_item_added(item: ItemData, success: bool) -> void:
	if success:
		_add_console_message("Item added: %s (x%d)" % [item.name, item.current_stack_amount], Color.GREEN)
		_update_player_info()

func _on_player_stats_modified() -> void:
	_update_player_info()

# Public method to show/hide the UI
func toggle_visibility() -> void:
	visible = !visible
	if visible:
		_update_player_info()
		_update_ui_state()
