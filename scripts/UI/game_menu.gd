extends Control
class_name GameMenu

@onready var resume_button: Button = %ResumeButton
@onready var keybinds_button: Button = %KeybindsButton
@onready var options_button: Button = %OptionsButton
@onready var show_tutorial_button: Button = %ShowTutorialButton
@onready var disconnect_button: Button = %DisconnectButton
@onready var exit_button: Button = %ExitButton
@onready var sub_menu_container: Control = %SubMenuContainer
@onready var keybinds_menu: KeybindsMenu = %KeybindsMenu
@onready var options_menu: OptionsMenu = %OptionsMenu

var _main_menu_buttons: Array[Button]

func _ready():
	visible = false # Start hidden

	_main_menu_buttons = [resume_button, keybinds_button, options_button, show_tutorial_button, disconnect_button, exit_button]

	resume_button.pressed.connect(_on_resume_button_pressed)
	keybinds_button.pressed.connect(_on_keybinds_button_pressed)
	options_button.pressed.connect(_on_options_button_pressed)
	show_tutorial_button.pressed.connect(_on_show_tutorial_pressed)
	disconnect_button.pressed.connect(_on_disconnect_button_pressed)
	exit_button.pressed.connect(_on_exit_button_pressed)

	keybinds_menu.back_pressed.connect(_on_keybinds_menu_back_pressed)
	options_menu.back_pressed.connect(_on_options_menu_back_pressed)

	_show_main_menu() # Ensure main menu is visible initially

func _unhandled_input(event: InputEvent):
	# Check if the event is a key press for "ui_cancel" and it's not an echo event
	if event is InputEventKey and event.is_action_pressed("ui_cancel") and not event.is_echo():
		if visible:
			_on_resume_button_pressed() # Close menu
		elif not InputManager.is_locked(): # Only open if input is not locked
			open_menu()
		get_viewport().set_input_as_handled() # Consume the event

func open_menu():
	visible = true
	_show_main_menu()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_menu():
	visible = false

func _show_main_menu():
	for button in _main_menu_buttons:
		button.visible = true
	keybinds_menu.hide_menu()
	options_menu.hide_menu()

func _on_resume_button_pressed():
	close_menu()

func _on_keybinds_button_pressed():
	for button in _main_menu_buttons:
		button.visible = false
	keybinds_menu.show_menu()

func _on_keybinds_menu_back_pressed():
	_show_main_menu()

func _on_options_button_pressed():
	for button in _main_menu_buttons:
		button.visible = false
	options_menu.show_menu()

func _on_options_menu_back_pressed():
	_show_main_menu()

## Leave the current session and return to the login screen (keeps the game
## running). The host saves all players first; a client's data is saved
## server-side when its peer drops. Closing the menu first so it isn't mid-teardown.
func _on_disconnect_button_pressed():
	disconnect_button.disabled = true  # guard against a double-press during the await
	close_menu()
	MultiplayerManager.leave_to_main_menu()


func _on_exit_button_pressed():
	get_tree().quit()


## Re-open the first-login tutorial overlay from Options → Show Tutorial. The
## `_onboarded` flag in QuestManager isn't touched (this is a manual replay,
## not a "treat me as new" reset), so closing it again won't re-fire the
## auto-grant of First Blood. The overlay is added to player_HUD — our
## parent — so it covers the full HUD just like the auto-spawned version.
func _on_show_tutorial_pressed():
	close_menu()
	var hud := get_parent()
	if not is_instance_valid(hud):
		return
	# De-dupe in case one is somehow already mounted (e.g. first-login RPC
	# happened to fire on the same frame).
	for child in hud.get_children():
		if child is WelcomeOverlay:
			return
	var overlay := WelcomeOverlay.new()
	hud.add_child(overlay)
