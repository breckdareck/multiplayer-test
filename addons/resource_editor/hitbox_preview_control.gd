@tool
class_name HitboxPreviewControl
extends Control

## Inline hitbox preview for an ActiveBehaviorData, shown at the top of its
## sub-inspector (via WeaponContentInspector). Draws a faint player reference at
## game scale, the origin crosshair, and the hit_box shape (circle / rect /
## capsule) at hit_box_position_data — so you can judge reach + placement while
## editing in the native Inspector.

const GAME_PLAYER_SCALE := 1.3
const GAME_PLAYER_OFFSET_Y := -12.0
const ZOOM := 6.0

var _behavior: Resource
var _sprite: Sprite2D


func _init() -> void:
	custom_minimum_size = Vector2(0, 280)
	clip_contents = true
	_sprite = Sprite2D.new()
	_sprite.modulate = Color(1, 1, 1, 0.45)
	var portrait = load("res://assets/UI/beginner_portrait.tres")
	if portrait:
		_sprite.texture = portrait
	add_child(_sprite)
	resized.connect(_reposition)


func set_behavior(behavior: Resource) -> void:
	_behavior = behavior
	if behavior and not behavior.changed.is_connected(queue_redraw):
		behavior.changed.connect(queue_redraw)
	_reposition()
	queue_redraw()


func _reposition() -> void:
	if not is_instance_valid(_sprite) or _sprite.texture == null:
		return
	_sprite.scale = Vector2.ONE * GAME_PLAYER_SCALE * ZOOM
	var center := size / 2
	_sprite.position = center + Vector2(0, (GAME_PLAYER_OFFSET_Y * ZOOM) / GAME_PLAYER_SCALE)


func _draw() -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.10, 0.11, 0.13)
	bg.border_color = Color(0.30, 0.32, 0.38)
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	draw_style_box(bg, Rect2(Vector2.ZERO, size))

	var center := size / 2
	draw_line(center - Vector2(10, 0), center + Vector2(10, 0), Color.RED, 2)
	draw_line(center - Vector2(0, 10), center + Vector2(0, 10), Color.RED, 2)

	if _behavior == null or _behavior.get("hit_box_shape_data") == null:
		return
	var shape = _behavior.hit_box_shape_data
	var pos_offset: Vector2 = _behavior.hit_box_position_data * ZOOM
	var draw_pos := center + pos_offset
	var label := ""
	var label_anchor := draw_pos

	if shape is CircleShape2D:
		var r: float = shape.radius * ZOOM
		draw_circle(draw_pos, r, Color(0, 1, 0, 0.5))
		draw_arc(draw_pos, r, 0, TAU, 32, Color.GREEN, 2)
		label = "r = %.0f" % shape.radius
		label_anchor = draw_pos + Vector2(-r, -r - 6)
	elif shape is RectangleShape2D:
		var s: Vector2 = shape.size * ZOOM
		var rect := Rect2(draw_pos - s / 2, s)
		draw_rect(rect, Color(0, 1, 0, 0.5))
		draw_rect(rect, Color.GREEN, false, 2)
		label = "%.0f × %.0f" % [shape.size.x, shape.size.y]
		label_anchor = rect.position + Vector2(0, -6)
	elif shape is CapsuleShape2D:
		var h: float = shape.height * ZOOM
		var r2: float = shape.radius * ZOOM
		var rect := Rect2(draw_pos - Vector2(r2, h / 2), Vector2(r2 * 2, h))
		draw_rect(rect, Color(0, 1, 0, 0.5))
		draw_rect(rect, Color.GREEN, false, 2)
		label = "r = %.0f · h = %.0f" % [shape.radius, shape.height]
		label_anchor = rect.position + Vector2(0, -6)

	if not label.is_empty():
		var font := ThemeDB.fallback_font
		if font:
			var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11)
			draw_rect(Rect2(label_anchor - Vector2(4, ts.y + 2), Vector2(ts.x + 8, ts.y + 4)), Color(0, 0, 0, 0.55), true)
			draw_string(font, label_anchor - Vector2(0, 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.GREEN)
