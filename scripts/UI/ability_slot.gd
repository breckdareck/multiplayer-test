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

func _ready():
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

## Enables dragging the ability to the hotbar
func _get_drag_data(_at_position: Vector2):
	if not ability_data:
		return null
	
	if ability_data.ability_type == Constants.AbilityType.PASSIVE:
		#print("Cannot drag Passive ability")
		return null
	
	# Only allow dragging learned abilities (level > 0)
	var current_level = int(ability_level.text) if ability_level else 0
	if current_level <= 0:
		#print("Cannot drag unlearned ability")
		return null
	
	# Create preview for dragging
	var preview = PanelContainer.new()
	var preview_style = StyleBoxFlat.new()
	preview_style.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	preview_style.border_color = Color(0.8, 0.8, 0.2, 1.0)
	preview_style.border_width_left = 2
	preview_style.border_width_top = 2
	preview_style.border_width_right = 2
	preview_style.border_width_bottom = 2
	preview.add_theme_stylebox_override("panel", preview_style)
	
	var icon = TextureRect.new()
	icon.texture = ability_data.ability_icon
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.add_child(icon)
	
	set_drag_preview(preview)
	
	# Return the ability data in a dictionary
	return {"ability_data": ability_data}

## Visually updates the slot to show if it is selected
func set_selected(selected: bool):
	is_selected = selected
	if is_selected:
		# Use a visible style for selection
		var panel = self.get_theme_stylebox("panel").duplicate()
		panel.border_color = Color(1.0, 0.8, 0.0, 1)
		add_theme_stylebox_override("panel", panel)
	else:
		# Use the normal style
		var panel = self.get_theme_stylebox("panel").duplicate()
		panel.border_color = Color(0.35, 0.35, 0.45, 1)
		add_theme_stylebox_override("panel", panel)
