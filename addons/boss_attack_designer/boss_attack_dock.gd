@tool
extends Control
##
## Boss Attack Designer dock. Loads a boss's EnemyData, lists its special attacks
## (BossAttackData via EnemyData.get_special_attacks()), draws the boss sprite at
## scale, and overlays the chosen attack's telegraph SHAPE + DASH using the EXACT
## runtime geometry from enemy_base._point_in_attack / enemy_boss_special.gd.
## "What you see = what the attack does."
##
## Editor tooling only (@tool). No game launch, no networking, no mutation of the
## resources — it only READS EnemyData / BossAttackData and renders them.
##
## Geometry contract (mirrors enemy_base.gd, with origin in place of the boss's
## global_position and dir = +1 right / -1 left):
##   - CIRCLE: hit radius = reach, centered on ORIGIN.
##   - RECT:   AABB of size (reach, band_height) centered on
##             ORIGIN + Vector2(dir * reach * forward_offset_frac, 0).
##   - CONE:   fan from ORIGIN toward dir, total angle = cone_angle_deg,
##             length = reach (the hit-test uses a radial length cap, so we draw a
##             rounded/arc cap to match).
##   - DASH:   dist = dash_distance if > 0 else reach; boss ends at
##             ORIGIN + Vector2(dir * dist, 0).
## Timing (mirrors enemy_boss_special.gd):
##   - T = hit_time + (dash_time if movement == DASH else 0).
##   - WINDUP [0, hit_time): telegraph alpha 0->1, red tint white->Color(1,.35,.3),
##     animation by anim_mode (STRETCH/HOLD/FREE). Boss at origin.
##   - At hit_time: bright flash of the shape.
##   - DASH [hit_time, T): boss slides origin -> origin + dir*dist.

const _WINDUP_ANIMS: Array[String] = ["dash_attack", "slash_attack", "bomb_attack", "attack", "idle"]
const _ConstantsScript := preload("res://scripts/Core/Enums/constants.gd")

var _editor_interface: EditorInterface = null

# --- State ---
var _enemy_data: EnemyData = null
var _attacks: Array[BossAttackData] = []
var _is_legacy_synth: bool = false
var _selected_attack: BossAttackData = null
var _connected_attack: BossAttackData = null  # the one whose `changed` we're listening to

# --- UI refs ---
var _resource_picker: EditorResourcePicker = null
var _attack_dropdown: OptionButton = null
var _refresh_btn: Button = null
var _face_left_check: CheckBox = null
var _preview: Control = null
var _play_btn: Button = null
var _scrub: HSlider = null
var _time_label: Label = null
var _info_label: RichTextLabel = null

# --- Playback state (owned by the dock, read by the preview) ---
var _playing: bool = false
var _time: float = 0.0          # seconds into the timeline
var _scrubbing: bool = false    # user is dragging the slider; don't fight it


func _ready() -> void:
	_build_ui()
	set_process(true)


func set_editor_interface(ed: EditorInterface) -> void:
	_editor_interface = ed


# --- UI construction --------------------------------------------------------

func _build_ui() -> void:
	custom_minimum_size = Vector2(360, 520)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	vb.add_theme_constant_override("separation", 4)
	add_child(vb)

	# Header.
	var header := Label.new()
	header.text = "Boss Attack Designer"
	header.add_theme_font_size_override("font_size", 15)
	header.add_theme_color_override("font_color", Color(0.95, 0.8, 0.45))
	vb.add_child(header)

	# Row: EnemyData picker + Refresh.
	var pick_row := HBoxContainer.new()
	pick_row.add_theme_constant_override("separation", 4)
	vb.add_child(pick_row)

	var pick_lab := Label.new()
	pick_lab.text = "Boss:"
	pick_row.add_child(pick_lab)

	_resource_picker = EditorResourcePicker.new()
	_resource_picker.base_type = "EnemyData"
	_resource_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_resource_picker.resource_changed.connect(_on_enemy_data_changed)
	pick_row.add_child(_resource_picker)

	_refresh_btn = Button.new()
	_refresh_btn.text = "Refresh"
	_refresh_btn.pressed.connect(_on_refresh)
	pick_row.add_child(_refresh_btn)

	# Row: attack dropdown + Face left.
	var attack_row := HBoxContainer.new()
	attack_row.add_theme_constant_override("separation", 4)
	vb.add_child(attack_row)

	var atk_lab := Label.new()
	atk_lab.text = "Attack:"
	attack_row.add_child(atk_lab)

	_attack_dropdown = OptionButton.new()
	_attack_dropdown.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_attack_dropdown.item_selected.connect(_on_attack_selected)
	attack_row.add_child(_attack_dropdown)

	_face_left_check = CheckBox.new()
	_face_left_check.text = "Face left"
	_face_left_check.toggled.connect(func(_p): _redraw_preview())
	attack_row.add_child(_face_left_check)

	# Preview control (expands to fill).
	_preview = _PreviewControl.new()
	(_preview as _PreviewControl).dock = self
	_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(0, 240)
	_preview.clip_contents = true
	vb.add_child(_preview)

	# Play row: play/pause + scrub + time readout.
	var play_row := HBoxContainer.new()
	play_row.add_theme_constant_override("separation", 4)
	vb.add_child(play_row)

	_play_btn = Button.new()
	_play_btn.text = "▶ Play"
	_play_btn.custom_minimum_size = Vector2(70, 0)
	_play_btn.pressed.connect(_on_play_pressed)
	play_row.add_child(_play_btn)

	_scrub = HSlider.new()
	_scrub.min_value = 0.0
	_scrub.max_value = 1.0
	_scrub.step = 0.001
	_scrub.value = 0.0
	_scrub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scrub.value_changed.connect(_on_scrub_changed)
	# Track press/release so playback yields to manual scrubbing.
	_scrub.gui_input.connect(_on_scrub_gui_input)
	play_row.add_child(_scrub)

	_time_label = Label.new()
	_time_label.text = "0.00s / 0.00s"
	_time_label.custom_minimum_size = Vector2(110, 0)
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	play_row.add_child(_time_label)

	# Info panel (scrollable so long resolved-number lists don't blow the dock).
	var info_scroll := ScrollContainer.new()
	info_scroll.custom_minimum_size = Vector2(0, 150)
	info_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(info_scroll)

	_info_label = RichTextLabel.new()
	_info_label.bbcode_enabled = true
	_info_label.fit_content = true
	_info_label.scroll_active = false
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.text = "[i]Pick a boss EnemyData above.[/i]"
	info_scroll.add_child(_info_label)


# --- EnemyData / attack selection -------------------------------------------

func _on_enemy_data_changed(res: Resource) -> void:
	_enemy_data = res as EnemyData
	_reload_attacks()


func _on_refresh() -> void:
	# Re-read get_special_attacks() (the user may have added/removed attacks in
	# the inspector) and rebuild the dropdown, then redraw.
	_reload_attacks()


func _reload_attacks() -> void:
	_attacks = []
	_is_legacy_synth = false
	_attack_dropdown.clear()

	if _enemy_data == null:
		_disconnect_attack()
		_selected_attack = null
		_reset_playback()
		_update_info()
		_redraw_preview()
		return

	var list: Array[BossAttackData] = _enemy_data.get_special_attacks()
	# Detect a legacy synth: special_attacks is empty but get_special_attacks()
	# returned one (the synthesised dash-slam from the legacy fields).
	if _enemy_data.special_attacks.is_empty() and not list.is_empty():
		_is_legacy_synth = true

	_attacks = list
	for i in _attacks.size():
		var atk: BossAttackData = _attacks[i]
		var label: String
		if _is_legacy_synth:
			label = "Legacy dash-slam (synth)"
		else:
			var shape_name: String = _shape_name(atk.shape) if atk != null else "?"
			var atk_name: String = atk.attack_name if (atk != null and not atk.attack_name.is_empty()) else "(unnamed)"
			label = "%s  [%s]" % [atk_name, shape_name]
		_attack_dropdown.add_item(label, i)

	if _attacks.is_empty():
		_disconnect_attack()
		_selected_attack = null
		_reset_playback()
		_update_info()
		_redraw_preview()
		return

	_attack_dropdown.select(0)
	_select_attack(0)


func _on_attack_selected(idx: int) -> void:
	_select_attack(idx)


func _select_attack(idx: int) -> void:
	if idx < 0 or idx >= _attacks.size():
		return
	_disconnect_attack()
	_selected_attack = _attacks[idx]
	# Live-update the preview when the user edits this attack in the Inspector.
	if _selected_attack != null:
		_selected_attack.changed.connect(_on_attack_resource_changed)
		_connected_attack = _selected_attack
	_reset_playback()
	_update_info()
	_redraw_preview()


func _on_attack_resource_changed() -> void:
	# A field on the selected BossAttackData changed in the Inspector.
	_update_info()
	_redraw_preview()


func _disconnect_attack() -> void:
	if _connected_attack != null and is_instance_valid(_connected_attack):
		if _connected_attack.changed.is_connected(_on_attack_resource_changed):
			_connected_attack.changed.disconnect(_on_attack_resource_changed)
	_connected_attack = null


# --- Playback ---------------------------------------------------------------

func _on_play_pressed() -> void:
	if _selected_attack == null:
		return
	_playing = not _playing
	if _playing:
		# Restart from the top if we're parked at the end.
		if _time >= _total_time() - 0.0001:
			_time = 0.0
		_play_btn.text = "⏸ Pause"
	else:
		_play_btn.text = "▶ Play"


func _reset_playback() -> void:
	_playing = false
	_time = 0.0
	if _play_btn != null:
		_play_btn.text = "▶ Play"
	if _scrub != null:
		_scrub.set_value_no_signal(0.0)
	_update_time_label()


func _on_scrub_changed(v: float) -> void:
	# Slider value 0..1 -> 0..T. Only honour user-driven changes; programmatic
	# updates during playback use set_value_no_signal to avoid feedback.
	_time = v * _total_time()
	_update_time_label()
	_redraw_preview()


func _on_scrub_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_scrubbing = true
				# Pause while dragging so playback doesn't fight the drag.
				_playing = false
				_play_btn.text = "▶ Play"
			else:
				_scrubbing = false


func _process(delta: float) -> void:
	if not _playing or _scrubbing or _selected_attack == null:
		return
	var t_total: float = _total_time()
	if t_total <= 0.0:
		_playing = false
		_play_btn.text = "▶ Play"
		return
	_time += delta
	if _time >= t_total:
		# Loop.
		_time = fmod(_time, t_total)
	_scrub.set_value_no_signal(clampf(_time / t_total, 0.0, 1.0))
	_update_time_label()
	_redraw_preview()


func _total_time() -> float:
	if _selected_attack == null:
		return 0.0
	var hit: float = maxf(0.0, _selected_attack.hit_time)
	var t: float = hit
	if _selected_attack.movement == BossAttackData.Movement.DASH:
		t += maxf(0.0, _selected_attack.dash_time)
	return maxf(0.0001, t)


func _update_time_label() -> void:
	if _time_label == null:
		return
	_time_label.text = "%.2fs / %.2fs" % [_time, _total_time()]


func _redraw_preview() -> void:
	if _preview != null:
		_preview.queue_redraw()


# --- Resolved-geometry helpers (shared by info panel and preview) -----------

func _dir() -> int:
	return -1 if (_face_left_check != null and _face_left_check.button_pressed) else 1


## Dash distance per the runtime rule: dash_distance if > 0 else reach.
func _dash_dist(atk: BossAttackData) -> float:
	if atk == null:
		return 0.0
	return atk.dash_distance if atk.dash_distance > 0.0 else atk.reach


## Resolves the animation clip the runtime would use for this attack: the
## explicit windup_anim if it exists on the SpriteFrames, else the first of the
## fallback list that exists. Returns "" if none.
func _resolve_anim(atk: BossAttackData) -> String:
	var sf: SpriteFrames = _sprite_frames()
	if atk != null and not atk.windup_anim.is_empty():
		if sf != null and sf.has_animation(atk.windup_anim):
			return atk.windup_anim
		# windup_anim set but missing — fall through to the fallback list.
	if sf == null:
		return ""
	for a in _WINDUP_ANIMS:
		if sf.has_animation(a):
			return a
	# Last resort: any animation that exists.
	var names := sf.get_animation_names()
	return names[0] if names.size() > 0 else ""


func _sprite_frames() -> SpriteFrames:
	return _enemy_data.sprite_frames if _enemy_data != null else null


func _shape_name(shape: int) -> String:
	match shape:
		BossAttackData.Shape.RECT: return "RECT"
		BossAttackData.Shape.CIRCLE: return "CIRCLE"
		BossAttackData.Shape.CONE: return "CONE"
		_: return str(shape)


func _anim_mode_name(mode: int) -> String:
	match mode:
		BossAttackData.AnimMode.STRETCH: return "STRETCH"
		BossAttackData.AnimMode.HOLD: return "HOLD"
		BossAttackData.AnimMode.FREE: return "FREE"
		_: return str(mode)


func _movement_name(mv: int) -> String:
	match mv:
		BossAttackData.Movement.NONE: return "NONE"
		BossAttackData.Movement.DASH: return "DASH"
		_: return str(mv)


# --- Info panel -------------------------------------------------------------

func _update_info() -> void:
	if _info_label == null:
		return
	if _enemy_data == null:
		_info_label.text = "[i]Pick a boss EnemyData above.[/i]"
		return
	if _selected_attack == null:
		var name_part: String = _enemy_data.monster_name if not _enemy_data.monster_name.is_empty() else "(unnamed enemy)"
		_info_label.text = "[b]%s[/b]\n[color=#c88]No special attacks. (is_boss=%s, special_attack_cooldown=%.1f)[/color]" % [
			_bb(name_part), str(_enemy_data.is_boss), _enemy_data.special_attack_cooldown,
		]
		return

	var atk: BossAttackData = _selected_attack
	var dir: int = _dir()
	var lines: PackedStringArray = []

	var boss_name: String = _enemy_data.monster_name if not _enemy_data.monster_name.is_empty() else "(unnamed)"
	lines.append("[b]%s[/b]  —  [color=#fd8]%s[/color]" % [_bb(boss_name), _bb(atk.attack_name)])
	if _is_legacy_synth:
		lines.append("[color=#fa6](synthesised from legacy special_attack_* fields)[/color]")

	# Shape line.
	lines.append("[color=#9fd]shape:[/color] [b]%s[/b]" % _shape_name(atk.shape))
	match atk.shape:
		BossAttackData.Shape.RECT:
			var fwd_off: float = atk.reach * atk.forward_offset_frac
			lines.append("  reach: %.0f px   band_height: %.0f px" % [atk.reach, atk.band_height])
			lines.append("  forward_offset: %.2f  =  %.0f px   (center offset along facing: %.0f px)" % [
				atk.forward_offset_frac, fwd_off, dir * fwd_off,
			])
		BossAttackData.Shape.CIRCLE:
			lines.append("  radius (reach): %.0f px   (centered on boss origin)" % atk.reach)
		BossAttackData.Shape.CONE:
			lines.append("  reach (length): %.0f px   cone_angle: %.0f°  (half: %.0f°)" % [
				atk.reach, atk.cone_angle_deg, atk.cone_angle_deg * 0.5,
			])

	# Movement / dash.
	lines.append("[color=#9fd]movement:[/color] %s" % _movement_name(atk.movement))
	if atk.movement == BossAttackData.Movement.DASH:
		var dist: float = _dash_dist(atk)
		var src: String = "dash_distance" if atk.dash_distance > 0.0 else "reach (dash_distance=0)"
		lines.append("  dash distance: %.0f px  (from %s)   dash_time: %.2fs" % [dist, src, atk.dash_time])

	# Timing.
	lines.append("[color=#9fd]timing:[/color] windup_time %.2fs   hit_time %.2fs   cooldown %.1fs" % [
		atk.windup_time, atk.hit_time, atk.cooldown,
	])
	lines.append("[color=#9fd]total preview timeline:[/color] %.2fs" % _total_time())

	# Animation.
	var resolved_anim: String = _resolve_anim(atk)
	lines.append("[color=#9fd]anim_mode:[/color] %s" % _anim_mode_name(atk.anim_mode))
	var sf: SpriteFrames = _sprite_frames()
	if atk.windup_anim.is_empty():
		lines.append("  windup_anim: (empty) → using fallback clip: [b]%s[/b]" % (resolved_anim if not resolved_anim.is_empty() else "(none)"))
	elif sf != null and sf.has_animation(atk.windup_anim):
		lines.append("  windup_anim: [b]%s[/b]  (exists ✓)" % atk.windup_anim)
	else:
		lines.append("  windup_anim: [color=#fa6][b]%s[/b]  (NOT on SpriteFrames — using %s)[/color]" % [
			atk.windup_anim, (resolved_anim if not resolved_anim.is_empty() else "(none)"),
		])
	if atk.anim_mode == BossAttackData.AnimMode.HOLD:
		lines.append("  hold_frame: %s" % ("last frame (-1)" if atk.hold_frame < 0 else str(atk.hold_frame)))
	if sf == null:
		lines.append("  [color=#fa6]No SpriteFrames on this EnemyData — sprite not drawn.[/color]")

	# Damage / bespoke.
	lines.append("[color=#9fd]damage_mult:[/color] %.2f×" % atk.damage_mult)
	if atk.logic_script != null:
		var lp: String = atk.logic_script.resource_path if not atk.logic_script.resource_path.is_empty() else "(inline)"
		lines.append("[color=#fc6]logic_script:[/color] %s  (bespoke on_hit may override the built-in shape)" % _bb(lp))
	else:
		lines.append("[color=#888]logic_script: none (built-in shape damage)[/color]")

	_info_label.text = "\n".join(lines)


func _bb(text: String) -> String:
	return text.replace("[", "[lb]")


# ===========================================================================
# Inner preview Control. Draws the boss sprite + telegraph shape + dash, and
# animates them according to the dock's playback state. All geometry mirrors
# enemy_base._point_in_attack / enemy_boss_special.gd.
# ===========================================================================
class _PreviewControl extends Control:
	var dock = null  # back-ref to the dock for state (typed as the outer script)

	const SCALE_MIN := 0.15
	const SCALE_MAX := 4.0
	const RULER_STEP := 50.0  # game units between ruler ticks

	const COL_BG := Color(0.10, 0.11, 0.14, 1.0)
	const COL_GROUND := Color(0.45, 0.48, 0.55, 0.9)
	const COL_RULER := Color(0.35, 0.38, 0.45, 0.5)
	const COL_RULER_TEXT := Color(0.6, 0.65, 0.72, 0.9)
	const COL_SHAPE_FILL := Color(1.0, 0.25, 0.22, 0.28)
	const COL_SHAPE_FILL_FLASH := Color(1.0, 0.55, 0.4, 0.6)
	const COL_SHAPE_LINE := Color(1.0, 0.45, 0.4, 0.95)
	const COL_DASH := Color(0.5, 0.8, 1.0, 0.9)
	const COL_GHOST := Color(1.0, 1.0, 1.0, 0.3)
	const COL_LABEL := Color(1.0, 0.85, 0.7, 1.0)

	func _draw() -> void:
		var sz := size
		# Background.
		draw_rect(Rect2(Vector2.ZERO, sz), COL_BG, true)

		if dock == null:
			return
		var atk: BossAttackData = dock._selected_attack
		if atk == null:
			_draw_hint("Select a boss + attack to preview.")
			return

		var dir: int = dock._dir()
		var hit_time: float = maxf(0.0001, atk.hit_time)
		var t: float = dock._time
		var t_total: float = dock._total_time()

		# --- Resolve fit scale + origin in screen space -----------------------
		# Forward extent (game-units) to fit ahead of the origin.
		var fwd_extent: float = _forward_extent(atk)
		# Behind extent (game-units) to keep behind the origin so the sprite +
		# any negative-offset RECT is visible.
		var behind_extent: float = _behind_extent(atk)
		# Vertical half-extent (game-units) so tall bands / circles aren't clipped.
		var vert_half: float = _vertical_half_extent(atk)

		var pad := 24.0
		var sprite_w_units: float = _sprite_width_units()
		# Horizontal budget: behind + sprite-half + forward, both sides padded.
		var total_h_units: float = behind_extent + fwd_extent + sprite_w_units
		var avail_w: float = maxf(1.0, sz.x - pad * 2.0)
		var avail_h: float = maxf(1.0, sz.y - pad * 2.0)
		var scale_x: float = avail_w / maxf(1.0, total_h_units)
		# Vertical budget: 2*vert_half (shape) or sprite height, whichever is taller.
		var sprite_h_units: float = _sprite_height_units()
		var total_v_units: float = maxf(vert_half * 2.0, sprite_h_units) + 20.0
		var scale_y: float = avail_h / maxf(1.0, total_v_units)
		var scl: float = clampf(minf(scale_x, scale_y), SCALE_MIN, SCALE_MAX)

		# Ground line y: a bit below vertical centre so the upward sprite + shape
		# fit. Place origin so behind/forward are balanced into the avail width.
		var ground_y: float = sz.y * 0.62
		# Origin x: leave `behind_extent`*scl + sprite_half to the left.
		var left_room: float = (behind_extent + sprite_w_units * 0.5) * scl
		var origin_x: float = clampf(pad + left_room, pad, sz.x - pad)
		var origin := Vector2(origin_x, ground_y)

		# --- Ruler + ground ---------------------------------------------------
		_draw_ground_and_ruler(origin, scl, sz)

		# --- Compute current animation frame + boss screen pos ----------------
		var anim: String = dock._resolve_anim(atk)
		var frame_idx: int = _current_frame(atk, anim, t, hit_time)

		# Boss world x-offset (0 during windup; slides during dash).
		var boss_dx_units: float = 0.0
		var dashing: bool = false
		if atk.movement == BossAttackData.Movement.DASH and t > hit_time:
			dashing = true
			var dash_time: float = maxf(0.0001, atk.dash_time)
			var dash_prog: float = clampf((t - hit_time) / dash_time, 0.0, 1.0)
			boss_dx_units = dir * dock._dash_dist(atk) * dash_prog
		var boss_origin := origin + Vector2(boss_dx_units * scl, 0.0)

		# --- Telegraph shape (drawn at the FIXED origin, not the dashing boss) -
		# The zone is telegraphed at windup start and doesn't move with the dash.
		var shape_alpha_mult: float = _shape_alpha(atk, t, hit_time)
		if shape_alpha_mult > 0.0:
			var flash: bool = _is_flashing(t, hit_time)
			_draw_shape(atk, origin, dir, scl, shape_alpha_mult, flash)

		# --- Dash ghost + arrow (only if DASH) --------------------------------
		if atk.movement == BossAttackData.Movement.DASH:
			_draw_dash(atk, origin, dir, scl)

		# --- Boss sprite ------------------------------------------------------
		var tint: Color = _windup_tint(t, hit_time)
		_draw_sprite(anim, frame_idx, boss_origin, scl, dir, tint)

		# --- Phase label ------------------------------------------------------
		_draw_phase_label(atk, t, hit_time, t_total)

	# --- Extent helpers (game-units) ----------------------------------------

	func _forward_extent(atk: BossAttackData) -> float:
		# Max forward reach of geometry, from origin toward facing.
		var reach: float = maxf(0.0, atk.reach)
		var fwd: float = 0.0
		match atk.shape:
			BossAttackData.Shape.RECT:
				# RECT far edge = reach*forward_offset_frac + reach*0.5.
				fwd = reach * (atk.forward_offset_frac + 0.5)
			BossAttackData.Shape.CIRCLE:
				fwd = reach
			BossAttackData.Shape.CONE:
				fwd = reach
		if atk.movement == BossAttackData.Movement.DASH:
			fwd = maxf(fwd, dock._dash_dist(atk))
		return maxf(20.0, fwd)

	func _behind_extent(atk: BossAttackData) -> float:
		# How far behind the origin the geometry reaches (for negative offsets /
		# circle / cone behind nothing). Keep a little so the boss isn't flush.
		var reach: float = maxf(0.0, atk.reach)
		var behind: float = 0.0
		match atk.shape:
			BossAttackData.Shape.RECT:
				# RECT near edge = reach*forward_offset_frac - reach*0.5. If that's
				# negative the box extends behind the origin.
				var near: float = reach * (atk.forward_offset_frac - 0.5)
				if near < 0.0:
					behind = -near
			BossAttackData.Shape.CIRCLE:
				behind = reach
			BossAttackData.Shape.CONE:
				behind = 0.0
		return maxf(20.0, behind)

	func _vertical_half_extent(atk: BossAttackData) -> float:
		match atk.shape:
			BossAttackData.Shape.RECT:
				return maxf(20.0, atk.band_height * 0.5)
			BossAttackData.Shape.CIRCLE:
				return maxf(20.0, atk.reach)
			BossAttackData.Shape.CONE:
				# Cone half-height at its widest ~ reach * sin(half-angle).
				var half_ang: float = deg_to_rad(atk.cone_angle_deg * 0.5)
				return maxf(20.0, atk.reach * sin(half_ang))
			_:
				return 20.0

	func _sprite_width_units() -> float:
		var tex := _frame_texture(dock._resolve_anim(dock._selected_attack), 0)
		return float(tex.get_width()) if tex != null else 32.0

	func _sprite_height_units() -> float:
		var tex := _frame_texture(dock._resolve_anim(dock._selected_attack), 0)
		return float(tex.get_height()) if tex != null else 32.0

	# --- Frame / animation ---------------------------------------------------

	func _current_frame(atk: BossAttackData, anim: String, t: float, hit_time: float) -> int:
		var sf: SpriteFrames = dock._sprite_frames()
		if sf == null or anim.is_empty() or not sf.has_animation(anim):
			return 0
		var count: int = sf.get_frame_count(anim)
		if count <= 0:
			return 0
		var frac: float = clampf(t / hit_time, 0.0, 1.0) if hit_time > 0.0 else 1.0
		# During dash, keep advancing toward the last frame.
		if t > hit_time:
			frac = 1.0
		match atk.anim_mode:
			BossAttackData.AnimMode.STRETCH:
				# frame = floor(frac * count), clamped to last.
				return clampi(int(floor(frac * count)), 0, count - 1)
			BossAttackData.AnimMode.HOLD:
				# Advance toward hold_frame, freeze there until hit_time, then
				# play out. Approximate the runtime: before hit_time, march to
				# hold_frame; after, play to the end.
				var hold_f: int = atk.hold_frame
				if hold_f < 0:
					hold_f = count - 1
				hold_f = clampi(hold_f, 0, count - 1)
				if t < hit_time:
					# Reach hold_f partway through the windup, then sit on it.
					var to_hold: int = maxi(1, hold_f)
					var f: int = int(floor(clampf(t / hit_time, 0.0, 1.0) * (to_hold + 1)))
					return clampi(f, 0, hold_f)
				else:
					# Play remaining frames over the dash window (or instantly).
					return count - 1
			BossAttackData.AnimMode.FREE:
				# frame = floor(t * fps) wrapped by count.
				var fps: float = sf.get_animation_speed(anim)
				if fps <= 0.0:
					return 0
				return int(floor(t * fps)) % count
		return 0

	func _frame_texture(anim: String, idx: int) -> Texture2D:
		var sf: SpriteFrames = dock._sprite_frames()
		if sf == null or anim.is_empty() or not sf.has_animation(anim):
			return null
		var count: int = sf.get_frame_count(anim)
		if count <= 0:
			return null
		return sf.get_frame_texture(anim, clampi(idx, 0, count - 1))

	# --- Drawing primitives --------------------------------------------------

	func _draw_ground_and_ruler(origin: Vector2, scl: float, sz: Vector2) -> void:
		var font := get_theme_default_font()
		var fs := 9
		# Ground line.
		draw_line(Vector2(0, origin.y), Vector2(sz.x, origin.y), COL_GROUND, 1.5)
		# Vertical ticks every RULER_STEP game-units, labeled in px, both sides.
		var step_px: float = RULER_STEP * scl
		if step_px < 6.0:
			return  # too dense to be legible; skip the ruler
		var n: int = int(ceil(sz.x / step_px)) + 1
		for i in range(-n, n + 1):
			var x: float = origin.x + i * step_px
			if x < 0.0 or x > sz.x:
				continue
			var tick_h: float = 6.0 if (i % 2 == 0) else 3.0
			draw_line(Vector2(x, origin.y - tick_h), Vector2(x, origin.y + tick_h), COL_RULER, 1.0)
			if i != 0 and i % 2 == 0 and font != null:
				var px_val: int = int(round(i * RULER_STEP))
				draw_string(font, Vector2(x + 1, origin.y + 14), str(px_val),
					HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_RULER_TEXT)
		# Origin marker.
		draw_circle(origin, 3.0, Color(0.9, 0.9, 0.3, 0.9))

	func _draw_shape(atk: BossAttackData, origin: Vector2, dir: int, scl: float,
			alpha_mult: float, flash: bool) -> void:
		var fill: Color = (COL_SHAPE_FILL_FLASH if flash else COL_SHAPE_FILL)
		fill.a *= alpha_mult
		var line: Color = COL_SHAPE_LINE
		line.a *= alpha_mult

		match atk.shape:
			BossAttackData.Shape.RECT:
				# Center = origin + dir * reach * forward_offset_frac (screen: only
				# x offsets; y stays on the ground line). Box = (reach, band_height).
				var cx: float = origin.x + dir * atk.reach * atk.forward_offset_frac * scl
				var cy: float = origin.y  # band centered on ground line
				var w: float = atk.reach * scl
				var h: float = atk.band_height * scl
				var rect := Rect2(cx - w * 0.5, cy - h * 0.5, w, h)
				draw_rect(rect, fill, true)
				draw_rect(rect, line, false, 1.5)
				_draw_metric_label("reach %.0f" % atk.reach,
					Vector2(cx, cy - h * 0.5 - 6))
			BossAttackData.Shape.CIRCLE:
				# Radius = reach, centered on ORIGIN.
				var r: float = atk.reach * scl
				draw_circle(origin, r, fill)
				draw_arc(origin, r, 0.0, TAU, 48, line, 1.5)
				_draw_metric_label("r %.0f" % atk.reach, Vector2(origin.x, origin.y - r - 6))
			BossAttackData.Shape.CONE:
				_draw_cone(atk, origin, dir, scl, fill, line)
				_draw_metric_label("reach %.0f / %.0f°" % [atk.reach, atk.cone_angle_deg],
					origin + Vector2(dir * atk.reach * 0.5 * scl, -atk.reach * 0.5 * scl))

	func _draw_cone(atk: BossAttackData, origin: Vector2, dir: int, scl: float,
			fill: Color, line: Color) -> void:
		# Fan from origin toward dir, total angle cone_angle_deg, length reach.
		# The runtime hit-test caps by radial length (to_p.length() <= reach), so
		# draw an arc cap rather than a flat one.
		var r: float = atk.reach * scl
		var half: float = deg_to_rad(atk.cone_angle_deg * 0.5)
		var base_ang: float = 0.0 if dir > 0 else PI  # facing direction in screen space
		var a0: float = base_ang - half
		var a1: float = base_ang + half
		var segs: int = maxi(2, int(atk.cone_angle_deg / 6.0))
		var pts: PackedVector2Array = []
		pts.append(origin)
		for i in range(segs + 1):
			var a: float = lerp(a0, a1, float(i) / float(segs))
			pts.append(origin + Vector2(cos(a), sin(a)) * r)
		# Filled pie.
		if pts.size() >= 3:
			draw_colored_polygon(pts, fill)
		# Outline: two edges + the arc.
		draw_line(origin, origin + Vector2(cos(a0), sin(a0)) * r, line, 1.5)
		draw_line(origin, origin + Vector2(cos(a1), sin(a1)) * r, line, 1.5)
		draw_arc(origin, r, a0, a1, segs, line, 1.5)

	func _draw_dash(atk: BossAttackData, origin: Vector2, dir: int, scl: float) -> void:
		var dist: float = dock._dash_dist(atk)
		var end := origin + Vector2(dir * dist * scl, 0.0)
		# Ghost sprite at the end pose.
		var anim: String = dock._resolve_anim(atk)
		var tex := _frame_texture(anim, _last_frame_idx(anim))
		if tex != null:
			_blit_sprite(tex, end, scl, dir, COL_GHOST)
		# Arrow origin -> end (slightly above the ground so it reads).
		var ay: float = origin.y - 10.0
		var p0 := Vector2(origin.x, ay)
		var p1 := Vector2(end.x, ay)
		draw_line(p0, p1, COL_DASH, 2.0)
		# Arrowhead.
		var head: float = 7.0
		var back: float = -dir * head
		draw_line(p1, p1 + Vector2(back, -head * 0.6), COL_DASH, 2.0)
		draw_line(p1, p1 + Vector2(back, head * 0.6), COL_DASH, 2.0)
		# Distance label at the midpoint.
		var font := get_theme_default_font()
		if font != null:
			var mid := Vector2((p0.x + p1.x) * 0.5, ay - 4)
			draw_string(font, mid, "dash %.0f px" % dist,
				HORIZONTAL_ALIGNMENT_CENTER, -1, 10, COL_DASH)

	func _last_frame_idx(anim: String) -> int:
		var sf: SpriteFrames = dock._sprite_frames()
		if sf == null or anim.is_empty() or not sf.has_animation(anim):
			return 0
		return maxi(0, sf.get_frame_count(anim) - 1)

	func _draw_sprite(anim: String, frame_idx: int, where: Vector2, scl: float,
			dir: int, tint: Color) -> void:
		var tex := _frame_texture(anim, frame_idx)
		if tex == null:
			# No sprite — draw a placeholder box so the origin is still legible.
			var ph := Rect2(where.x - 12, where.y - 24, 24, 24)
			draw_rect(ph, Color(0.4, 0.4, 0.5, 0.6), true)
			draw_rect(ph, Color(0.7, 0.7, 0.8, 0.8), false, 1.0)
			return
		_blit_sprite(tex, where, scl, dir, tint)

	## Draws `tex` centered horizontally on `where`, with its bottom on where.y
	## (the ground line). Flips horizontally when dir < 0.
	func _blit_sprite(tex: Texture2D, where: Vector2, scl: float, dir: int, tint: Color) -> void:
		var w: float = tex.get_width() * scl
		var h: float = tex.get_height() * scl
		var rect := Rect2(where.x - w * 0.5, where.y - h, w, h)
		if dir < 0:
			# Flip horizontally: negative width rect.
			var flipped := Rect2(where.x + w * 0.5, where.y - h, -w, h)
			draw_texture_rect(tex, flipped, false, tint)
		else:
			draw_texture_rect(tex, rect, false, tint)

	# --- Timeline-driven cosmetics ------------------------------------------

	## Windup tint: white -> Color(1,0.35,0.3) by t/hit_time. After hit, stay red.
	func _windup_tint(t: float, hit_time: float) -> Color:
		var frac: float = clampf(t / hit_time, 0.0, 1.0) if hit_time > 0.0 else 1.0
		return Color.WHITE.lerp(Color(1.0, 0.35, 0.3, 1.0), frac)

	## Telegraph alpha multiplier: grows 0->1 over the windup, holds at the hit,
	## then fades out during the dash.
	func _shape_alpha(atk: BossAttackData, t: float, hit_time: float) -> float:
		if t < hit_time:
			return clampf(t / hit_time, 0.0, 1.0) if hit_time > 0.0 else 1.0
		# After the hit: brief full, then fade across the dash (if any).
		if atk.movement == BossAttackData.Movement.DASH:
			var dash_time: float = maxf(0.0001, atk.dash_time)
			var dash_prog: float = clampf((t - hit_time) / dash_time, 0.0, 1.0)
			return clampf(1.0 - dash_prog, 0.0, 1.0)
		# No dash: the hit is the end; show it full at the instant.
		return 1.0

	## True for a brief window right at the hit, so the shape flashes bright.
	func _is_flashing(t: float, hit_time: float) -> bool:
		return absf(t - hit_time) < 0.08

	func _draw_phase_label(atk: BossAttackData, t: float, hit_time: float, t_total: float) -> void:
		var font := get_theme_default_font()
		if font == null:
			return
		var phase: String
		if t < hit_time:
			phase = "WINDUP  %.2f / %.2fs" % [t, hit_time]
		elif _is_flashing(t, hit_time):
			phase = "HIT!"
		elif atk.movement == BossAttackData.Movement.DASH and t < t_total:
			phase = "DASH  %.2f / %.2fs" % [t - hit_time, atk.dash_time]
		else:
			phase = "DONE"
		draw_string(font, Vector2(8, 16), phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, COL_LABEL)

	func _draw_metric_label(text: String, at: Vector2) -> void:
		var font := get_theme_default_font()
		if font == null:
			return
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, -1, 9, COL_LABEL)

	func _draw_hint(text: String) -> void:
		var font := get_theme_default_font()
		if font == null:
			return
		draw_string(font, Vector2(12, size.y * 0.5), text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(0.7, 0.72, 0.78, 0.9))
