extends Control
class_name SwordComboWidget

const GaugeInfo = preload("res://scripts/UI/gauge_info.gd")

## PR 5 — Sword discipline's signature class widget (MapleStory style).
##
## Lives on the left edge of the screen, vertically centered. Shows a vertical
## stack of 3 combo pips and a small "COMBO" label. Visible only when the
## active discipline is SWORD (Tab-swap to bow → widget hides; swap back → it
## reappears with the same combo count, since combo state persists across
## Tab-swaps per the locked design).
##
## This widget is intentionally NOT inside the hotbar. The hotbar holds bindings
## and weapon-loadout slots; signature gauges (combo, bow momentum, staff modes,
## dagger stealth) belong to the class identity and get their own anchored
## widgets so the hotbar can stay compact across all disciplines.
##
## Pattern for future signature widgets (PRs 6-8):
##   - Subscribe to the discipline's source-of-truth component signal
##   - Gate visibility on player.get_active_discipline()
##   - Refresh on equipment changes + active-weapon changes
##   - Animate on transitions (build / spend) for tactile feedback

#region #################### Constants ####################

const COMBO_CAP: int = 3
const PIP_FILLED_COLOR: Color = Color(1.0, 0.65, 0.15, 1.0)
const PIP_FILLED_BORDER: Color = Color(1.0, 0.85, 0.4, 1.0)
const PIP_EMPTY_COLOR: Color = Color(0.12, 0.1, 0.085, 0.85)
const PIP_EMPTY_BORDER: Color = Color(0.4, 0.32, 0.22, 1.0)

#endregion


#region #################### State ####################

var player: MultiplayerPlayerV2 = null
var sword_combo_component: SwordComboComponent = null
var equipment_component: EquipmentComponent = null

@onready var combo_label: Label = $Panel/VBox/ComboLabel
@onready var pip_box: VBoxContainer = $Panel/VBox/Pips
var combo_pips: Array[Panel] = []
var _pip_style_empty: StyleBox = null
var _pip_style_filled: StyleBox = null

## Last observed combo count. Used by _on_combo_changed to differentiate
## gain (pulse newly-filled pip) from spend (flash all pips).
var _last_combo_count: int = 0

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_pip_style_empty = _build_pip_style(PIP_EMPTY_COLOR, PIP_EMPTY_BORDER)
	_pip_style_filled = _build_pip_style(PIP_FILLED_COLOR, PIP_FILLED_BORDER)

	combo_pips = []
	for i in range(COMBO_CAP):
		var pip: Panel = pip_box.get_node_or_null("Pip%d" % i) as Panel
		if pip:
			combo_pips.append(pip)
			pip.add_theme_stylebox_override("panel", _pip_style_empty)
	# Non-empty tooltip_text makes Godot call _make_custom_tooltip() on hover.
	tooltip_text = "COMBO POINTS"
	# Player-dependent wiring happens in bind_player() — this widget lives in the
	# persistent UI layer and is (re)bound per spawn / map change (ADR 0009 Stage B).
	visible = false


## Skinned BBCode tooltip explaining the combo-point gauge (matches the ability /
## item tooltip look) instead of Godot's raw-text default.
func _make_custom_tooltip(_for_text: String) -> Object:
	return AbilityTooltip.build(GaugeInfo.sword_combo())


## Binds this widget to the local player body. Called by LocalPlayerUI.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		visible = false
		return

	sword_combo_component = player.sword_combo_component
	equipment_component = player.equipment_component

	# Subscribe to the source of truth (combo_changed fires on both server
	# and client via sync_combo_to_client). Single connection works in both
	# host and remote-client topologies.
	if is_instance_valid(sword_combo_component):
		sword_combo_component.combo_changed.connect(_on_combo_changed)

	# Equipment + active-weapon swaps flip the active discipline → toggle
	# visibility. Refresh on every change.
	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh_visibility)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Defer the first refresh — equipment slots may not be populated yet
	# when bind fires (loaded asynchronously after spawn).
	call_deferred("_refresh_visibility")
	call_deferred("_refresh_pips")


## Drops the binding (teardown). Old-body signal connections die with the freed
## body; this clears refs. Stage C (live-body reparent) will need disconnects.
func unbind_player() -> void:
	player = null
	sword_combo_component = null
	equipment_component = null
	visible = false

#endregion


#region #################### Signal handlers ####################

func _on_combo_changed(new_count: int) -> void:
	var was: int = _last_combo_count
	_last_combo_count = new_count
	_refresh_pips()
	if not visible:
		return
	if new_count > was:
		# Build — pulse newly-filled pip(s). Usually one per tick.
		for i in range(was, min(new_count, combo_pips.size())):
			_pulse_pip(combo_pips[i])
	elif new_count < was and was > 0:
		# Consume — quick flash across the whole widget.
		_flash_widget()


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	_refresh_visibility()

#endregion


#region #################### Visibility + paint ####################

func _refresh_visibility() -> void:
	if not is_instance_valid(player) or not player.has_method("get_active_discipline"):
		visible = false
		return
	visible = player.get_equipped_disciplines().has(Constants.ClassType.SWORD)
	if visible:
		var is_active: bool = player.get_active_discipline() == Constants.ClassType.SWORD
		modulate.a = 1.0 if is_active else 0.5
		_refresh_pips()


func _refresh_pips() -> void:
	var count: int = 0
	if is_instance_valid(sword_combo_component):
		count = sword_combo_component.get_combo_count()
	for i in range(combo_pips.size()):
		var pip: Panel = combo_pips[i]
		if not is_instance_valid(pip):
			continue
		var should_fill: bool = i < count
		var style_to_apply: StyleBox = _pip_style_filled if should_fill else _pip_style_empty
		if pip.get_theme_stylebox("panel") == style_to_apply:
			continue
		pip.add_theme_stylebox_override("panel", style_to_apply)

#endregion


#region #################### Animations ####################

func _pulse_pip(pip: Panel) -> void:
	if not is_instance_valid(pip):
		return
	pip.pivot_offset = pip.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(pip, "scale", Vector2(1.4, 1.4), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pip, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _flash_widget() -> void:
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate", Color(1.6, 1.4, 0.8, 1.0), 0.06)
	tween.tween_property(self, "modulate", Color.WHITE, 0.12)

#endregion


#region #################### Helpers ####################

func _build_pip_style(bg: Color, border: Color) -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	return style

#endregion
