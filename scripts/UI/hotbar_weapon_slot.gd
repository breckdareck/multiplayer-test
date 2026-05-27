extends PanelContainer
class_name HotbarWeaponSlot

## A weapon-loadout widget inside the hotbar (PR 3). One instance per
## loadout slot — primary and secondary. Shows the equipped weapon's icon,
## a highlight when active, a dimmer modulate when inactive, a radial
## cooldown overlay during the 1.5s swap window, and forwards clicks on the
## INACTIVE slot to the player's weapon-swap RPC.

## Emitted when the user clicks this slot while it is NOT the active weapon.
## The Hotbar parent routes this into request_weapon_swap_server.
signal click_to_swap_requested(slot_kind: String)

## "primary" or "secondary" — matches EquipmentComponent's active_weapon enum.
@export var slot_kind: String = "primary"

@onready var icon_rect: TextureRect = $MarginContainer/IconRect
@onready var cooldown_overlay: ColorRect = $MarginContainer/CooldownOverlay
@onready var label: Label = $MarginContainer/SlotLabel

var _active: bool = false
var _cooldown_timer: float = 0.0
var _cooldown_total: float = 0.0
var _flash_remaining: float = 0.0

# Visual state colors.
const ACTIVE_BORDER_COLOR := Color(0.95, 0.85, 0.20, 1.0)
const INACTIVE_BORDER_COLOR := Color(0.30, 0.30, 0.35, 1.0)
const INACTIVE_MODULATE := Color(0.55, 0.55, 0.55, 0.85)
const ACTIVE_MODULATE := Color.WHITE
const FLASH_COLOR := Color(1.4, 1.4, 0.6, 1.0)
const FLASH_DURATION := 0.1

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_on_gui_input)
	_update_visual()
	if is_instance_valid(cooldown_overlay):
		cooldown_overlay.visible = false
	if is_instance_valid(label):
		label.text = "1" if slot_kind == "primary" else "2"


func _process(delta: float) -> void:
	# Tick the cooldown overlay. Server-authoritative duration arrives via
	# the swap_cooldown_started signal handler below.
	if _cooldown_timer > 0.0:
		_cooldown_timer = maxf(0.0, _cooldown_timer - delta)
		if is_instance_valid(cooldown_overlay):
			cooldown_overlay.color.a = clampf(0.55 * (_cooldown_timer / max(_cooldown_total, 0.01)), 0.0, 0.55)
			cooldown_overlay.visible = _cooldown_timer > 0.0

	if _flash_remaining > 0.0:
		_flash_remaining = maxf(0.0, _flash_remaining - delta)
		if _flash_remaining <= 0.0:
			_update_visual()


## Called by Hotbar parent when the active weapon flips.
func set_active(is_active: bool) -> void:
	if is_active == _active:
		return
	_active = is_active
	_update_visual()
	# Play a flash to draw the eye on every state change.
	flash()


## Sets the displayed weapon icon. `null` clears to an "empty" look.
func set_weapon_item(item: ItemData) -> void:
	if is_instance_valid(icon_rect):
		icon_rect.texture = item.icon if item else null
		icon_rect.visible = item != null


## Starts the radial cooldown overlay. Server-authoritative duration.
func start_swap_cooldown(duration: float) -> void:
	if duration <= 0.0:
		return
	_cooldown_total = duration
	_cooldown_timer = duration
	if is_instance_valid(cooldown_overlay):
		cooldown_overlay.visible = true


## Brief tint flash drawing the eye to the swap.
func flash() -> void:
	_flash_remaining = FLASH_DURATION
	modulate = FLASH_COLOR


## Visual ping for a denied attempt (e.g. empty secondary). Reuses the flash
## with a redder tint so it reads as "denied".
func flash_denied() -> void:
	_flash_remaining = FLASH_DURATION * 2.0
	modulate = Color(1.5, 0.5, 0.5, 1.0)


func _update_visual() -> void:
	if _active:
		modulate = ACTIVE_MODULATE
	else:
		modulate = INACTIVE_MODULATE

	var style: StyleBoxFlat = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if style:
		style.border_color = ACTIVE_BORDER_COLOR if _active else INACTIVE_BORDER_COLOR
		add_theme_stylebox_override("panel", style)


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		# Click-to-swap only on the inactive slot. Active-slot clicks no-op.
		if not _active:
			click_to_swap_requested.emit(slot_kind)
