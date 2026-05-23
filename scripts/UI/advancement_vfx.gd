class_name AdvancementVFX
extends Control

## Job-advancement transition VFX. Played on the LOCAL CLIENT of the advancing
## player only (the server broadcasts a server-wide chat announcement
## separately for everyone else).
##
## Two synchronized animations:
##  * Screen flash — a warm-gold full-screen ColorRect that punches in fast
##    and fades out slowly, like a burst of inspiration.
##  * Banner — "JOB ADVANCEMENT" / "<CLASS NAME>" centered, fades in with the
##    flash, holds, fades out.
##
## Self-frees when the tween completes. The QuestManager-style RPC pattern
## (server → client → spawn this in player_HUD) is used by JobAdvancementManager.

const FLASH_FADE_IN: float = 0.18
const FLASH_FADE_OUT: float = 0.6
const BANNER_FADE_IN: float = 0.45
const BANNER_HOLD: float = 1.7
const BANNER_FADE_OUT: float = 0.7

const FLASH_COLOR: Color = Color(1.0, 0.95, 0.7, 0.0)
const FLASH_PEAK_ALPHA: float = 0.65

var _class_text: String = ""


## Pass the new class display name (e.g. "Crusader") before adding to the tree.
func setup(class_text: String) -> void:
	_class_text = class_text


func _ready() -> void:
	# Cover the full HUD; consume no clicks.
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = 0.0
	offset_top = 0.0
	offset_right = 0.0
	offset_bottom = 0.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS

	_play()


func _play() -> void:
	# --- Screen flash ---
	var flash := ColorRect.new()
	flash.color = FLASH_COLOR
	flash.anchor_left = 0.0
	flash.anchor_top = 0.0
	flash.anchor_right = 1.0
	flash.anchor_bottom = 1.0
	flash.offset_left = 0.0
	flash.offset_top = 0.0
	flash.offset_right = 0.0
	flash.offset_bottom = 0.0
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(flash)

	var flash_tween := create_tween()
	flash_tween.set_trans(Tween.TRANS_SINE)
	flash_tween.tween_property(flash, "color:a", FLASH_PEAK_ALPHA, FLASH_FADE_IN)
	flash_tween.tween_property(flash, "color:a", 0.0, FLASH_FADE_OUT)
	flash_tween.tween_callback(flash.queue_free)

	# --- Centered banner ---
	# CenterContainer keeps the banner glued to the geometric middle of the
	# overlay, even if the HUD resizes mid-animation.
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

	var vbox := VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_theme_constant_override("separation", 6)
	vbox.modulate.a = 0.0
	center.add_child(vbox)

	var title := Label.new()
	title.text = "JOB ADVANCEMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	title.add_theme_constant_override("outline_size", 6)
	title.add_theme_font_size_override("font_size", 30)
	vbox.add_child(title)

	var class_label := Label.new()
	class_label.text = _class_text.to_upper()
	class_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	class_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.25))
	class_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.95))
	class_label.add_theme_constant_override("outline_size", 8)
	class_label.add_theme_font_size_override("font_size", 58)
	vbox.add_child(class_label)

	var banner_tween := create_tween()
	banner_tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	banner_tween.tween_property(vbox, "modulate:a", 1.0, BANNER_FADE_IN)
	banner_tween.tween_interval(BANNER_HOLD)
	banner_tween.tween_property(vbox, "modulate:a", 0.0, BANNER_FADE_OUT)
	banner_tween.tween_callback(queue_free)
