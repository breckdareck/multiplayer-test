extends Control
class_name StaffElementWidget

## PR 7 — Staff discipline's signature class widget (MapleStory style).
##
## Lives on the left edge of the screen, vertically centered (same anchor family
## as the sword combo / bow momentum widgets — only one is ever visible at a time
## since they gate on mutually-exclusive disciplines). Shows the active element
## as a colored label (FIRE = red, ICE = blue, LIGHTNING = yellow) with a small
## "ELEMENT" caption. Visible only when the active discipline is STAFF.
##
## Mirrors SwordComboWidget / BowMomentumWidget wiring:
##   - Subscribe to the discipline's source-of-truth component signal
##     (StaffElementComponent.element_changed)
##   - Gate visibility on player.get_active_discipline()
##   - Refresh on equipment changes + active-weapon changes
##   - Hidden for remote players (only the local player sees their own gauge)
##
## The server owns the active element; the client only ever paints what the
## component's element_changed signal hands it (driven on the host directly, on a
## remote client via sync_element_to_client).

#region #################### Constants ####################

## Per-element display: label text + color. Index = StaffElementComponent.Element.
const ELEMENT_NAMES: Array[String] = ["FIRE", "ICE", "LIGHTNING"]
const ELEMENT_COLORS: Array[Color] = [
	Color(1.0, 0.35, 0.2, 1.0),   # FIRE — red/orange
	Color(0.4, 0.75, 1.0, 1.0),   # ICE — light blue
	Color(1.0, 0.85, 0.25, 1.0),  # LIGHTNING — yellow
]

#endregion


#region #################### State ####################

var player: MultiplayerPlayerV2 = null
var staff_element_component: StaffElementComponent = null
var equipment_component: EquipmentComponent = null

@onready var caption_label: Label = $Panel/VBox/CaptionLabel
@onready var element_label: Label = $Panel/VBox/ElementLabel

var _current_element: int = 0

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	# Player-dependent wiring happens in bind_player() — persistent UI layer,
	# (re)bound per spawn / map change (ADR 0009 Stage B).
	visible = false


## Binds this widget to the local player body. Called by LocalPlayerUI.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		visible = false
		return

	staff_element_component = player.staff_element_component
	equipment_component = player.equipment_component

	# element_changed fires on both server and client (via sync_element_to_client).
	if is_instance_valid(staff_element_component):
		staff_element_component.element_changed.connect(_on_element_changed)

	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh_visibility)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Defer the first refresh — equipment slots may not be populated yet at bind.
	call_deferred("_refresh_visibility")
	call_deferred("_refresh_label")


## Drops the binding (teardown). Old-body connections die with the freed body.
func unbind_player() -> void:
	player = null
	staff_element_component = null
	equipment_component = null
	visible = false

#endregion


#region #################### Signal handlers ####################

func _on_element_changed(element: int) -> void:
	_current_element = element
	_refresh_label()
	if visible:
		_pulse()


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	_refresh_visibility()

#endregion


#region #################### Visibility + paint ####################

func _refresh_visibility() -> void:
	if not is_instance_valid(player) or not player.has_method("get_active_discipline"):
		visible = false
		return
	visible = player.get_equipped_disciplines().has(Constants.ClassType.STAFF)
	if visible:
		var is_active: bool = player.get_active_discipline() == Constants.ClassType.STAFF
		modulate.a = 1.0 if is_active else 0.5
		# Sync to current component state on (re)appearance.
		if is_instance_valid(staff_element_component):
			_current_element = staff_element_component.get_current_element()
		_refresh_label()


func _refresh_label() -> void:
	if not is_instance_valid(element_label):
		return
	var idx: int = clampi(_current_element, 0, ELEMENT_NAMES.size() - 1)
	element_label.text = ELEMENT_NAMES[idx]
	element_label.add_theme_color_override("font_color", ELEMENT_COLORS[idx])

#endregion


#region #################### Animations ####################

func _pulse() -> void:
	# Quick scale pop on the whole widget when the element cycles.
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#endregion
