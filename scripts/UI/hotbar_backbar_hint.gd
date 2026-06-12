extends PanelContainer
class_name HotbarBackbarHint

## ESO-style back-bar cooldown hint: a mini ability icon with a countdown that
## pops up above a hotbar slot while the INACTIVE weapon's ability bound to
## that slot index is still cooling down — a glanceable "when will it be back
## up" for the bar you're about to swap to. The Hotbar builds one per slot,
## feeds it every frame from the AbilityComponent's authoritative cooldowns,
## and positions it above the slot (so it follows the bar-swap flip).
##
## Children are code-built: the widget is tiny and never authored in-scene.

const FONT: FontFile = preload("res://assets/fonts/PixelOperator8.ttf")
const ICON_SIZE := 24
const POP_DURATION := 0.12
const READY_FADE_DURATION := 0.35
const NOT_READY_DIM := Color(0.75, 0.75, 0.75, 1.0)

var _icon: TextureRect
var _label: Label
var _ability_id: String = ""
var _fading: bool = false
var _tween: Tween = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.105, 0.078, 0.058, 0.92)
	style.border_color = Color(0.78, 0.53, 0.22, 0.9)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2)
	style.set_content_margin_all(2.0)
	add_theme_stylebox_override("panel", style)

	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.self_modulate = NOT_READY_DIM
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_icon)

	# Overlaid on the icon (PanelContainer fits all children to the same rect),
	# hugging the bottom edge like the slot cooldown label.
	_label = Label.new()
	_label.add_theme_font_override("font", FONT)
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(1, 1, 0.3, 1))
	_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


## Called every frame while the back-bar ability at this slot index is on
## cooldown. Pops the widget in on the first call (or when the bound ability
## changed under it, e.g. a swap mid-fade).
func update_hint(ability_id: String, icon: Texture2D, remaining: float) -> void:
	_label.text = ("%.1f" % remaining) if remaining < 10.0 else str(int(ceilf(remaining)))
	if ability_id != _ability_id or not visible or _fading:
		_ability_id = ability_id
		_icon.texture = icon
		_pop_in()


## Called every frame while there is NO cooldown for this slot's back-bar
## entry. `bound_ability_id` is whatever is bound there now ("" when empty):
## if it's still the ability we were tracking, the cooldown finished naturally
## — flash "ready" and fade out. Otherwise the binding changed; hide instantly.
func clear_hint(bound_ability_id: String) -> void:
	if not visible or _fading:
		return
	if bound_ability_id != "" and bound_ability_id == _ability_id:
		_ready_fade()
	else:
		force_hide()


func force_hide() -> void:
	_kill_tween()
	_fading = false
	visible = false
	_ability_id = ""
	_icon.self_modulate = NOT_READY_DIM
	modulate = Color.WHITE
	scale = Vector2.ONE


func _pop_in() -> void:
	_kill_tween()
	_fading = false
	visible = true
	_icon.self_modulate = NOT_READY_DIM
	modulate = Color(1, 1, 1, 0)
	reset_size()
	# Grow up out of the bar: pivot at the bottom-center edge.
	pivot_offset = Vector2(size.x * 0.5, size.y)
	scale = Vector2(0.6, 0.6)
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(self, "modulate:a", 1.0, POP_DURATION)
	_tween.tween_property(self, "scale", Vector2.ONE, POP_DURATION) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## The tracked cooldown just finished: brighten to full color ("it's ready"),
## then fade away.
func _ready_fade() -> void:
	_kill_tween()
	_fading = true
	_icon.self_modulate = Color.WHITE
	_label.text = ""
	_tween = create_tween()
	_tween.tween_property(self, "modulate", Color(1.6, 1.6, 1.2, 1.0), 0.08)
	_tween.tween_property(self, "modulate:a", 0.0, READY_FADE_DURATION)
	_tween.tween_callback(force_hide)


func _kill_tween() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = null
