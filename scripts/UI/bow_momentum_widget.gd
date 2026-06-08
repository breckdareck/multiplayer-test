extends Control
class_name BowMomentumWidget

const GaugeInfo = preload("res://scripts/UI/gauge_info.gd")

## Bow discipline's signature class widget (MapleStory style).
##
## Lives on the left edge of the screen, vertically centered (same anchor family
## as the sword combo / staff element / shadowmeld widgets — only one is ever
## visible at a time since they gate on mutually-exclusive disciplines). Shows a
## vertical MOMENTUM gauge: a bottom-up fill bar driven by get_fill_fraction()
## plus a "MOMENTUM" caption and an "xN" stack label. The fill ramps cool->hot as
## Momentum climbs and pulses when it tops out. Visible only when the active
## discipline is BOW.
##
## Mirrors StaffElementWidget / SwordComboWidget / ShadowmeldWidget wiring:
##   - Subscribe to the discipline's source-of-truth component signal
##     (BowMomentumComponent.momentum_changed)
##   - Gate visibility on player.get_active_discipline()
##   - Refresh on equipment changes + active-weapon changes
##   - Hidden for remote players (only the local player sees their own gauge)
##
## The server owns the stack count; the client only ever paints what the
## component's momentum_changed signal hands it (driven on the host directly, on a
## remote client via sync_momentum_to_client). The bar interpolates smoothly
## toward the target fill so a stack change reads as a continuous fill.

#region #################### Constants ####################

## Fill color ramps as Momentum climbs — cool at low stacks, hot near the cap.
const FILL_COLOR_LOW: Color = Color(0.4, 0.7, 1.0, 1.0)
const FILL_COLOR_MID: Color = Color(0.5, 1.0, 0.6, 1.0)
const FILL_COLOR_HIGH: Color = Color(1.0, 0.85, 0.25, 1.0)
const FILL_COLOR_MAX: Color = Color(1.0, 0.4, 0.2, 1.0)

## How fast the visible bar chases its target fill (higher = snappier).
const FILL_LERP_SPEED: float = 14.0

#endregion


#region #################### State ####################

var player: MultiplayerPlayerV2 = null
var bow_momentum_component: BowMomentumComponent = null
var equipment_component: EquipmentComponent = null

@onready var caption_label: Label = $Panel/VBox/CaptionLabel
@onready var stack_label: Label = $Panel/VBox/StackLabel
@onready var bar_back: Panel = $Panel/VBox/BarBack
@onready var bar_fill: Panel = $Panel/VBox/BarBack/BarFill

## Target 0-1 fill from the latest momentum_changed; the visible bar lerps to it.
var _target_progress: float = 0.0
var _shown_progress: float = 0.0
var _stacks: int = 0
var _max_stacks: int = 1
var _fill_style: StyleBoxFlat = null

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	_fill_style = StyleBoxFlat.new()
	_fill_style.bg_color = FILL_COLOR_LOW
	_fill_style.corner_radius_top_left = 4
	_fill_style.corner_radius_top_right = 4
	_fill_style.corner_radius_bottom_left = 4
	_fill_style.corner_radius_bottom_right = 4
	if is_instance_valid(bar_fill):
		bar_fill.add_theme_stylebox_override("panel", _fill_style)
	# Non-empty tooltip_text makes Godot call _make_custom_tooltip() on hover.
	tooltip_text = "MOMENTUM"
	# Player-dependent wiring happens in bind_player() — persistent UI layer,
	# (re)bound per spawn / map change (ADR 0009 Stage B).
	visible = false


## Skinned BBCode tooltip explaining the Momentum gauge (matches the ability /
## item tooltip look) instead of Godot's raw-text default.
func _make_custom_tooltip(_for_text: String) -> Object:
	return AbilityTooltip.build(GaugeInfo.bow_momentum())


## Binds this widget to the local player body. Called by LocalPlayerUI.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		visible = false
		return

	bow_momentum_component = player.bow_momentum_component
	equipment_component = player.equipment_component

	# momentum_changed fires on both server and client (via sync_momentum_to_client).
	if is_instance_valid(bow_momentum_component):
		bow_momentum_component.momentum_changed.connect(_on_momentum_changed)

	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh_visibility)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Defer the first refresh — equipment slots may not be populated yet at bind.
	call_deferred("_refresh_visibility")


## Drops the binding (teardown). Old-body connections die with the freed body.
func unbind_player() -> void:
	player = null
	bow_momentum_component = null
	equipment_component = null
	visible = false


func _process(delta: float) -> void:
	if not visible:
		return
	# Smoothly chase the target fill so discrete stack syncs read as a continuous
	# gauge. Snap to zero instantly on reset so the bar empties crisply.
	if _target_progress <= 0.0:
		_shown_progress = 0.0
	else:
		_shown_progress = lerpf(_shown_progress, _target_progress, clampf(delta * FILL_LERP_SPEED, 0.0, 1.0))
	_apply_fill()

#endregion


#region #################### Signal handlers ####################

func _on_momentum_changed(stacks: int, max_stacks: int) -> void:
	var was_stacks: int = _stacks
	_stacks = stacks
	_max_stacks = maxi(1, max_stacks)
	_target_progress = float(_stacks) / float(_max_stacks)
	if _stacks <= 0:
		# Reset/empty — drop the bar immediately.
		_shown_progress = 0.0
	_refresh_label()
	_apply_fill()
	if not visible:
		return
	# Pop on a gain, and a stronger pop when topping out.
	if _stacks > was_stacks:
		_pulse(1.18 if _stacks >= _max_stacks else 1.1)


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	_refresh_visibility()

#endregion


#region #################### Visibility + paint ####################

func _refresh_visibility() -> void:
	if not is_instance_valid(player) or not player.has_method("get_active_discipline"):
		visible = false
		return
	visible = player.get_equipped_disciplines().has(Constants.ClassType.BOW)
	if visible:
		var is_active: bool = player.get_active_discipline() == Constants.ClassType.BOW
		modulate.a = 1.0 if is_active else 0.5
		# Sync to current component state on (re)appearance.
		if is_instance_valid(bow_momentum_component):
			_stacks = bow_momentum_component.get_stacks()
			_target_progress = bow_momentum_component.get_fill_fraction()
		_refresh_label()
		_apply_fill()


func _refresh_label() -> void:
	if not is_instance_valid(stack_label):
		return
	stack_label.text = "x%d" % _stacks
	stack_label.add_theme_color_override("font_color", _color_for_stacks())


func _apply_fill() -> void:
	if not is_instance_valid(bar_back) or not is_instance_valid(bar_fill):
		return
	# Bar fills bottom-up: height tracks progress, anchored to the bottom.
	var full_h: float = bar_back.size.y
	var fill_h: float = full_h * clampf(_shown_progress, 0.0, 1.0)
	bar_fill.size = Vector2(bar_back.size.x, fill_h)
	bar_fill.position = Vector2(0, full_h - fill_h)
	if _fill_style:
		_fill_style.bg_color = _color_for_stacks()


## Ramp the fill / label color across the gauge: cool low, hot near the cap.
func _color_for_stacks() -> Color:
	if _max_stacks <= 0:
		return FILL_COLOR_LOW
	var frac: float = float(_stacks) / float(_max_stacks)
	if frac >= 1.0:
		return FILL_COLOR_MAX
	elif frac >= 0.66:
		return FILL_COLOR_HIGH
	elif frac >= 0.33:
		return FILL_COLOR_MID
	return FILL_COLOR_LOW

#endregion


#region #################### Animations ####################

func _pulse(to_scale: float) -> void:
	# Quick scale pop on the whole widget when Momentum builds.
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(to_scale, to_scale), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#endregion
