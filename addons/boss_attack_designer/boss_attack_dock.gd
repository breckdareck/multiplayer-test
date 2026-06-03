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

# --- Edit-fields UI refs ---
var _toolbar: HBoxContainer = null
var _add_btn: Button = null
var _dup_btn: Button = null
var _del_btn: Button = null
var _save_btn: Button = null
var _status_label: Label = null
var _placeholder_banner: Label = null
var _legacy_hint: Label = null
var _fields_container: GridContainer = null

# Field controls (filled by _populate_fields, read by their change handlers).
var _f_attack_name: LineEdit = null
var _f_shape: OptionButton = null
var _f_reach: SpinBox = null
var _f_band_height: SpinBox = null
var _f_cone_angle_deg: SpinBox = null
var _f_forward_offset_frac: SpinBox = null
var _f_windup_time: SpinBox = null
var _f_hit_time: SpinBox = null
var _f_cooldown: SpinBox = null
var _f_anim_mode: OptionButton = null
var _f_windup_anim: OptionButton = null
var _f_hold_frame: SpinBox = null
var _f_movement: OptionButton = null
var _f_dash_distance: SpinBox = null
var _f_dash_time: SpinBox = null
var _f_damage_mult: SpinBox = null
var _f_logic_script: EditorResourcePicker = null

# --- Edit / save state ---
var _applying_field: bool = false   # true while we write a field -> selected_attack
var _loading_fields: bool = false   # true while we programmatically set field controls
var _unsaved: bool = false          # true once any unpersisted edit has been made
var _is_placeholder: bool = false   # true when EnemyData is a placeholder (no @tool)

# --- Playback state (owned by the dock, read by the preview) ---
var _playing: bool = false
var _time: float = 0.0          # seconds into the timeline
var _scrubbing: bool = false    # user is dragging the slider; don't fight it
var _speed_opt: OptionButton = null
var _play_speed: float = 1.0
const _SPEEDS: Array[float] = [1.0, 0.5, 0.25, 0.1]
const _SPEED_LABELS: Array[String] = ["1×", "0.5×", "0.25×", "0.1×"]
# While playing we force the editor to redraw continuously (it otherwise idles at a
# low fps, sampling playback coarsely). Saved + restored so we don't leave it on.
const _UPDATE_KEY: String = "interface/editor/update_continuously"
var _continuous_active: bool = false
var _prev_update_continuous: bool = false


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

	# Toolbar: Add / Duplicate / Delete / Save + status.
	_toolbar = HBoxContainer.new()
	_toolbar.add_theme_constant_override("separation", 4)
	vb.add_child(_toolbar)

	_add_btn = Button.new()
	_add_btn.text = "+ Add"
	_add_btn.tooltip_text = "Add a new attack to this boss's special_attacks."
	_add_btn.pressed.connect(_on_add_attack)
	_toolbar.add_child(_add_btn)

	_dup_btn = Button.new()
	_dup_btn.text = "Duplicate"
	_dup_btn.tooltip_text = "Deep-copy the selected attack."
	_dup_btn.pressed.connect(_on_duplicate_attack)
	_toolbar.add_child(_dup_btn)

	_del_btn = Button.new()
	_del_btn.text = "Delete"
	_del_btn.tooltip_text = "Remove the selected attack."
	_del_btn.pressed.connect(_on_delete_attack)
	_toolbar.add_child(_del_btn)

	_save_btn = Button.new()
	_save_btn.text = "Save"
	_save_btn.tooltip_text = "Persist this boss's attacks to disk."
	_save_btn.pressed.connect(_on_save)
	_toolbar.add_child(_save_btn)

	_status_label = Label.new()
	_status_label.text = ""
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_toolbar.add_child(_status_label)

	# Placeholder banner (hidden unless EnemyData loads as a placeholder).
	_placeholder_banner = Label.new()
	_placeholder_banner.text = "Restart the Godot editor to enable editing — EnemyData is loaded as a placeholder until its new @tool mode takes effect."
	_placeholder_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_placeholder_banner.add_theme_color_override("font_color", Color(1.0, 0.7, 0.35))
	_placeholder_banner.visible = false
	vb.add_child(_placeholder_banner)

	# Legacy-synth hint (hidden unless the current attack is a legacy synth).
	_legacy_hint = Label.new()
	_legacy_hint.text = "Legacy synth (from special_attack_* fields). Editing will save it as a new authored attack."
	_legacy_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_legacy_hint.add_theme_color_override("font_color", Color(0.98, 0.6, 0.4))
	_legacy_hint.visible = false
	vb.add_child(_legacy_hint)

	# Edit Fields panel (scrollable grid of label + control rows).
	var fields_scroll := ScrollContainer.new()
	fields_scroll.custom_minimum_size = Vector2(0, 230)
	fields_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fields_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(fields_scroll)

	_fields_container = GridContainer.new()
	_fields_container.columns = 2
	_fields_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_container.add_theme_constant_override("h_separation", 6)
	_fields_container.add_theme_constant_override("v_separation", 3)
	fields_scroll.add_child(_fields_container)

	_build_field_controls()

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

	# Playback speed — slow it down to watch a transition land on its exact time
	# (editor idle-fps samples live playback coarsely; lower speed = finer sampling).
	_speed_opt = OptionButton.new()
	for lbl in _SPEED_LABELS:
		_speed_opt.add_item(lbl)
	_speed_opt.select(0)
	_speed_opt.tooltip_text = "Playback speed (lower = inspect transitions precisely)"
	_speed_opt.item_selected.connect(func(idx: int): _play_speed = _SPEEDS[idx])
	play_row.add_child(_speed_opt)

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


# --- Edit Fields construction -----------------------------------------------

## Builds every field control once and adds it (with a label) to the grid. The
## values are filled later by _populate_fields() whenever the selected attack
## changes. Each control's change handler writes back to _selected_attack.
func _build_field_controls() -> void:
	_f_attack_name = _make_line_edit()
	_f_attack_name.text_changed.connect(func(v: String): _apply_field("attack_name", v))
	_add_field_row("attack_name", _f_attack_name)

	_f_shape = _make_option(["RECT", "CIRCLE", "CONE"])
	_f_shape.item_selected.connect(func(i: int): _apply_field("shape", i); _refresh_field_relevance())
	_add_field_row("shape", _f_shape)

	_f_reach = _make_spin(0.0, 4000.0, 1.0, true)
	_f_reach.value_changed.connect(func(v: float): _apply_field("reach", v))
	_add_field_row("reach (px)", _f_reach)

	_f_band_height = _make_spin(0.0, 2000.0, 1.0, true)
	_f_band_height.value_changed.connect(func(v: float): _apply_field("band_height", v))
	_add_field_row("band_height (px)", _f_band_height)

	_f_cone_angle_deg = _make_spin(0.0, 360.0, 1.0, false)
	_f_cone_angle_deg.value_changed.connect(func(v: float): _apply_field("cone_angle_deg", v))
	_add_field_row("cone_angle_deg", _f_cone_angle_deg)

	_f_forward_offset_frac = _make_spin(0.0, 1.0, 0.05, false)
	_f_forward_offset_frac.value_changed.connect(func(v: float): _apply_field("forward_offset_frac", v))
	_add_field_row("forward_offset_frac", _f_forward_offset_frac)

	_f_windup_time = _make_spin(0.0, 60.0, 0.1, true)
	_f_windup_time.value_changed.connect(func(v: float): _apply_field("windup_time", v))
	_add_field_row("windup_time (s)", _f_windup_time)

	_f_hit_time = _make_spin(0.0, 60.0, 0.1, true)
	_f_hit_time.value_changed.connect(func(v: float): _apply_field("hit_time", v))
	_add_field_row("hit_time (s)", _f_hit_time)

	_f_cooldown = _make_spin(0.0, 600.0, 0.1, true)
	_f_cooldown.value_changed.connect(func(v: float): _apply_field("cooldown", v))
	_add_field_row("cooldown (s)", _f_cooldown)

	_f_anim_mode = _make_option(["STRETCH", "HOLD", "FREE"])
	_f_anim_mode.item_selected.connect(func(i: int): _apply_field("anim_mode", i))
	_add_field_row("anim_mode", _f_anim_mode)

	# windup_anim is populated dynamically from the boss SpriteFrames clips; its
	# item metadata holds the actual string value ("" for "(none)").
	_f_windup_anim = OptionButton.new()
	_f_windup_anim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_windup_anim.item_selected.connect(_on_windup_anim_selected)
	_add_field_row("windup_anim", _f_windup_anim)

	_f_hold_frame = _make_spin(-1.0, 4096.0, 1.0, true)
	_f_hold_frame.rounded = true
	_f_hold_frame.value_changed.connect(func(v: float): _apply_field("hold_frame", int(v)))
	_add_field_row("hold_frame", _f_hold_frame)

	_f_movement = _make_option(["NONE", "DASH"])
	_f_movement.item_selected.connect(func(i: int): _apply_field("movement", i); _refresh_field_relevance())
	_add_field_row("movement", _f_movement)

	_f_dash_distance = _make_spin(0.0, 4000.0, 1.0, true)
	_f_dash_distance.value_changed.connect(func(v: float): _apply_field("dash_distance", v))
	_add_field_row("dash_distance (px)", _f_dash_distance)

	_f_dash_time = _make_spin(0.0, 10.0, 0.1, true)
	_f_dash_time.value_changed.connect(func(v: float): _apply_field("dash_time", v))
	_add_field_row("dash_time (s)", _f_dash_time)

	_f_damage_mult = _make_spin(0.0, 100.0, 0.1, true)
	_f_damage_mult.value_changed.connect(func(v: float): _apply_field("damage_mult", v))
	_add_field_row("damage_mult (×)", _f_damage_mult)

	_f_logic_script = EditorResourcePicker.new()
	_f_logic_script.base_type = "Script"
	_f_logic_script.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_f_logic_script.resource_changed.connect(_on_logic_script_changed)
	_add_field_row("logic_script", _f_logic_script)


func _add_field_row(label_text: String, control: Control) -> void:
	var lab := Label.new()
	lab.text = label_text
	lab.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lab.custom_minimum_size = Vector2(140, 0)
	_fields_container.add_child(lab)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_fields_container.add_child(control)


func _make_line_edit() -> LineEdit:
	var le := LineEdit.new()
	le.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return le


func _make_option(items: Array) -> OptionButton:
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in items.size():
		ob.add_item(items[i], i)
	return ob


func _make_spin(min_v: float, max_v: float, step: float, allow_greater: bool) -> SpinBox:
	var sb := SpinBox.new()
	sb.min_value = min_v
	sb.max_value = max_v
	sb.step = step
	sb.allow_greater = allow_greater
	sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return sb


# --- Field write-back (selected_attack <- control) --------------------------

## Writes a property on the selected attack, refreshing the preview/info but NOT
## the field controls. Guarded so the resource's `changed` signal (which we also
## listen to) doesn't trigger a control repopulate. Skips programmatic sets done
## while loading. Promotes a legacy synth on the first real edit.
func _apply_field(prop: String, value) -> void:
	if _loading_fields:
		return
	if _selected_attack == null or _is_placeholder:
		return
	# A legacy synth must be promoted to an authored attack before edits persist.
	if _is_legacy_synth:
		_promote_legacy_synth()
	_applying_field = true
	_selected_attack.set(prop, value)
	_selected_attack.emit_changed()
	_applying_field = false
	_mark_unsaved()
	_update_info()
	_redraw_preview()


func _on_windup_anim_selected(idx: int) -> void:
	if _f_windup_anim == null:
		return
	var v: String = str(_f_windup_anim.get_item_metadata(idx))
	_apply_field("windup_anim", v)


func _on_logic_script_changed(res: Resource) -> void:
	_apply_field("logic_script", res as Script)


# --- Field read (control <- selected_attack) --------------------------------

## Fills every field control from the selected attack. Wrapped in _loading_fields
## so the programmatic sets don't re-fire the change handlers. Called only when
## the SELECTED ATTACK changes (in _select_attack), never from the change loop.
func _populate_fields() -> void:
	_loading_fields = true
	var atk: BossAttackData = _selected_attack
	if atk != null:
		_f_attack_name.text = atk.attack_name
		_f_shape.select(clampi(atk.shape, 0, _f_shape.item_count - 1))
		_f_reach.set_value_no_signal(atk.reach)
		_f_band_height.set_value_no_signal(atk.band_height)
		_f_cone_angle_deg.set_value_no_signal(atk.cone_angle_deg)
		_f_forward_offset_frac.set_value_no_signal(atk.forward_offset_frac)
		_f_windup_time.set_value_no_signal(atk.windup_time)
		_f_hit_time.set_value_no_signal(atk.hit_time)
		_f_cooldown.set_value_no_signal(atk.cooldown)
		_f_anim_mode.select(clampi(atk.anim_mode, 0, _f_anim_mode.item_count - 1))
		_populate_windup_anim_options(atk.windup_anim)
		_f_hold_frame.set_value_no_signal(float(atk.hold_frame))
		_f_movement.select(clampi(atk.movement, 0, _f_movement.item_count - 1))
		_f_dash_distance.set_value_no_signal(atk.dash_distance)
		_f_dash_time.set_value_no_signal(atk.dash_time)
		_f_damage_mult.set_value_no_signal(atk.damage_mult)
		_f_logic_script.edited_resource = atk.logic_script
	_loading_fields = false
	_refresh_field_relevance()


## Rebuilds the windup_anim dropdown from the boss SpriteFrames clips. The first
## entry is "(none)" -> "". The current value is selected; if it isn't a known
## clip, it's added as "(missing) <name>" so editing doesn't silently drop it.
func _populate_windup_anim_options(current: String) -> void:
	_f_windup_anim.clear()
	_f_windup_anim.add_item("(none)")
	_f_windup_anim.set_item_metadata(0, "")
	var sel_idx: int = 0
	var sf: SpriteFrames = _sprite_frames()
	var names: PackedStringArray = []
	if sf != null:
		names = sf.get_animation_names()
	var found_current: bool = current.is_empty()
	for n in names:
		var idx: int = _f_windup_anim.item_count
		_f_windup_anim.add_item(n)
		_f_windup_anim.set_item_metadata(idx, n)
		if n == current:
			sel_idx = idx
			found_current = true
	if not found_current:
		# The stored clip isn't on this SpriteFrames — keep it so it's not lost.
		var idx: int = _f_windup_anim.item_count
		_f_windup_anim.add_item("(missing) %s" % current)
		_f_windup_anim.set_item_metadata(idx, current)
		sel_idx = idx
	_f_windup_anim.select(sel_idx)


## Optionally disables irrelevant rows for the current shape/movement. Visual aid
## only — leaves them visible. Never disables when placeholder/empty (those paths
## disable everything via _set_edit_enabled).
func _refresh_field_relevance() -> void:
	if _selected_attack == null or _is_placeholder:
		return
	var atk: BossAttackData = _selected_attack
	_f_band_height.editable = (atk.shape == BossAttackData.Shape.RECT)
	_f_cone_angle_deg.editable = (atk.shape == BossAttackData.Shape.CONE)
	var is_dash: bool = (atk.movement == BossAttackData.Movement.DASH)
	_f_dash_distance.editable = is_dash
	_f_dash_time.editable = is_dash
	_f_hold_frame.editable = (atk.anim_mode == BossAttackData.AnimMode.HOLD)


# --- Toolbar actions --------------------------------------------------------

func _on_add_attack() -> void:
	if _enemy_data == null or _is_placeholder:
		return
	var a := BossAttackData.new()
	a.attack_name = "New Attack"
	a.shape = BossAttackData.Shape.RECT
	a.reach = 140.0
	a.band_height = 64.0
	a.forward_offset_frac = 0.5
	a.windup_time = 1.0
	a.hit_time = 1.0
	a.cooldown = 6.0
	a.anim_mode = BossAttackData.AnimMode.STRETCH
	a.movement = BossAttackData.Movement.NONE
	a.damage_mult = 2.0
	_append_attack(a)


func _on_duplicate_attack() -> void:
	if _enemy_data == null or _is_placeholder or _selected_attack == null:
		return
	# Promote a legacy synth first so the duplicate has an authored sibling too.
	if _is_legacy_synth:
		_promote_legacy_synth()
	var a: BossAttackData = _selected_attack.duplicate(true)
	_append_attack(a)


## Appends an attack to the boss array, rebuilds the dropdown, selects the new
## one, and marks unsaved. Writes back the whole array property so the change
## sticks even if `special_attacks` returned a copy.
func _append_attack(a: BossAttackData) -> void:
	var arr: Array[BossAttackData] = _enemy_data.special_attacks.duplicate()
	arr.append(a)
	_enemy_data.special_attacks = arr
	_is_legacy_synth = false
	_mark_unsaved()
	_rebuild_dropdown(arr.size() - 1)


func _on_delete_attack() -> void:
	if _enemy_data == null or _is_placeholder or _selected_attack == null:
		return
	if _is_legacy_synth:
		# A synth isn't in the array; "deleting" it just clears the preview.
		_is_legacy_synth = false
		_attacks = []
		_disconnect_attack()
		_selected_attack = null
		_reset_playback()
		_update_info()
		_redraw_preview()
		_update_edit_ui_state()
		return
	var idx: int = _attacks.find(_selected_attack)
	var arr: Array[BossAttackData] = _enemy_data.special_attacks.duplicate()
	if idx >= 0 and idx < arr.size():
		arr.remove_at(idx)
	_enemy_data.special_attacks = arr
	_mark_unsaved()
	var new_idx: int = clampi(idx, 0, arr.size() - 1)
	_rebuild_dropdown(new_idx)


## Re-reads the boss array into _attacks, rebuilds the dropdown labels, and
## selects `select_idx` (clamped). Shared by Add/Duplicate/Delete.
func _rebuild_dropdown(select_idx: int) -> void:
	_attacks = []
	for a in _enemy_data.special_attacks:
		_attacks.append(a)
	_attack_dropdown.clear()
	for i in _attacks.size():
		var atk: BossAttackData = _attacks[i]
		var shape_name: String = _shape_name(atk.shape) if atk != null else "?"
		var atk_name: String = atk.attack_name if (atk != null and not atk.attack_name.is_empty()) else "(unnamed)"
		_attack_dropdown.add_item("%s  [%s]" % [atk_name, shape_name], i)
	if _attacks.is_empty():
		_disconnect_attack()
		_selected_attack = null
		_reset_playback()
		_update_info()
		_redraw_preview()
		_update_edit_ui_state()
		return
	var sel: int = clampi(select_idx, 0, _attacks.size() - 1)
	_attack_dropdown.select(sel)
	_select_attack(sel)


# --- Legacy-synth promotion -------------------------------------------------

## Appends the transient legacy-synth attack to the boss's authored array so
## edits/saves persist. Clears the synth flag and rebuilds the dropdown selecting
## the now-authored attack. Safe to call when not a synth (no-op).
func _promote_legacy_synth() -> void:
	if not _is_legacy_synth or _selected_attack == null or _enemy_data == null:
		return
	var promoted: BossAttackData = _selected_attack
	var arr: Array[BossAttackData] = _enemy_data.special_attacks.duplicate()
	arr.append(promoted)
	_enemy_data.special_attacks = arr
	_is_legacy_synth = false
	_attacks = []
	for a in arr:
		_attacks.append(a)
	# Rebuild dropdown labels (drop the "(synth)" wording) and reselect.
	var sel: int = arr.size() - 1
	_attack_dropdown.clear()
	for i in _attacks.size():
		var atk: BossAttackData = _attacks[i]
		var shape_name: String = _shape_name(atk.shape) if atk != null else "?"
		var atk_name: String = atk.attack_name if (atk != null and not atk.attack_name.is_empty()) else "(unnamed)"
		_attack_dropdown.add_item("%s  [%s]" % [atk_name, shape_name], i)
	_attack_dropdown.select(sel)
	# Keep our `changed` connection on this same instance; just refresh chrome.
	if _legacy_hint != null:
		_legacy_hint.visible = false
	_mark_unsaved()


# --- Save -------------------------------------------------------------------

func _on_save() -> void:
	if _enemy_data == null or _is_placeholder:
		return
	# Promote a legacy synth so there's something authored to persist.
	if _is_legacy_synth:
		_promote_legacy_synth()
	var ok: bool = true
	# Standalone-attack .tres (embedded sub-resources have no resource_path).
	if _selected_attack != null and _selected_attack.resource_path != "":
		var err := ResourceSaver.save(_selected_attack, _selected_attack.resource_path)
		ok = ok and (err == OK)
	# The EnemyData itself — persists the array + embedded sub-resource attacks.
	if _enemy_data.resource_path != "":
		var err2 := ResourceSaver.save(_enemy_data, _enemy_data.resource_path)
		ok = ok and (err2 == OK)
	else:
		ok = false  # nothing to save to
	if _editor_interface != null:
		var fs := _editor_interface.get_resource_filesystem()
		if fs != null:
			fs.scan()
	if ok:
		_unsaved = false
		_set_status("Saved ✓", Color(0.5, 0.85, 0.5))
	else:
		_set_status("Save failed ✗", Color(1.0, 0.4, 0.4))


# --- Status / edit-UI state -------------------------------------------------

func _mark_unsaved() -> void:
	_unsaved = true
	_set_status("● Unsaved changes", Color(1.0, 0.8, 0.4))


func _set_status(text: String, col: Color) -> void:
	if _status_label == null:
		return
	_status_label.text = text
	_status_label.add_theme_color_override("font_color", col)


## Detects whether the picked EnemyData is a real @tool instance or a placeholder.
## A placeholder doesn't expose script methods, so get_special_attacks() is absent;
## a real instance has it. Writing properties / saving only works on a real one.
func _refresh_placeholder_state() -> void:
	if _enemy_data == null:
		_is_placeholder = false
		return
	_is_placeholder = not _enemy_data.has_method("get_special_attacks")


## Enables/disables the edit controls + toolbar based on placeholder state and
## whether an attack is selected, and toggles the banner/legacy hint. Call after
## any change to _enemy_data, _selected_attack, or _is_legacy_synth.
func _update_edit_ui_state() -> void:
	if _placeholder_banner != null:
		_placeholder_banner.visible = (_enemy_data != null and _is_placeholder)
	if _legacy_hint != null:
		_legacy_hint.visible = (_is_legacy_synth and not _is_placeholder)

	var can_edit: bool = (_enemy_data != null and not _is_placeholder)
	var has_attack: bool = (_selected_attack != null)
	if _add_btn != null:
		_add_btn.disabled = not can_edit
	if _dup_btn != null:
		_dup_btn.disabled = not (can_edit and has_attack)
	if _del_btn != null:
		_del_btn.disabled = not (can_edit and has_attack)
	if _save_btn != null:
		_save_btn.disabled = not can_edit
	_set_fields_enabled(can_edit and has_attack)


func _set_fields_enabled(enabled: bool) -> void:
	if _fields_container == null:
		return
	if _f_attack_name != null:
		_f_attack_name.editable = enabled
	for sb in [_f_reach, _f_band_height, _f_cone_angle_deg, _f_forward_offset_frac,
			_f_windup_time, _f_hit_time, _f_cooldown, _f_hold_frame,
			_f_dash_distance, _f_dash_time, _f_damage_mult]:
		if sb != null:
			sb.editable = enabled
	for ob in [_f_shape, _f_anim_mode, _f_windup_anim, _f_movement]:
		if ob != null:
			ob.disabled = not enabled
	if _f_logic_script != null:
		_f_logic_script.editable = enabled
	# When enabling, re-apply shape/movement-based relevance greying.
	if enabled:
		_refresh_field_relevance()


# --- EnemyData / attack selection -------------------------------------------

func _on_enemy_data_changed(res: Resource) -> void:
	_enemy_data = res as EnemyData
	_refresh_placeholder_state()
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
		_update_edit_ui_state()
		return

	# Resolve via PROPERTY reads + an inline synth rather than calling
	# EnemyData.get_special_attacks(): the editor may hold the picked EnemyData as a
	# placeholder instance (e.g. before a full editor restart picks up @tool), and
	# methods can't be called on a placeholder — but @export properties are readable.
	var authored: Array = _enemy_data.special_attacks
	var list: Array[BossAttackData] = []
	if not authored.is_empty():
		for a in authored:
			list.append(a)
	elif _enemy_data.special_attack_cooldown > 0.0:
		list.append(_synth_legacy_attack(_enemy_data))
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
		_update_edit_ui_state()
		return

	_attack_dropdown.select(0)
	_select_attack(0)


## Builds the legacy dash-slam — mirrors EnemyData.get_special_attacks() exactly.
## Duplicated here (rather than calling the method) because the editor may load the
## picked EnemyData as a placeholder instance where methods can't be called; the
## legacy @export fields it reads ARE available on a placeholder. Keep in sync.
func _synth_legacy_attack(enemy: EnemyData) -> BossAttackData:
	var a := BossAttackData.new()
	a.attack_name = "Dash Slam"
	a.shape = BossAttackData.Shape.RECT
	a.reach = enemy.special_attack_radius * 2.0
	a.band_height = clampf(enemy.special_attack_radius * 0.55, 48.0, 110.0)
	a.forward_offset_frac = 0.5
	a.windup_time = enemy.special_telegraph_time
	a.hit_time = enemy.special_telegraph_time
	a.cooldown = enemy.special_attack_cooldown
	a.damage_mult = enemy.special_attack_damage_mult
	a.anim_mode = BossAttackData.AnimMode.STRETCH
	a.movement = BossAttackData.Movement.DASH
	a.dash_distance = 0.0
	a.dash_time = 0.18
	return a


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
	# Repopulate the edit-field controls ONLY here (selected attack changed),
	# never from the resource `changed` handler — that would fight live typing.
	_populate_fields()
	_update_edit_ui_state()
	_update_info()
	_redraw_preview()


func _on_attack_resource_changed() -> void:
	# The selected BossAttackData's `changed` fired. If WE caused it (a field
	# write from this dock), only refresh the preview — do NOT repopulate the
	# field controls, or we'd clobber the control the user is editing. If it came
	# from elsewhere (the Inspector), refresh the controls too.
	if _applying_field:
		_update_info()
		_redraw_preview()
		return
	_populate_fields()
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
		_set_continuous_redraw(true)
	else:
		_play_btn.text = "▶ Play"
		_set_continuous_redraw(false)


## Force the editor to render continuously (full fps) while playing, so playback
## isn't sampled at the editor's coarse idle redraw rate. Saved + restored.
func _set_continuous_redraw(on: bool) -> void:
	if _editor_interface == null:
		return
	var settings := _editor_interface.get_editor_settings()
	if settings == null or not settings.has_setting(_UPDATE_KEY):
		return
	if on:
		if not _continuous_active:
			_prev_update_continuous = bool(settings.get_setting(_UPDATE_KEY))
			settings.set_setting(_UPDATE_KEY, true)
			_continuous_active = true
	elif _continuous_active:
		settings.set_setting(_UPDATE_KEY, _prev_update_continuous)
		_continuous_active = false


func _exit_tree() -> void:
	# Don't leave the editor stuck in continuous-redraw if the dock goes away mid-play.
	_set_continuous_redraw(false)


func _reset_playback() -> void:
	_playing = false
	_set_continuous_redraw(false)
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
	_time += delta * _play_speed
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
		# The dash starts at windup_time and lasts dash_time; recover when both the
		# hit has fired and the dash has finished.
		var windup: float = clampf(_selected_attack.windup_time, 0.05, maxf(0.05, hit))
		t = maxf(hit, windup + maxf(0.0, _selected_attack.dash_time))
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
	var eff_windup: float = clampf(atk.windup_time, 0.05, maxf(0.05, atk.hit_time))
	var strike_lead: float = maxf(0.0, atk.hit_time - eff_windup)
	lines.append("[color=#9fd]timing:[/color] wind-up+hold %.2fs → [b]release[/b] (strike + dash begin) → %.2fs lead → [b]DAMAGE[/b] @ %.2fs   cooldown %.1fs" % [
		eff_windup, strike_lead, atk.hit_time, atk.cooldown,
	])
	if strike_lead < 0.01:
		lines.append("  [color=#fa6]windup_time == hit_time → strike + dash begin at the same instant damage lands (no lead-in). Set windup_time < hit_time so the dash carries in before the hit.[/color]")
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
		var frame_count: int = sf.get_frame_count(resolved_anim) if (sf != null and sf.has_animation(resolved_anim)) else 0
		if atk.hold_frame < 0 or atk.hold_frame >= frame_count - 1:
			var eff: int = clampi(int(frame_count / 2), 0, maxi(0, frame_count - 2))
			lines.append("  hold_frame: %d → auto mid [b]%d[/b]  (freeze through the windup, then play %d→%d as the strike)" % [atk.hold_frame, eff, eff, maxi(0, frame_count - 1)])
		else:
			lines.append("  hold_frame: %d  (freeze through the windup, then play %d→%d as the strike)" % [atk.hold_frame, atk.hold_frame, maxi(0, frame_count - 1)])
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
		# The dash begins at windup_time (when the hold releases), not at the hit.
		var windup_d: float = clampf(atk.windup_time, 0.05, hit_time)
		if atk.movement == BossAttackData.Movement.DASH and t > windup_d:
			dashing = true
			var dash_time: float = maxf(0.0001, atk.dash_time)
			var dash_prog: float = clampf((t - windup_d) / dash_time, 0.0, 1.0)
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
				# Mirrors the runtime: play the wind-up (0 -> hold_frame) at native speed,
				# FREEZE on hold_frame until windup_time, then play hold_frame -> end (the
				# strike). Unset (-1)/out-of-range hold_frame defaults to a MID frame.
				var fps_h: float = sf.get_animation_speed(anim)
				var hold_f: int = atk.hold_frame
				if hold_f < 0 or hold_f >= count - 1:
					hold_f = clampi(int(count / 2), 0, maxi(0, count - 2))
				if fps_h <= 0.0:
					return hold_f
				var windup: float = clampf(atk.windup_time, 0.05, hit_time)
				if t < windup:
					# Wind-up: advance 0 -> hold_f at native speed, then sit on hold_f.
					return clampi(int(floor(t * fps_h)), 0, hold_f)
				# Strike: swap to hold_f+1 at release, then stretch hold_f+1 -> last so
				# the last frame lands at hit_time.
				var last: int = count - 1
				var nxt: int = mini(hold_f + 1, last)
				var gap: float = hit_time - windup
				if gap <= 0.001:
					return last
				var sfrac: float = clampf((t - windup) / gap, 0.0, 1.0)
				return clampi(nxt + int(floor(sfrac * float(last - nxt))), nxt, last)
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
