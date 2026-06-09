extends Node

## Global UI feel layer (autoload "UiFx"). Hooks SceneTree.node_added so EVERY
## BaseButton in the game gets a click sound, a hover tick, and a small
## press-in / spring-back scale tween — and every "ui_window" Control gets
## open/close whooshes — with zero per-scene wiring.
##
## Opt out per node with `set_meta("no_ui_fx", true)` (or the Editor's
## metadata panel) for buttons that manage their own feel (e.g. hotbar slots
## with drag handling).
##
## All effects are local-only cosmetics: no RPCs, no server involvement.

const CLICK_SFX := "res://assets/sounds/generated/ui_click.wav"
const HOVER_SFX := "res://assets/sounds/generated/ui_hover.wav"
const OPEN_SFX := "res://assets/sounds/generated/ui_open.wav"
const CLOSE_SFX := "res://assets/sounds/generated/ui_close.wav"

## Window open/close signals that fire within this window of the node entering
## the tree are setup noise (scenes hiding their windows on boot), not the
## player toggling UI — ignore them.
const SETTLE_MS := 400

const PRESS_SCALE := Vector2(0.94, 0.94)
const HOVER_SCALE := Vector2(1.04, 1.04)


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)


func _on_node_added(node: Node) -> void:
	# Defer so the node's _ready has run — group membership (ui_window) is
	# often added there, and Control sizes have resolved.
	_setup_node.call_deferred(node)


func _setup_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node.has_meta("no_ui_fx"):
		return

	if node is BaseButton:
		node.pressed.connect(_on_button_pressed.bind(node))
		node.button_down.connect(_on_button_down.bind(node))
		node.button_up.connect(_on_button_up.bind(node))
		node.mouse_entered.connect(_on_button_hovered.bind(node))
		node.mouse_exited.connect(_on_button_unhovered.bind(node))
		return

	if node is Control and node.is_in_group("ui_window"):
		node.set_meta("_uifx_added_ms", Time.get_ticks_msec())
		node.visibility_changed.connect(_on_window_visibility.bind(node))


# -- Buttons -----------------------------------------------------------------

func _on_button_pressed(_btn: BaseButton) -> void:
	AudioManager.play_ui_sfx(CLICK_SFX)


func _on_button_down(btn: BaseButton) -> void:
	_scale_to(btn, PRESS_SCALE, 0.06, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_button_up(btn: BaseButton) -> void:
	# Spring back with a touch of overshoot — the "wiggle".
	_scale_to(btn, Vector2.ONE, 0.22, Tween.TRANS_BACK, Tween.EASE_OUT)


func _on_button_hovered(btn: BaseButton) -> void:
	if btn.disabled:
		return
	AudioManager.play_ui_sfx(HOVER_SFX, -8.0)
	_scale_to(btn, HOVER_SCALE, 0.10, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _on_button_unhovered(btn: BaseButton) -> void:
	_scale_to(btn, Vector2.ONE, 0.12, Tween.TRANS_QUAD, Tween.EASE_OUT)


func _scale_to(btn: BaseButton, target: Vector2, dur: float,
		trans: Tween.TransitionType, ease_type: Tween.EaseType) -> void:
	if not is_instance_valid(btn) or not btn.is_inside_tree():
		return
	# Scale around the center, not the top-left corner.
	btn.pivot_offset = btn.size * 0.5
	if btn.has_meta("_uifx_tween"):
		var prev: Tween = btn.get_meta("_uifx_tween")
		if prev is Tween and prev.is_valid():
			prev.kill()
	var tw := btn.create_tween()
	tw.tween_property(btn, "scale", target, dur).set_trans(trans).set_ease(ease_type)
	btn.set_meta("_uifx_tween", tw)


# -- Windows -----------------------------------------------------------------

func _on_window_visibility(window: Control) -> void:
	if not is_instance_valid(window) or not window.is_inside_tree():
		return
	var added: int = window.get_meta("_uifx_added_ms", 0)
	if Time.get_ticks_msec() - added < SETTLE_MS:
		return
	if window.visible:
		AudioManager.play_ui_sfx(OPEN_SFX, -4.0)
	else:
		AudioManager.play_ui_sfx(CLOSE_SFX, -6.0)
