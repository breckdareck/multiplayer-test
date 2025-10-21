extends PanelContainer
class_name HotbarSlot

signal ability_dropped(slot_index: int, ability_data: AbilityData)
signal ability_removed(slot_index: int)

@export var slot_index: int = 0
@export var ability_icon: TextureRect
@export var keybind_label: Label

var assigned_ability: AbilityData = null
var is_drag_hovering: bool = false

const KEYBINDS = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]

func _ready():
	if keybind_label and slot_index < KEYBINDS.size():
		keybind_label.text = KEYBINDS[slot_index]
	
	# Enable mouse filter to receive drop events
	mouse_filter = Control.MOUSE_FILTER_STOP

func _can_drop_data(_at_position: Vector2, data) -> bool:
	# Check if the data is an AbilityData object
	if data is Dictionary and data.has("ability_data"):
		if not is_drag_hovering:
			is_drag_hovering = true
			update_visual()
		return true
	if is_drag_hovering:
		is_drag_hovering = false
		update_visual()
	return false

func _drop_data(_at_position: Vector2, data) -> void:
	if data is Dictionary and data.has("ability_data"):
		var ability_data = data["ability_data"]
		assign_ability(ability_data)
		ability_dropped.emit(slot_index, ability_data)
	
	is_drag_hovering = false
	update_visual()

func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		is_drag_hovering = false
		update_visual()

@rpc("any_peer", "call_remote", "reliable")
func request_assign_ability(ability_id: String):
	var ability_data = ResourceManager.get_ability_data(ability_id)
	assigned_ability = ability_data
	if ability_icon and ability_data:
		ability_icon.texture = ability_data.ability_icon
		ability_icon.visible = true
	update_visual()
	
@rpc("authority", "call_local", "reliable")
func recieve_assign_ability(ability_id: String):
	var ability_data = ResourceManager.get_ability_data(ability_id)
	assigned_ability = ability_data
	if ability_icon and ability_data:
		ability_icon.texture = ability_data.ability_icon
		ability_icon.visible = true
	update_visual()
		
func assign_ability(ability_data: AbilityData):
	assigned_ability = ability_data
	if ability_icon and ability_data:
		ability_icon.texture = ability_data.ability_icon
		ability_icon.visible = true
	update_visual()
	if not multiplayer.is_server():
		rpc_id(1, "request_assign_ability", ability_data.ability_id)
	else:
		rpc_id(multiplayer.get_remote_sender_id(), "recieve_assign_ability", ability_data.ability_id)

@rpc("any_peer", "call_remote", "reliable")
func request_clear_ability():
	assigned_ability = null
	if ability_icon:
		ability_icon.texture = null
		ability_icon.visible = false
	update_visual()
	ability_removed.emit(slot_index)

func clear_ability():
	assigned_ability = null
	if ability_icon:
		ability_icon.texture = null
		ability_icon.visible = false
	update_visual()
	ability_removed.emit(slot_index)
	if not multiplayer.is_server():
		rpc_id(1, "request_clear_ability")

func update_visual():
	var panel_style = get_theme_stylebox("panel").duplicate()
	
	if is_drag_hovering:
		panel_style.border_color = Color(0.2, 0.8, 1.0, 1.0)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
	elif assigned_ability:
		panel_style.border_color = Color(0.8, 0.8, 0.2, 1.0)
	else:
		panel_style.border_color = Color(0.35, 0.35, 0.45, 1)
	
	add_theme_stylebox_override("panel", panel_style)

func _gui_input(event: InputEvent):
	# Right-click to remove ability
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if assigned_ability:
			clear_ability()
