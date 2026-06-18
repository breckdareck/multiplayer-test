extends Control

@onready var name_input = $Panel/VBoxContainer/NameInput
@onready var class_option = $Panel/VBoxContainer/ClassOption
@onready var create_button = $Panel/VBoxContainer/CreateButton
@onready var back_button = $Panel/VBoxContainer/BackButton
@onready var status_label = $Panel/VBoxContainer/StatusLabel
@onready var class_icon = $ClassSelectPanel/ClassIcon
@onready var class_description = $Panel/VBoxContainer/ClassDescription
@onready var left_button = $ClassSelectPanel/LeftButton
@onready var right_button = $ClassSelectPanel/RightButton

const STARTER_DISCIPLINES: Array[Constants.ClassType] = [
	Constants.ClassType.SWORD,
	Constants.ClassType.STAFF,
	Constants.ClassType.BOW,
	Constants.ClassType.DAGGER,
]

var _starter_index: int = 0
var selected_class: Constants.ClassType = Constants.ClassType.SWORD

# Idle bob for the class portrait (cosmetic). Base captured on the first frame so
# the anchored layout has resolved.
const _BOB_AMPLITUDE := 6.0
const _BOB_SPEED := 2.2
var _bob_t := 0.0
var _bob_base_y := 0.0
var _bob_primed := false


func _process(delta: float) -> void:
	if not is_instance_valid(class_icon):
		return
	if not _bob_primed:
		_bob_base_y = class_icon.position.y
		_bob_primed = true
	_bob_t += delta
	class_icon.position.y = _bob_base_y + sin(_bob_t * _BOB_SPEED) * _BOB_AMPLITUDE


func _ready():
	create_button.pressed.connect(_on_create_pressed)
	back_button.pressed.connect(_on_back_pressed)
	left_button.pressed.connect(change_class.bind(-1))
	right_button.pressed.connect(change_class.bind(1))

	NetworkManager.character_created.connect(_on_character_created)
	NetworkManager.character_creation_failed.connect(_on_character_creation_failed)

	# Show first class by default
	change_class(0)

func change_class(value: int):
	_starter_index = wrapi(_starter_index + value, 0, STARTER_DISCIPLINES.size())
	selected_class = STARTER_DISCIPLINES[_starter_index]

	# Get class data from ResourceManager
	var class_data = ResourceManager.get_class_data(selected_class)
	
	if class_data:
		# Update icon/sprite
		if class_icon and class_data.icon:
			class_icon.texture = class_data.icon
		
		# Update description
		if class_description:
			class_description.text = class_data.description

func _on_create_pressed():
	var char_name = name_input.text
	if char_name == "":
		status_label.text = "Please enter a character name."
		return
		
	# Use the selected_class value directly
	var class_id = int(selected_class)
	
	status_label.text = "Creating..."
	status_label.add_theme_color_override("font_color", Color.WHITE)
	NetworkManager.create_character(char_name, class_id)

func _on_back_pressed():
	get_tree().change_scene_to_file("res://scenes/Screens/CharacterSelectScreen.tscn")

func _on_character_created(_char_name):
	status_label.text = "Character Created!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Return to select screen
	get_tree().change_scene_to_file("res://scenes/Screens/CharacterSelectScreen.tscn")

func _on_character_creation_failed(error):
	status_label.text = "Creation Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)
