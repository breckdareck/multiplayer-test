extends Control
class_name ShadowmeldWidget

const GaugeInfo = preload("res://scripts/UI/gauge_info.gd")

## PR 7 — Dagger discipline's signature class widget (MapleStory style).
##
## Lives on the left edge of the screen, vertically centered (same anchor family
## as the sword combo / bow momentum / staff element widgets — only one is ever
## visible at a time since they gate on mutually-exclusive disciplines). Shows the
## Shadowmeld state as a colored label: STEALTHED (active), READY (off cooldown),
## or a recharging countdown while on cooldown. Visible only when the active
## discipline is DAGGER.
##
## Mirrors StaffElementWidget / SwordComboWidget / BowMomentumWidget wiring:
##   - Subscribe to the discipline's source-of-truth component signal
##     (ShadowmeldComponent.shadowmeld_changed)
##   - Gate visibility on player.get_active_discipline()
##   - Refresh on equipment changes + active-weapon changes
##   - Hidden for remote players (only the local player sees their own gauge)
##
## The server owns the stealth state; the client only ever paints what the
## component's shadowmeld_changed signal hands it (driven on the host directly, on
## a remote client via sync_shadowmeld_to_client). A light _process poll refreshes
## the cooldown countdown text while recharging (the component owns the clock).

#region #################### Constants ####################

const STEALTHED_COLOR: Color = Color(0.65, 0.45, 0.95, 1.0)  # purple — cloaked
const READY_COLOR: Color = Color(0.55, 0.85, 0.6, 1.0)       # green — ready
const COOLDOWN_COLOR: Color = Color(0.55, 0.5, 0.42, 1.0)    # warm grey — recharging

#endregion


#region #################### State ####################

var player: MultiplayerPlayerV2 = null
var shadowmeld_component: ShadowmeldComponent = null
var equipment_component: EquipmentComponent = null

@onready var caption_label: Label = $Panel/VBox/CaptionLabel
@onready var state_label: Label = $Panel/VBox/StateLabel

var _is_stealthed: bool = false
## True while the cooldown countdown is ticking. Lets _process fire ONE final
## _refresh_label() on the recharging→ready transition so the label flips to
## "READY" instead of freezing on the last "0.0s" countdown value.
var _was_recharging: bool = false

#endregion


#region #################### Lifecycle ####################

func _ready() -> void:
	# Non-empty tooltip_text makes Godot call _make_custom_tooltip() on hover.
	tooltip_text = "SHADOWMELD"
	# Player-dependent wiring happens in bind_player() — persistent UI layer,
	# (re)bound per spawn / map change (ADR 0009 Stage B).
	visible = false


## Skinned BBCode tooltip explaining Shadowmeld stealth (matches the ability /
## item tooltip look) instead of Godot's raw-text default.
func _make_custom_tooltip(_for_text: String) -> Object:
	return AbilityTooltip.build(GaugeInfo.shadowmeld())


## Binds this widget to the local player body. Called by LocalPlayerUI.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		visible = false
		return

	shadowmeld_component = player.shadowmeld_component
	equipment_component = player.equipment_component

	# shadowmeld_changed fires on both server and client (via sync_shadowmeld_to_client).
	if is_instance_valid(shadowmeld_component):
		shadowmeld_component.shadowmeld_changed.connect(_on_shadowmeld_changed)

	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh_visibility)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	# Defer the first refresh — equipment slots may not be populated yet at bind.
	call_deferred("_refresh_visibility")
	call_deferred("_refresh_label")


## Drops the binding (teardown). Old-body connections die with the freed body.
func unbind_player() -> void:
	player = null
	shadowmeld_component = null
	equipment_component = null
	visible = false


func _process(_delta: float) -> void:
	# Ticks the cooldown countdown while recharging, then fires one final
	# refresh on the recharging→ready transition so the label flips to "READY"
	# instead of freezing on the last countdown value. Cheap no-op otherwise.
	if not visible or _is_stealthed:
		return
	if not is_instance_valid(shadowmeld_component):
		return
	if not shadowmeld_component.is_ready():
		_refresh_label()
		_was_recharging = true
	elif _was_recharging:
		# Just finished recharging — repaint once to show READY, then stop.
		_was_recharging = false
		_refresh_label()

#endregion


#region #################### Signal handlers ####################

func _on_shadowmeld_changed(stealthed: bool) -> void:
	_is_stealthed = stealthed
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
	visible = player.get_equipped_disciplines().has(Constants.ClassType.DAGGER)
	if visible:
		var is_active: bool = player.get_active_discipline() == Constants.ClassType.DAGGER
		modulate.a = 1.0 if is_active else 0.5
		# Sync to current component state on (re)appearance.
		if is_instance_valid(shadowmeld_component):
			_is_stealthed = shadowmeld_component.is_stealthed()
		_refresh_label()


func _refresh_label() -> void:
	if not is_instance_valid(state_label):
		return
	if _is_stealthed:
		state_label.text = "STEALTHED"
		state_label.add_theme_color_override("font_color", STEALTHED_COLOR)
		return
	if is_instance_valid(shadowmeld_component) and not shadowmeld_component.is_ready():
		var remaining: float = shadowmeld_component.get_cooldown_remaining()
		state_label.text = "%.1fs" % remaining
		state_label.add_theme_color_override("font_color", COOLDOWN_COLOR)
		return
	state_label.text = "READY"
	state_label.add_theme_color_override("font_color", READY_COLOR)

#endregion


#region #################### Animations ####################

func _pulse() -> void:
	# Quick scale pop on the whole widget when stealth toggles.
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.18, 1.18), 0.08).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

#endregion
