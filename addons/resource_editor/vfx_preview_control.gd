@tool
class_name VfxPreviewControl
extends VBoxContainer

## Inline live preview for a VfxEffectData, shown at the top of its sub-inspector
## (via WeaponContentInspector). Animates the effect from its sheet/fps/scale/tint
## against a faint character reference. Left-drag sets vfx.offset (world px, what
## spawns in game), middle-drag pans, wheel zooms. Ported from the legacy dock.

const GAME_PLAYER_SCALE := 1.3
const GAME_PLAYER_OFFSET_Y := -12.0
const VIS_CAST_BODY_OFFSET := Vector2(0, -18)
const FEET_MARGIN := 30.0
const DEFAULT_ZOOM := 3.5
const MIN_ZOOM := 0.5
const MAX_ZOOM := 16.0

var _vfx: Resource
var _stage: Control
var _sprite: AnimatedSprite2D
var _char: Sprite2D
var _info: Label
var _zoom_label: Label
var _zoom := DEFAULT_ZOOM
var _pan := Vector2.ZERO
var _anchor_screen := Vector2.ZERO
var _dragging := false
var _panning := false


func _init() -> void:
	add_theme_constant_override("separation", 4)

	_stage = Control.new()
	_stage.custom_minimum_size = Vector2(0, 420)
	_stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage.clip_contents = true
	_stage.mouse_filter = Control.MOUSE_FILTER_STOP
	_stage.tooltip_text = "Left-drag: set offset • Middle-drag: pan • Wheel: zoom.\nCrosshair = offset (0,0); line = floor."
	_stage.gui_input.connect(_on_stage_input)
	_stage.draw.connect(_on_stage_draw)
	_stage.resized.connect(func(): _stage.queue_redraw(); _refresh())
	add_child(_stage)

	_char = Sprite2D.new()
	_char.modulate = Color(1, 1, 1, 0.4)
	var portrait = load("res://assets/UI/beginner_portrait.tres")
	if portrait:
		_char.texture = portrait
	_stage.add_child(_char)

	_sprite = AnimatedSprite2D.new()
	_stage.add_child(_sprite)

	var zrow := HBoxContainer.new()
	zrow.alignment = BoxContainer.ALIGNMENT_CENTER
	zrow.add_theme_constant_override("separation", 6)
	var zout := Button.new(); zout.text = " − "
	zout.pressed.connect(func(): _set_zoom(_zoom / 1.25))
	zrow.add_child(zout)
	_zoom_label = Label.new()
	_zoom_label.custom_minimum_size = Vector2(50, 0)
	_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_zoom_label.text = "%.1f×" % _zoom
	zrow.add_child(_zoom_label)
	var zin := Button.new(); zin.text = " + "
	zin.pressed.connect(func(): _set_zoom(_zoom * 1.25))
	zrow.add_child(zin)
	var zreset := Button.new(); zreset.text = " Reset "
	zreset.pressed.connect(_reset_view)
	zrow.add_child(zreset)
	add_child(zrow)

	_info = Label.new()
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_info.add_theme_font_size_override("font_size", 11)
	_info.modulate = Color(1, 1, 1, 0.7)
	add_child(_info)


func set_vfx(vfx: Resource) -> void:
	_vfx = vfx
	if vfx and not vfx.changed.is_connected(_on_vfx_changed):
		vfx.changed.connect(_on_vfx_changed)
	_refresh()


func _on_vfx_changed() -> void:
	VfxCatalog.invalidate()  # drop runtime cache so saved edits reload in-game
	_refresh()


func _refresh() -> void:
	if not is_instance_valid(_sprite) or _vfx == null:
		return
	var sf: SpriteFrames = VfxCatalog.build_frames_from_resource(_vfx)
	if sf == null:
		_sprite.sprite_frames = null
		_info.text = "(no sheet assigned)"
		return
	sf.set_animation_loop("play", true)
	_sprite.sprite_frames = sf
	_sprite.animation = "play"
	_sprite.modulate = _vfx.modulate

	var z := _zoom
	var feet := _feet()
	var aoff := _anchor_world(_vfx)
	var off: Vector2 = _vfx.offset if _vfx.offset is Vector2 else Vector2.ZERO
	_anchor_screen = feet + aoff * z

	if is_instance_valid(_char) and _char.texture != null:
		_char.scale = Vector2.ONE * GAME_PLAYER_SCALE * z
		_char.position = feet + Vector2(0, (GAME_PLAYER_OFFSET_Y * z) / GAME_PLAYER_SCALE)

	_sprite.scale = Vector2.ONE * maxf(0.05, _vfx.scale) * z
	_sprite.position = feet + (aoff + off) * z
	_sprite.play("play")
	if is_instance_valid(_stage):
		_stage.queue_redraw()

	var n := sf.get_frame_count("play")
	var faces: bool = _vfx.face_direction if _vfx.face_direction is bool else true
	_info.text = "%s • %d frames @ %.0f fps • %s • offset (%.0f, %.0f) • %s" % [
		_vfx.effect_key if _vfx.effect_key != "" else "(no key)",
		n, _vfx.fps, "loop" if _vfx.loop else "one-shot",
		off.x, off.y, "faces dir" if faces else "no flip"]


func _feet() -> Vector2:
	var sw: float = _stage.size.x if is_instance_valid(_stage) else 240.0
	var sh: float = _stage.size.y if is_instance_valid(_stage) else 190.0
	return Vector2(sw * 0.5, sh - FEET_MARGIN) + _pan


func _anchor_world(vfx: Resource) -> Vector2:
	if vfx != null and vfx.get("category") == "ground":
		return Vector2.ZERO
	return VIS_CAST_BODY_OFFSET


func _on_stage_draw() -> void:
	var fy: float = _stage.size.y - FEET_MARGIN
	_stage.draw_line(Vector2(0, fy), Vector2(_stage.size.x, fy), Color(0.4, 0.45, 0.5, 0.4), 1.0)
	var a := _anchor_screen
	var mc := Color(0.5, 0.6, 0.75, 0.7)
	_stage.draw_line(a - Vector2(8, 0), a + Vector2(8, 0), mc, 1.0)
	_stage.draw_line(a - Vector2(0, 8), a + Vector2(0, 8), mc, 1.0)
	_stage.draw_circle(a, 2.0, mc)


func _on_stage_input(event: InputEvent) -> void:
	if _vfx == null:
		return
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_dragging = true
					_set_offset_from_pos(mb.position)
				elif _dragging:
					_dragging = false
					_vfx.emit_changed()
				return
			MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
				return
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.15)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / 1.15)
				return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _dragging:
			_set_offset_from_pos(mm.position)
		elif _panning:
			_pan += mm.relative
			_refresh()


func _set_offset_from_pos(local_pos: Vector2) -> void:
	var z := _zoom
	var feet := _feet()
	var aoff := _anchor_world(_vfx)
	_vfx.offset = (((local_pos - feet) / z) - aoff).round()
	_refresh()


func _zoom_at(pivot: Vector2, factor: float) -> void:
	var old_z := _zoom
	var new_z := clampf(old_z * factor, MIN_ZOOM, MAX_ZOOM)
	if is_equal_approx(new_z, old_z):
		return
	var feet := _feet()
	var world := (pivot - feet) / old_z
	var new_feet := pivot - world * new_z
	_pan += (new_feet - feet)
	_zoom = new_z
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "%.1f×" % _zoom
	_refresh()


func _set_zoom(value: float) -> void:
	if is_instance_valid(_stage):
		_zoom_at(_stage.size * 0.5, value / maxf(0.01, _zoom))


func _reset_view() -> void:
	_zoom = DEFAULT_ZOOM
	_pan = Vector2.ZERO
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "%.1f×" % _zoom
	_refresh()
