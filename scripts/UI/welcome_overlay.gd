class_name WelcomeOverlay
extends Control

## First-login onboarding overlay. Shown ONCE to brand-new characters when
## QuestManager.start_onboarding fires. Lists the controls, the four
## most-likely-to-be-missed keybinds (Q quest log, K abilities, right-click
## NPC, portals), and a single dismiss button. Input is locked while the
## overlay is up so the player actually reads it instead of fumbling around.
##
## Self-frees on dismiss. The QuestManager `_onboarded` flag guarantees the
## RPC that spawns this overlay only fires once per character.
##
## Layout note: anchors are set explicitly (not via `set_anchors_preset`)
## because the preset variant leaves offsets at (0, 0) — which on a freshly
## created Control collapses the whole overlay to a zero-size rect at the
## parent's top-left, and any "centered" children inside end up pinned to
## the corner. The CenterContainer below additionally guarantees the card
## stays centered as the HUD resizes.

const THEME_PATH: String = "res://assets/themes/UI_Theme.tres"
const GOLD: Color = Color(1.0, 0.85, 0.35)
const KEY_COLOR: Color = Color(0.55, 0.85, 1.0)

var _input_was_locked: bool = false


func _ready() -> void:
	# Cover the whole HUD. Explicit anchors + zero offsets so the root fills
	# the parent regardless of when the parent's size resolves.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS

	_lock_input()
	_build_ui()


func _exit_tree() -> void:
	_unlock_input()


func _lock_input() -> void:
	if InputManager:
		_input_was_locked = InputManager.is_locked()
		if not _input_was_locked:
			InputManager.set_input_locked(true)


func _unlock_input() -> void:
	# Only unlock if we were the ones who locked it.
	if InputManager and not _input_was_locked:
		InputManager.set_input_locked(false)


func _build_ui() -> void:
	# Backdrop — full-rect dim layer behind the card.
	var backdrop := ColorRect.new()
	backdrop.color = Color(0, 0, 0, 0.55)
	backdrop.anchor_left = 0.0
	backdrop.anchor_top = 0.0
	backdrop.anchor_right = 1.0
	backdrop.anchor_bottom = 1.0
	backdrop.offset_left = 0.0
	backdrop.offset_top = 0.0
	backdrop.offset_right = 0.0
	backdrop.offset_bottom = 0.0
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	# CenterContainer fills the overlay and centers its single child (the
	# card) at the geometric middle of whatever the overlay's rect resolves
	# to. This is robust against parent-resize timing.
	var center := CenterContainer.new()
	center.anchor_left = 0.0
	center.anchor_top = 0.0
	center.anchor_right = 1.0
	center.anchor_bottom = 1.0
	center.offset_left = 0.0
	center.offset_top = 0.0
	center.offset_right = 0.0
	center.offset_bottom = 0.0
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	# The card itself.
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(560, 420)
	card.mouse_filter = Control.MOUSE_FILTER_STOP

	var ui_theme: Theme = load(THEME_PATH)
	if ui_theme:
		card.theme = ui_theme

	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.08, 0.09, 0.12, 0.97)
	bg.border_color = Color(0.55, 0.45, 0.2, 1.0)
	bg.set_border_width_all(2)
	bg.set_corner_radius_all(4)
	bg.content_margin_left = 24.0
	bg.content_margin_right = 24.0
	bg.content_margin_top = 20.0
	bg.content_margin_bottom = 20.0
	card.add_theme_stylebox_override("panel", bg)

	center.add_child(card)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	card.add_child(col)

	# Title.
	var title := Label.new()
	title.text = "Welcome, Adventurer!"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", GOLD)
	title.add_theme_font_size_override("font_size", 22)
	col.add_child(title)

	var intro := Label.new()
	intro.text = "You've arrived in Maple Town. Here's how to get started:"
	intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 13)
	col.add_child(intro)

	col.add_child(_make_separator())

	# Movement / combat controls — two-column grid.
	var controls_header := Label.new()
	controls_header.text = "Controls"
	controls_header.add_theme_color_override("font_color", GOLD)
	controls_header.add_theme_font_size_override("font_size", 15)
	col.add_child(controls_header)

	var controls := GridContainer.new()
	controls.columns = 2
	controls.add_theme_constant_override("h_separation", 30)
	controls.add_theme_constant_override("v_separation", 4)
	col.add_child(controls)

	_add_control_row(controls, "Move", "A / D  or  Arrow Keys")
	_add_control_row(controls, "Jump", "Space")
	_add_control_row(controls, "Attack", "Ctrl")
	_add_control_row(controls, "Pick up item", "Z")
	_add_control_row(controls, "Drop through platform", "Down  +  Space")

	col.add_child(_make_separator())

	# Highlighted tips.
	var tips_header := Label.new()
	tips_header.text = "Don't miss"
	tips_header.add_theme_color_override("font_color", GOLD)
	tips_header.add_theme_font_size_override("font_size", 15)
	col.add_child(tips_header)

	_add_tip(col, "Q", "Open your Quest Log — your first quest is already accepted")
	_add_tip(col, "K", "Open the Abilities window once you have skill points")
	_add_tip(col, "Right-click", "Talk to NPCs (the merchant, the Job Master)")
	_add_tip(col, "Portal", "Step into the glowing portal and press the interact key to travel")

	col.add_child(_make_separator())

	# Dismiss.
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(btn_row)

	var got_it := Button.new()
	got_it.text = "Got it!"
	got_it.custom_minimum_size = Vector2(160, 36)
	got_it.pressed.connect(_dismiss)
	btn_row.add_child(got_it)
	got_it.grab_focus.call_deferred()


func _add_control_row(grid: GridContainer, action: String, keys: String) -> void:
	var a := Label.new()
	a.text = action
	a.add_theme_font_size_override("font_size", 13)
	a.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	grid.add_child(a)

	var k := Label.new()
	k.text = keys
	k.add_theme_font_size_override("font_size", 13)
	k.add_theme_color_override("font_color", KEY_COLOR)
	grid.add_child(k)


func _add_tip(parent: VBoxContainer, key: String, text: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	var key_label := Label.new()
	key_label.text = "[%s]" % key
	key_label.add_theme_color_override("font_color", KEY_COLOR)
	key_label.add_theme_font_size_override("font_size", 13)
	key_label.custom_minimum_size = Vector2(110, 0)
	row.add_child(key_label)

	var text_label := Label.new()
	text_label.text = text
	text_label.add_theme_font_size_override("font_size", 13)
	text_label.add_theme_color_override("font_color", Color(0.92, 0.92, 0.92))
	text_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text_label)

	parent.add_child(row)


func _make_separator() -> Control:
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 1)
	return sep


func _input(event: InputEvent) -> void:
	# Esc dismisses too. We don't bind to ui_accept because that's Space, which
	# would conflict with the player's jump input when they read the overlay.
	if event.is_action_pressed("ui_cancel"):
		accept_event()
		_dismiss()


func _dismiss() -> void:
	queue_free()
