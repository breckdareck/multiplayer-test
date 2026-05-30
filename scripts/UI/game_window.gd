extends Panel

## Unified game hub (ADR 0003). Builds ONE clean window: a Character tab with 3
## authored columns (Equipment | Stats | Inventory) and an Abilities tab. On load
## it pulls the CONTENT out of the existing windows into those columns/hosts —
## not the whole windows — so there is one frame + one set of column headers, not
## three glued sub-windows. Each source window's shell is kept alive (hidden, its
## per-frame input off) so its controller script keeps driving the moved content
## via its node references (which survive reparenting — the components use
## node-reference @exports, so gear/inventory/stats keep syncing, no NodePath edits).
## Non-modal: movable, never locks input. Path-resolved (no class_name).

@onready var title_label: Label = %HubTitle
@onready var tab_bar: TabBar = %HubTabBar
@onready var character_page: Control = %CharacterPage
@onready var abilities_page: Control = %AbilitiesPage
@onready var equip_host: Control = %EquipHost
@onready var stats_host: Control = %StatsHost
@onready var inv_host: Control = %InvHost
@onready var abil_host: Control = %AbilHost
@onready var close_button: Button = %HubCloseButton

const FONT := preload("res://assets/fonts/PixelOperator8.ttf")

var player
var _absorbed := false
var _dragging := false
var _drag_offset := Vector2()
var _ability_shell: Node = null
var _hdr_name: Label
var _hdr_sub: Label

# Fresh mock-styled stats panel (built in StatsHost; the old stats window is not
# reparented — its rows are too verbose / differently labelled).
const _DERIVED := ["HP", "MP", "Attack", "Magic Atk", "Defense", "Mag Def", "Crit Rate", "Crit Dmg", "Dmg Range"]
var _stat_rows := {}
var _attr_vals := {}
var _unspent_lbl: Label
var _stats_built := false

const HOTKEY_TAB := {
	"OpenEquipmentWindow": 0, "OpenInventoryWindow": 0, "OpenStatsWindow": 0,
	"OpenAbilityWindow": 1,
}


func _ready() -> void:
	add_to_group("ui_window")
	visible = false
	if owner is MultiplayerPlayerV2:
		player = owner
	if is_instance_valid(tab_bar):
		tab_bar.tab_changed.connect(_on_tab_changed)
	if is_instance_valid(close_button):
		close_button.pressed.connect(func(): visible = false)
	# Defer so every sibling window is in-tree and its component exports resolved.
	call_deferred("_absorb_windows")


func _absorb_windows() -> void:
	if _absorbed:
		return
	var src := get_parent()  # CanvasLayer/MoveableWindows
	if src == null:
		return
	var eqw := src.get_node_or_null("EquipmentWindow")
	_absorb(eqw, equip_host)
	if eqw:
		# Mock = NO Equipment/Pets toggle: show gear AND the pet panel together,
		# pet directly under the equipment slots. Hide the toggle bar; force both
		# the gear panel and the pet content visible.
		var toggle := equip_host.find_child("TabButtons", true, false)
		if toggle is CanvasItem:
			(toggle as CanvasItem).visible = false
		if "equipment_panel" in eqw and is_instance_valid(eqw.equipment_panel):
			var ep := eqw.equipment_panel as Control
			ep.visible = true
			ep.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # gear top, natural height
		if "pet_tab_content" in eqw and is_instance_valid(eqw.pet_tab_content):
			var pc := eqw.pet_tab_content as Control
			pc.visible = true
			pc.size_flags_vertical = Control.SIZE_EXPAND_FILL    # pet panel fills below
			# The full pet_tab is a roster list + detail; in the narrow column the
			# roster strip ("PETS" list) reads as broken. Hide it → compact pet box
			# (portrait/name/hunger/summon/slots) like the mock.
			var roster := pc.find_child("ListPanel", true, false)
			if roster is CanvasItem:
				(roster as CanvasItem).visible = false
	# Lay the 6 equipment slots out 2-wide (mock paperdoll).
	var grid := equip_host.find_child("GridContainer", true, false)
	if grid is GridContainer:
		(grid as GridContainer).columns = 2
	# Character header card (name / Lv + class) at the top of the equipment column.
	var hdr := _make_char_header()
	equip_host.add_child(hdr)
	equip_host.move_child(hdr, 0)
	_refresh_header()
	# Stats: build a fresh mock-styled panel reading the same components; disable
	# the old stats window shell (don't reparent its verbose rows).
	var sw := src.get_node_or_null("StatsWindow")
	if sw:
		sw.set_process(false)
		sw.set_process_input(false)
		if sw is CanvasItem:
			(sw as CanvasItem).visible = false
	_build_stats_panel()
	_absorb(src.get_node_or_null("InventoryWindow"), inv_host)
	# Densify the inventory grids toward the mock (6-wide); revert if they overflow.
	for g in inv_host.find_children("", "GridContainer", true, false):
		(g as GridContainer).columns = 6
	_ability_shell = src.get_node_or_null("AbilityWindow")
	_absorb(_ability_shell, abil_host)
	_absorbed = true
	_show_tab(0)


## Moves a window's CONTENT children into `host`, hides its chrome, keeps the
## (now-empty) shell alive + input-off so its script still drives the content.
func _absorb(w: Node, host: Node) -> void:
	if w == null or host == null or not is_instance_valid(w):
		return
	w.set_process(false)
	w.set_process_input(false)
	w.set_process_unhandled_input(false)
	for child in w.get_children():
		if child.name == "Label" or child.name == "CloseButton":
			if child is CanvasItem:
				(child as CanvasItem).visible = false
			continue
		w.remove_child(child)
		host.add_child(child)
		if child is Control:
			var c := child as Control
			_reset_anchors(c)
			c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			c.size_flags_vertical = Control.SIZE_EXPAND_FILL if _is_big(c) else Control.SIZE_FILL
			c.visible = true
	# Source content can carry its own nested title/close (e.g. the ability
	# window's header) — hide those so only the hub chrome remains.
	_hide_named(host, ["CloseButton", "TitleLabel"])
	if w is CanvasItem:
		(w as CanvasItem).visible = false


func _is_big(c: Control) -> bool:
	# Panel (not just PanelContainer) covers the stats window's StatsPanel — without
	# this it gets SIZE_FILL and collapses to zero height (blank STATS column).
	return c is TabContainer or c is MarginContainer or c is ScrollContainer \
		or c is HSplitContainer or c is PanelContainer or c is VBoxContainer or c is Panel


func _reset_anchors(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	c.position = Vector2.ZERO


func _hide_named(node: Node, names: Array) -> void:
	for c in node.get_children():
		if c.name in names:
			if c is CanvasItem:
				(c as CanvasItem).visible = false
		else:
			_hide_named(c, names)


func _on_tab_changed(idx: int) -> void:
	_show_tab(idx)


func _show_tab(idx: int) -> void:
	if is_instance_valid(character_page):
		character_page.visible = idx == 0
	if is_instance_valid(abilities_page):
		abilities_page.visible = idx == 1
	# The ability window normally refreshes its tree on open; trigger it on tab show.
	if idx == 1 and _ability_shell and _ability_shell.has_method("load_ability_list"):
		_ability_shell.call("load_ability_list")
	if idx == 0:
		_refresh_header()
		_refresh_stats()


## A small "name / Lv N <Class>" card for the top of the equipment column.
func _make_char_header() -> Control:
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(0, 50)
	p.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.13)
	sb.border_color = Color(0.3, 0.3, 0.36)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(6)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	p.add_child(h)
	var port := Panel.new()
	port.custom_minimum_size = Vector2(38, 38)
	h.add_child(port)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(v)
	_hdr_name = Label.new()
	_hdr_name.add_theme_font_override("font", FONT)
	_hdr_name.add_theme_font_size_override("font_size", 13)
	_hdr_name.add_theme_color_override("font_color", Color(1, 1, 1))
	v.add_child(_hdr_name)
	_hdr_sub = Label.new()
	_hdr_sub.add_theme_font_override("font", FONT)
	_hdr_sub.add_theme_font_size_override("font_size", 10)
	_hdr_sub.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	v.add_child(_hdr_sub)
	return p


const _DISC_NAMES := ["Sword", "Bow", "Staff", "Dagger"]

func _refresh_header() -> void:
	if player == null or not is_instance_valid(_hdr_name):
		return
	_hdr_name.text = str(player.username) if "username" in player else "Player"
	var lvl: int = 0
	if "level_component" in player and player.level_component:
		lvl = int(player.level_component.level)
	var cls := ""
	if player.has_method("get_active_discipline"):
		var d: int = player.get_active_discipline()
		if d >= 0 and d < _DISC_NAMES.size():
			cls = _DISC_NAMES[d]
	_hdr_sub.text = "Lv %d   %s" % [lvl, cls]
	if is_instance_valid(title_label):
		title_label.text = "CHARACTER   ·   %s   Lv %d   %s" % [_hdr_name.text, lvl, cls]


## Mock-styled stats panel: a tight derived-stat list + a green ATTRIBUTES section
## with per-attribute + buttons + Respec. Reads the same components the old stats
## window did; refreshed on stat/attribute signals + on Character-tab show.
func _build_stats_panel() -> void:
	if _stats_built or not is_instance_valid(stats_host):
		return
	_stats_built = true
	for k in _DERIVED:
		_stat_rows[k] = _kv_row(stats_host, k)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 12)
	stats_host.add_child(sep)
	_unspent_lbl = Label.new()
	_unspent_lbl.add_theme_font_override("font", FONT)
	_unspent_lbl.add_theme_font_size_override("font_size", 12)
	_unspent_lbl.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
	stats_host.add_child(_unspent_lbl)
	var attrs := [Constants.StatType.STRENGTH, Constants.StatType.DEXTERITY, Constants.StatType.INTELLIGENCE, Constants.StatType.LUCK, Constants.StatType.CONSTITUTION]
	for a in attrs:
		var row := HBoxContainer.new()
		var nl := Label.new()
		nl.text = _attr_name(a)
		nl.add_theme_font_override("font", FONT)
		nl.add_theme_font_size_override("font_size", 12)
		nl.add_theme_color_override("font_color", Color(1, 1, 1))
		nl.custom_minimum_size = Vector2(64, 0)
		row.add_child(nl)
		var vl := Label.new()
		vl.text = "0"
		vl.add_theme_font_override("font", FONT)
		vl.add_theme_font_size_override("font_size", 12)
		vl.add_theme_color_override("font_color", Color(1, 1, 1))
		vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(vl)
		var btn := Button.new()
		btn.text = "+"
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(30, 24)
		btn.add_theme_color_override("font_color", Color(0.45, 0.9, 0.55))
		var at: int = a
		btn.pressed.connect(func(): if player and player.stats_component: player.stats_component.allocate_attribute(at, 1))
		row.add_child(btn)
		stats_host.add_child(row)
		_attr_vals[a] = vl
	var respec := Button.new()
	respec.text = "Respec Attrs"
	respec.focus_mode = Control.FOCUS_NONE
	respec.pressed.connect(func(): if player and player.stats_component: player.stats_component.respec_attributes())
	stats_host.add_child(respec)
	# Refresh on stat / attribute changes.
	var sc = player.stats_component if player else null
	if sc:
		if sc.has_signal("stats_changed") and not sc.stats_changed.is_connected(_refresh_stats):
			sc.stats_changed.connect(_refresh_stats)
		if sc.has_signal("attribute_points_changed"):
			sc.attribute_points_changed.connect(func(_u): _refresh_stats())
	_refresh_stats()


func _kv_row(parent: Node, key: String) -> Label:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = key
	l.add_theme_font_override("font", FONT)
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.62, 0.62, 0.68))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var v := Label.new()
	v.text = "-"
	v.add_theme_font_override("font", FONT)
	v.add_theme_font_size_override("font_size", 11)
	v.add_theme_color_override("font_color", Color(1, 1, 1))
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	parent.add_child(row)
	return v


func _attr_name(stat_type: int) -> String:
	match stat_type:
		Constants.StatType.STRENGTH: return "STR"
		Constants.StatType.DEXTERITY: return "DEX"
		Constants.StatType.INTELLIGENCE: return "INT"
		Constants.StatType.LUCK: return "LUCK"
		Constants.StatType.CONSTITUTION: return "CON"
	return "?"


func _refresh_stats() -> void:
	if player == null or not is_instance_valid(_unspent_lbl):
		return
	var sc = player.stats_component
	if sc == null:
		return
	var S = Constants.StatType
	if "health_component" in player and player.health_component:
		_stat_rows["HP"].text = "%d/%d" % [player.health_component.current_health, player.health_component.max_health]
	if "mana_component" in player and player.mana_component:
		_stat_rows["MP"].text = "%d/%d" % [player.mana_component.current_mana, player.mana_component.max_mana]
	_stat_rows["Attack"].text = str(int(sc.stats.get(S.WEAPONATTACK).total_value))
	_stat_rows["Magic Atk"].text = str(int(sc.stats.get(S.MAGICATTACK).total_value))
	_stat_rows["Defense"].text = str(int(sc.stats.get(S.DEFENSE).total_value))
	_stat_rows["Mag Def"].text = str(int(sc.stats.get(S.MAGICDEFENSE).total_value))
	_stat_rows["Crit Rate"].text = "%d%%" % int(sc.stats.get(S.CRITCHANCE).total_value)
	_stat_rows["Crit Dmg"].text = "%d%%" % int(sc.stats.get(S.CRITDAMAGE).total_value)
	if "combat_component" in player and player.combat_component:
		_stat_rows["Dmg Range"].text = "%d ~ %d" % [player.combat_component.display_min_damage, player.combat_component.display_max_damage]
	_unspent_lbl.text = "ATTRIBUTES   —   Unspent: %d" % sc.get_attribute_points_unused()
	for a in _attr_vals:
		_attr_vals[a].text = str(sc.get_allocated_attribute(a))


func _open_to_tab(idx: int) -> void:
	visible = true
	move_to_front()
	if is_instance_valid(tab_bar):
		tab_bar.current_tab = idx
	_show_tab(idx)


func _process(_delta: float) -> void:
	if player == null or multiplayer.get_unique_id() != player.player_id:
		return
	for action in HOTKEY_TAB:
		if Input.is_action_just_pressed(action):
			var target: int = HOTKEY_TAB[action]
			if visible and tab_bar.current_tab == target:
				visible = false
			elif not InputManager.is_locked():
				_open_to_tab(target)
			break
	if _dragging:
		var p := get_global_mouse_position() - _drag_offset
		var vp := get_viewport_rect().size
		p.x = clampf(p.x, 0, vp.x - size.x)
		p.y = clampf(p.y, 0, vp.y - size.y)
		global_position = p


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed and is_instance_valid(title_label) \
				and title_label.get_global_rect().has_point(get_global_mouse_position()):
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			move_to_front()
		else:
			_dragging = false
