class_name ZoneBanner
extends Label

## A brief top-center label that fades in, holds, then fades out — shown when
## the local player enters a new zone. Instantiated and triggered by the player
## controller; reads the zone name from the current map's MapBase.display_name.
## Self-frees after the fade-out tween completes.

const HOLD_DURATION: float = 1.6
const FADE_IN_DURATION: float = 0.45
const FADE_OUT_DURATION: float = 0.7


func _ready() -> void:
	# Anchor: top-wide; banner sits in the upper portion of the screen.
	anchor_left = 0.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 0.0
	offset_top = 40.0
	offset_bottom = 100.0
	horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_font_size_override("font_size", 32)
	add_theme_color_override("font_color", Color(1.0, 0.92, 0.6))
	add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	add_theme_constant_override("outline_size", 4)
	text = ""
	modulate.a = 0.0


## Display the given zone name with a fade-in/hold/fade-out animation, then
## free this node. Safe to call before or right after _ready().
func show_zone(zone_name: String) -> void:
	if zone_name.is_empty():
		queue_free()
		return
	text = zone_name
	var tween := create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN_DURATION)
	tween.tween_interval(HOLD_DURATION)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_DURATION)
	tween.tween_callback(queue_free)
