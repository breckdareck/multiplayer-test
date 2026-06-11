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

func _ready():
	_update_keybind_label()

	# Enable mouse filter to receive drop events
	mouse_filter = Control.MOUSE_FILTER_STOP

	TooltipTheme.apply_to(self)
	mouse_entered.connect(_on_mouse_entered)

func _process(_delta: float) -> void:
	_update_cooldown_display()

## Cooldowns are read from the AbilityComponent's authoritative per-ability
## dict every frame rather than ticked locally per slot. Per-weapon hotbar
## bindings mean a slot's CONTENT changes on weapon swap while the cooldowns
## belong to abilities — a slot-local timer kept painting the outgoing
## ability's cooldown over the incoming one and lost the back bar's still-
## ticking cooldowns when swapping back.
func _update_cooldown_display() -> void:
	var remaining := 0.0
	var total := 0.0
	if assigned_ability:
		var hb := _get_hotbar()
		if hb and is_instance_valid(hb.ability_component):
			remaining = hb.ability_component.get_cooldown_remaining(assigned_ability.ability_id)
			total = hb.get_cooldown_total(assigned_ability.ability_id)

	if remaining <= 0.0:
		if cooldown_overlay and cooldown_overlay.visible:
			cooldown_overlay.visible = false
		return

	if cooldown_overlay:
		cooldown_overlay.visible = true
		cooldown_overlay.color.a = 0.4 + 0.3 * clampf(remaining / maxf(total, remaining), 0.0, 1.0)
	if cooldown_label:
		cooldown_label.text = "%.1fs" % remaining

func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		KeybindManager.keybind_changed.connect(_on_keybind_changed)
	elif what == NOTIFICATION_EXIT_TREE:
		KeybindManager.keybind_changed.disconnect(_on_keybind_changed)
	elif what == NOTIFICATION_DRAG_END:
		# The drop landed elsewhere (or was cancelled) — clear any leftover
		# hover highlight, since _drop_data never fires on this slot.
		if is_drag_hovering:
			is_drag_hovering = false
			update_visual()
		
func _update_keybind_label():
	var action_name = "hotbar_" + str(slot_index + 1)
	if keybind_label:
		keybind_label.text = KeybindManager.get_keybind_text(action_name)

func _on_keybind_changed(action_name: String, _new_event: InputEventKey, _key_index: int):
	var my_action_name = "hotbar_" + str(slot_index + 1)
	if action_name == my_action_name:
		_update_keybind_label()

func _can_drop_data(_at_position: Vector2, data) -> bool:
	# Accept abilities from the ability window, consumables from the inventory,
	# and other hotbar slots (rearrange via move/swap).
	if _is_ability_drag(data) or _is_consumable_drag(data) or _is_hotbar_drag(data):
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

func _is_hotbar_drag(data) -> bool:
	return data is Dictionary and data.get("hotbar_slot") is HotbarSlot and data["hotbar_slot"] != self

func _drop_data(_at_position: Vector2, data) -> void:
	if _is_hotbar_drag(data):
		_swap_with(data["hotbar_slot"])
	elif _is_ability_drag(data):
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

## Dragging an occupied slot rearranges the hotbar: dropping on an empty slot
## moves the binding, dropping on an occupied slot swaps the two.
func _get_drag_data(_at_position: Vector2):
	if not assigned_ability and not assigned_consumable:
		return null

	var preview := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	ps.border_color = Color(0.8, 0.8, 0.2, 1.0)
	ps.set_border_width_all(2)
	preview.add_theme_stylebox_override("panel", ps)
	var icon_rect := TextureRect.new()
	icon_rect.texture = ability_icon.texture if ability_icon else null
	icon_rect.custom_minimum_size = Vector2(48, 48)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.add_child(icon_rect)
	set_drag_preview(preview)

	return {"hotbar_slot": self}

## Exchange contents with another hotbar slot (move when this slot is empty).
## Uses the local setters, then pushes the whole layout once — on_binding_edited
## captures every slot, so one notification covers both ends of the swap.
func _swap_with(source: HotbarSlot) -> void:
	var my_ability := assigned_ability
	var my_consumable := assigned_consumable

	if source.assigned_ability:
		_set_ability(source.assigned_ability)
	elif source.assigned_consumable:
		_set_consumable(source.assigned_consumable)

	if my_ability:
		source._set_ability(my_ability)
	elif my_consumable:
		source._set_consumable(my_consumable)
	else:
		source._clear_slot()

	_notify_binding_changed()

func assign_ability(ability_data: AbilityData):
	if not ability_data:
		return
	_set_ability(ability_data)
	# ADR 0009 Stage B: the binding is persisted by pushing the whole hotbar config
	# through the player's AbilityComponent (under the body → correct per-player
	# routing). The old per-slot RPC was node-addressed into the persistent UI,
	# which cross-resolved to the HOST's hotbar slot on the server (the "overlap").
	_notify_binding_changed()

func assign_consumable(consumable: ConsumableData):
	# Resolve to the canonical resource so the icon and item_id are reliable
	# even when the drag carried a duplicated inventory item.
	var canonical = ResourceManager.get_item_data(consumable.item_id) if consumable else null
	if not canonical is ConsumableData:
		return
	_set_consumable(canonical)
	_notify_binding_changed()

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

func clear_slot():
	_clear_slot()
	_notify_binding_changed()


## Pushes the (changed) live hotbar layout to the player's AbilityComponent so it
## persists for the active weapon. Routed through the component, not a per-slot
## node RPC (ADR 0009 Stage B). No-op during programmatic load (the local setters
## _set_ability/_set_consumable/_clear_slot don't call this).
func _notify_binding_changed() -> void:
	var hb := _get_hotbar()
	if hb and hb.has_method("on_binding_edited"):
		hb.on_binding_edited()

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
		panel_style.border_color = Color(1.0, 0.78, 0.3, 1.0)
		panel_style.border_width_left = 2
		panel_style.border_width_top = 2
		panel_style.border_width_right = 2
		panel_style.border_width_bottom = 2
	elif assigned_ability or assigned_consumable:
		panel_style.border_color = Color(0.92, 0.72, 0.25, 1.0)
	else:
		panel_style.border_color = Color(0.5, 0.34, 0.16, 1)
	
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


## Render the tooltip as BBCode so [color=...] tags in ability descriptions
## display styled instead of raw (Godot's default tooltip is a plain Label).
## Consumables keep their rarity-colored border, matching the inventory tooltip.
func _make_custom_tooltip(for_text: String) -> Object:
	var border = null
	if assigned_consumable and not assigned_ability:
		border = TooltipTheme.rarity_color_for(assigned_consumable)
	return AbilityTooltip.build(for_text, border)


func _get_ability_level(ability_data: AbilityData) -> int:
	# The HotbarSlot is `slots_container -> Hotbar`. Walk up to fetch the level
	# from the player's ability component; fall back to 0 if the lookup fails
	# (e.g. before _ready on the parent has run).
	var hb := _get_hotbar()
	if hb and is_instance_valid(hb.ability_component):
		return hb.ability_component.get_ability_level(ability_data.ability_id)
	return 0


var _hotbar_cache: Hotbar = null

func _get_hotbar() -> Hotbar:
	# The hotbar scene wraps slots in a Background PanelContainer, so the
	# Hotbar root is not at a fixed depth. Walk up until we find one. Cached —
	# slots live persistently under the hotbar (ADR 0009) and this is queried
	# every frame for the cooldown display.
	if is_instance_valid(_hotbar_cache):
		return _hotbar_cache
	var node := get_parent()
	while node != null:
		if node is Hotbar:
			_hotbar_cache = node
			return _hotbar_cache
		node = node.get_parent()
	return null


func _build_consumable_tooltip(consumable: ConsumableData) -> String:
	var lines: Array[String] = []
	lines.append(consumable.name)
	if consumable.description:
		lines.append("")
		lines.append(consumable.description)
	return "\n".join(lines)
