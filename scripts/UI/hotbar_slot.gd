extends PanelContainer
class_name HotbarSlot

signal ability_dropped(slot_index: int, ability_data: AbilityData)
signal ability_removed(slot_index: int)

@export var slot_index: int = 0
@export var ability_icon: TextureRect
@export var keybind_label: Label
@export var cooldown_overlay: ColorRect
@export var cooldown_label: Label

var assigned_ability: AbilityData = null
var assigned_consumable: ConsumableData = null
var is_drag_hovering: bool = false

var _cooldown_timer: float = 0.0
var _cooldown_total: float = 0.0

func _ready():
	_update_keybind_label()

	# Enable mouse filter to receive drop events
	mouse_filter = Control.MOUSE_FILTER_STOP

	TooltipTheme.apply_to(self)
	mouse_entered.connect(_on_mouse_entered)

func _process(delta: float) -> void:
	if _cooldown_timer <= 0.0:
		return
	_cooldown_timer -= delta
	if _cooldown_timer <= 0.0:
		_cooldown_timer = 0.0
		if cooldown_overlay:
			cooldown_overlay.visible = false
	else:
		if cooldown_label:
			cooldown_label.text = "%.1fs" % _cooldown_timer
		if cooldown_overlay:
			cooldown_overlay.color.a = 0.4 + 0.3 * (_cooldown_timer / _cooldown_total)

func start_cooldown(ability_id: String, duration: float) -> void:
	if not assigned_ability or assigned_ability.ability_id != ability_id:
		return
	if duration <= 0.0:
		return
	_cooldown_total = duration
	_cooldown_timer = duration
	if cooldown_overlay:
		cooldown_overlay.visible = true
	if cooldown_label:
		cooldown_label.text = "%.1fs" % duration

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		KeybindManager.keybind_changed.connect(_on_keybind_changed)
	elif what == NOTIFICATION_EXIT_TREE:
		KeybindManager.keybind_changed.disconnect(_on_keybind_changed)
		
func _update_keybind_label():
	var action_name = "hotbar_" + str(slot_index + 1)
	if keybind_label:
		keybind_label.text = KeybindManager.get_keybind_text(action_name)

func _on_keybind_changed(action_name: String, _new_event: InputEventKey, _key_index: int):
	var my_action_name = "hotbar_" + str(slot_index + 1)
	if action_name == my_action_name:
		_update_keybind_label()

func _can_drop_data(_at_position: Vector2, data) -> bool:
	# Accept abilities from the ability window and consumables from the inventory.
	if _is_ability_drag(data) or _is_consumable_drag(data):
		if not is_drag_hovering:
			is_drag_hovering = true
			update_visual()
		return true
	if is_drag_hovering:
		is_drag_hovering = false
		update_visual()
	return false

func _is_ability_drag(data) -> bool:
	return data is Dictionary and data.has("ability_data")

func _is_consumable_drag(data) -> bool:
	return data is Slot and data.drag_item is ConsumableData

func _drop_data(_at_position: Vector2, data) -> void:
	if _is_ability_drag(data):
		var ability_data = data["ability_data"]
		assign_ability(ability_data)
		ability_dropped.emit(slot_index, ability_data)
	elif _is_consumable_drag(data):
		assign_consumable(data.drag_item)
		# The consumable stays in the inventory — cancel the source slot's drag
		# so it is neither dropped on the ground nor restored.
		data.cancel_drag()

	is_drag_hovering = false
	update_visual()

@rpc("any_peer", "call_remote", "reliable")
func request_assign_ability(ability_id: String):
	_set_ability(ResourceManager.get_ability_data(ability_id))

@rpc("authority", "call_local", "reliable")
func recieve_assign_ability(ability_id: String):
	_set_ability(ResourceManager.get_ability_data(ability_id))

func assign_ability(ability_data: AbilityData):
	if not ability_data:
		return
	_set_ability(ability_data)
	if not multiplayer.is_server():
		rpc_id(1, "request_assign_ability", ability_data.ability_id)
	else:
		rpc_id(multiplayer.get_remote_sender_id(), "recieve_assign_ability", ability_data.ability_id)

@rpc("any_peer", "call_remote", "reliable")
func request_assign_consumable(item_id: String):
	_set_consumable(ResourceManager.get_item_data(item_id))

@rpc("authority", "call_local", "reliable")
func recieve_assign_consumable(item_id: String):
	_set_consumable(ResourceManager.get_item_data(item_id))

func assign_consumable(consumable: ConsumableData):
	# Resolve to the canonical resource so the icon and item_id are reliable
	# even when the drag carried a duplicated inventory item.
	var canonical = ResourceManager.get_item_data(consumable.item_id) if consumable else null
	if not canonical is ConsumableData:
		return
	_set_consumable(canonical)
	if not multiplayer.is_server():
		rpc_id(1, "request_assign_consumable", canonical.item_id)
	else:
		rpc_id(multiplayer.get_remote_sender_id(), "recieve_assign_consumable", canonical.item_id)

## Sets this slot to hold an ability (local state only — no RPC).
func _set_ability(ability_data: AbilityData) -> void:
	assigned_ability = ability_data
	assigned_consumable = null
	if ability_icon:
		ability_icon.texture = ability_data.ability_icon if ability_data else null
		ability_icon.visible = ability_data != null
	update_visual()

## Sets this slot to hold a consumable (local state only — no RPC).
func _set_consumable(consumable) -> void:
	if not consumable is ConsumableData:
		return
	assigned_consumable = consumable
	assigned_ability = null
	if ability_icon:
		ability_icon.texture = consumable.icon
		ability_icon.visible = true
	update_visual()

@rpc("any_peer", "call_remote", "reliable")
func request_clear_slot():
	_clear_slot()

func clear_slot():
	_clear_slot()
	if not multiplayer.is_server():
		rpc_id(1, "request_clear_slot")

func _clear_slot() -> void:
	assigned_ability = null
	assigned_consumable = null
	if ability_icon:
		ability_icon.texture = null
		ability_icon.visible = false
	update_visual()
	ability_removed.emit(slot_index)

func update_visual():
	var panel_style = get_theme_stylebox("panel").duplicate()
	
	if is_drag_hovering:
		panel_style.border_color = Color(0.2, 0.8, 1.0, 1.0)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
	elif assigned_ability or assigned_consumable:
		panel_style.border_color = Color(0.8, 0.8, 0.2, 1.0)
	else:
		panel_style.border_color = Color(0.35, 0.35, 0.45, 1)
	
	add_theme_stylebox_override("panel", panel_style)

func _gui_input(event: InputEvent):
	# Right-click to clear the slot
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if assigned_ability or assigned_consumable:
			clear_slot()


func _on_mouse_entered() -> void:
	if assigned_ability:
		tooltip_text = assigned_ability.get_tooltip_text(_get_ability_level(assigned_ability))
		TooltipTheme.set_border_color(self, null)
	elif assigned_consumable:
		tooltip_text = _build_consumable_tooltip(assigned_consumable)
		TooltipTheme.set_border_color(self, TooltipTheme.rarity_color_for(assigned_consumable))
	else:
		tooltip_text = ""


func _get_ability_level(ability_data: AbilityData) -> int:
	# The HotbarSlot is `slots_container -> Hotbar`. Walk up to fetch the level
	# from the player's ability component; fall back to 0 if the lookup fails
	# (e.g. before _ready on the parent has run).
	var hb := _get_hotbar()
	if hb and is_instance_valid(hb.ability_component):
		return hb.ability_component.get_ability_level(ability_data.ability_id)
	return 0


func _get_hotbar() -> Hotbar:
	# The hotbar scene wraps slots in a Background PanelContainer, so the
	# Hotbar root is not at a fixed depth. Walk up until we find one.
	var node := get_parent()
	while node != null:
		if node is Hotbar:
			return node
		node = node.get_parent()
	return null


func _build_consumable_tooltip(consumable: ConsumableData) -> String:
	var lines: Array[String] = []
	lines.append(consumable.name)
	if consumable.description:
		lines.append("")
		lines.append(consumable.description)
	return "\n".join(lines)
