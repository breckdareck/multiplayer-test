extends PanelContainer
class_name AbilitySlot

## Signal emitted when this slot is clicked, passing the ability ID
signal ability_selected(ability_id: String)

@export var ability_icon: TextureRect
@export var ability_name: Label
@export var ability_type: Label
@export var ability_level: Label

var ability_data: AbilityData
var is_selected: bool = false
#var NORMAL_STYLE = preload("uid://buknvqomhng01").get_node(".").get_theme_stylebox("panel")
#var SELECTED_STYLE = preload("uid://buknvqomhng01").get_node(".").get_stylebox("panel", "AbilitySlot")

func _ready():
	# NOTE: The above style loading is a simple way; you should load the actual
	# selected stylebox from your project's theme.
	pass

## Called by the AbilityWindow to set the data for the slot
func setup(data: AbilityData, current_level: int):
	ability_data = data
	if ability_data:
		if ability_icon:
			ability_icon.texture = data.ability_icon
		if ability_name:
			ability_name.text = data.ability_name
	
	# Mocking the AbilityType display, replace with actual Constants
	var type_text = "Passive" if data.ability_type == 1 else "Active"
	ability_type.text = type_text
	
	ability_level.text = str(current_level)

## Handles mouse click to select the ability
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if ability_data:
			ability_selected.emit(ability_data.ability_id)

## Visually updates the slot to show if it is selected
func set_selected(selected: bool):
	is_selected = selected
	if is_selected:
		# Use a visible style for selection
		var panel = self.get_theme_stylebox("panel").duplicate()
		panel.border_color = Color(1.0, 0.8, 0.0, 1)
		add_theme_stylebox_override("panel", panel)
		#add_theme_stylebox_override("panel", preload("res://scenes/UI/ability_slot.tscn").get_node("AbilitySlot").get_theme_stylebox("panel"))
	else:
		# Use the normal style
		var panel = self.get_theme_stylebox("panel").duplicate()
		panel.border_color = Color(0.35, 0.35, 0.45, 1)
		add_theme_stylebox_override("panel", panel)
