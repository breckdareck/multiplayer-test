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

var selected_class: Constants.ClassType = Constants.ClassType.SWORDSMAN

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
	selected_class += value
	if selected_class > len(Constants.ClassType.values()) - 1:
		selected_class = 0
	elif selected_class < 0:
		selected_class = len(Constants.ClassType.values()) - 1
	
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
	get_tree().change_scene_to_file("res://scenes/UI/CharacterSelectScreen.tscn")

func _on_character_created(_char_name):
	status_label.text = "Character Created!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Return to select screen
	get_tree().change_scene_to_file("res://scenes/UI/CharacterSelectScreen.tscn")

func _on_character_creation_failed(error):
	status_label.text = "Creation Failed: " + error
	status_label.add_theme_color_override("font_color", Color.RED)
