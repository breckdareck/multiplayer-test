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
var current_level: int = 0

func _ready():
	TooltipTheme.apply_to(self)
	mouse_entered.connect(_on_mouse_entered)

## Called by the AbilityWindow to set the data for the slot.
## PR 6: owned_upgrades / total_upgrades drive a small "◆ owned/total" badge
## so the list shows at a glance which abilities have upgrade trees and how
## far they're invested. Defaults keep older callers working (no badge).
func setup(data: AbilityData, level: int, owned_upgrades: int = 0, total_upgrades: int = 0):
	ability_data = data
	current_level = level
	if ability_data:
		if ability_icon:
			ability_icon.texture = data.ability_icon
		if ability_name:
			ability_name.text = data.ability_name

	# Mocking the AbilityType display, replace with actual Constants
	var type_text = "Passive" if data.ability_type == 1 else "Active"
	ability_type.text = type_text

	ability_level.text = str(level)
	_refresh_upgrade_badge(owned_upgrades, total_upgrades)
	_refresh_tooltip()


## Shows/updates an upgrade badge under the ability type. Gold ◆ with
## owned/total count; hidden when the ability has no upgrades. Created lazily
## so the slot scene needs no extra node.
func _refresh_upgrade_badge(owned: int, total: int) -> void:
	var vbox: Node = ability_name.get_parent() if is_instance_valid(ability_name) else null
	if vbox == null:
		return
	var badge: Label = vbox.get_node_or_null("UpgradeBadge") as Label
	if total <= 0:
		if badge:
			badge.visible = false
		return
	if badge == null:
		badge = Label.new()
		badge.name = "UpgradeBadge"
		badge.add_theme_font_size_override("font_size", 8)
		vbox.add_child(badge)
	badge.visible = true
	# Fully-upgraded reads gold; partial reads muted gold.
	var col := Color(1.0, 0.82, 0.3) if owned >= total else Color(0.75, 0.68, 0.4)
	badge.add_theme_color_override("font_color", col)
	badge.text = "◆ %d/%d upgrades" % [owned, total]


func _on_mouse_entered() -> void:
	_refresh_tooltip()


func _refresh_tooltip() -> void:
	if ability_data:
		tooltip_text = ability_data.get_tooltip_text(current_level)
	else:
		tooltip_text = ""


## Render the tooltip as BBCode so [color=...] tags in the description display
## styled instead of raw (Godot's default tooltip is a plain Label).
func _make_custom_tooltip(for_text: String) -> Object:
	return AbilityTooltip.build(for_text)

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
