extends Control
class_name BowChargeWidget

## PR 8 — Bow discipline's signature class widget (MapleStory style).
##
## Lives on the left edge of the screen, vertically centered (same anchor family
## as the sword combo widget — only one is ever visible at a time since they
## gate on mutually-exclusive disciplines). Shows a vertical charge bar that
## fills as the held charge builds, with 3 tier ticks (tiers 1/2/3) and a small
## "CHARGE" label. Visible only when the active discipline is BOW.
##
## Mirrors SwordComboWidget's wiring:
##   - Subscribe to the discipline's source-of-truth component signal
##     (BowChargeComponent.charge_changed)
##   - Gate visibility on player.get_active_discipline()
##   - Refresh on equipment changes + active-weapon changes
##   - Hidden for remote players (only the local player sees their own gauge)
##
## The server times the charge; the client only ever paints what the component's
## charge_changed signal hands it (driven on the host directly, on a remote
## client via sync_charge_to_client). The bar interpolates smoothly toward the
## target fill so it reads as a continuous charge even though tier RPCs are
## discrete.

#region #################### Constants ####################

const TIER_COUNT: int = 3

## Bar fill color ramps as the charge climbs — cool at tier 0/1, hot at tier 3.
const FILL_COLOR_LOW: Color = Color(0.4, 0.7, 1.0, 1.0)
const FILL_COLOR_MID: Color = Color(0.5, 1.0, 0.6, 1.0)
const FILL_COLOR_HIGH: Color = Color(1.0, 0.85, 0.25, 1.0)
const FILL_COLOR_MAX: Color = Color(1.0, 0.4, 0.2, 1.0)

## How fast the visible bar chases its target fill (higher = snappier).
const FILL_LERP_SPEED: float = 14.0

#endregion


#region #################### State ####################

var player: MultiplayerPlayerV2 = null
var bow_charge_component: BowChargeComponent = null
var equipment_component: EquipmentComponent = null

@onready var charge_label: Label = $Panel/VBox/ChargeLabel
@onready var bar_back: Panel = $Panel/VBox/BarBack
@onready var bar_fill: Panel = $Panel/VBox/BarBack/BarFill

## Target 0-1 fill from the latest charge_changed; the visible bar lerps to it.
var _target_progress: float = 0.0
var _shown_progress: float = 0.0
var _current_tier: int = 0
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

	# Resolve player off the owner chain — instanced under CanvasLayer/PlayerHUD
	# on the player root, mirroring sword_combo_widget.gd.
	var node: Node = self
	while node and not (node is MultiplayerPlayerV2):
		node = node.get_parent()
	if node is MultiplayerPlayerV2:
		player = node as MultiplayerPlayerV2

	if not is_instance_valid(player):
		visible = false
		return

	# Hide for remote players' widgets — only the local player sees their own
	# class identity gauges (matches PlayerHUD gating + SwordComboWidget).
	if player.player_id != multiplayer.get_unique_id():
		visible = false
		return

	bow_charge_component = player.bow_charge_component
	equipment_component = player.equipment_component

	# charge_changed fires on both server and client (via sync_charge_to_client).
	if is_instance_valid(bow_charge_component):
		bow_charge_component.charge_changed.connect(_on_charge_changed)

	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh_visibility)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Defer the first refresh — equipment slots may not be populated yet at _ready.
	call_deferred("_refresh_visibility")


func _process(delta: float) -> void:
	if not visible:
		return
	# Smoothly chase the target fill so discrete tier syncs read as a continuous
	# charge. Snap to zero instantly on release so the bar empties crisply.
	if _target_progress <= 0.0:
		_shown_progress = 0.0
	else:
		_shown_progress = lerpf(_shown_progress, _target_progress, clampf(delta * FILL_LERP_SPEED, 0.0, 1.0))
	_apply_fill()

#endregion


#region #################### Signal handlers ####################

func _on_charge_changed(tier: int, progress: float) -> void:
	var was_tier: int = _current_tier
	_current_tier = tier
	_target_progress = progress
	if progress <= 0.0:
		# Reset/release — empty immediately.
		_shown_progress = 0.0
		_apply_fill()
	if not visible:
		return
	if tier > was_tier and tier > 0:
		_pulse()


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	_refresh_visibility()

#endregion


#region #################### Visibility + paint ####################

func _refresh_visibility() -> void:
	if not is_instance_valid(player) or not player.has_method("get_active_discipline"):
		visible = false
		return
	visible = player.get_active_discipline() == Constants.ClassType.BOW
	if visible:
		# Sync to current component state on (re)appearance.
		if is_instance_valid(bow_charge_component):
			_current_tier = bow_charge_component.get_current_tier()
		_apply_fill()


func _apply_fill() -> void:
	if not is_instance_valid(bar_back) or not is_instance_valid(bar_fill):
		return
	# Bar fills bottom-up: height tracks progress, anchored to the bottom.
	var full_h: float = bar_back.size.y
	var fill_h: float = full_h * clampf(_shown_progress, 0.0, 1.0)
	bar_fill.size = Vector2(bar_back.size.x, fill_h)
	bar_fill.position = Vector2(0, full_h - fill_h)
	if _fill_style:
		_fill_style.bg_color = _color_for_tier(_current_tier)


func _color_for_tier(tier: int) -> Color:
	match tier:
		0: return FILL_COLOR_LOW
		1: return FILL_COLOR_MID
		2: return FILL_COLOR_HIGH
		_: return FILL_COLOR_MAX

#endregion


#region #################### Animations ####################

func _pulse() -> void:
	# Quick scale pop on the whole widget when a new tier is reached.
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.15, 1.15), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#endregion
