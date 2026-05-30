extends Panel

## Unified game hub (ADR 0003). The LAYOUT lives in game_window.tscn (editable in
## the Godot editor): the tabbed frame, the 3 Character columns, the character
## header card, and the full STATS panel (derived rows + ATTRIBUTES + buttons) are
## all authored nodes. This script only:
##   - fills those authored nodes with live values + wires their buttons, and
##   - reparents the live component-bound content (equipment slots, inventory grid,
##     pet panel, skill tree) from the existing windows into the column hosts at
##     runtime (those can't be authored here — they belong to their own scenes:
##     equipment_window / inventory_window / abilities_window).
## Non-modal: movable, never locks input. Path-resolved (no class_name).

@onready var title_label: Label = %HubTitle
@onready var tab_bar: TabBar = %HubTabBar
@onready var character_page: Control = %CharacterPage
@onready var abilities_page: Control = %AbilitiesPage
@onready var equip_host: Control = %EquipHost
@onready var inv_host: Control = %InvHost
@onready var abil_host: Control = %AbilHost
@onready var stats_root: Control = %Stats
@onready var close_button: Button = %HubCloseButton

var player
var _absorbed := false
var _dragging := false
var _drag_offset := Vector2()
var _ability_shell: Node = null

const _DISC_NAMES := ["Sword", "Bow", "Staff", "Dagger"]
# Attribute row name (in %Stats) -> StatType.
const _ATTR_ROWS := {
	"StrRow": Constants.StatType.STRENGTH, "DexRow": Constants.StatType.DEXTERITY,
	"IntRow": Constants.StatType.INTELLIGENCE, "LuckRow": Constants.StatType.LUCK,
	"ConRow": Constants.StatType.CONSTITUTION,
}
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
	_wire_stats_buttons()
	call_deferred("_absorb_windows")


# ─── Wiring the authored stats/attribute controls ────────────────────────────
func _wire_stats_buttons() -> void:
	if not is_instance_valid(stats_root):
		return
	for row_name in _ATTR_ROWS:
		var btn := stats_root.get_node_or_null(row_name + "/Plus")
		if btn:
			var st: int = _ATTR_ROWS[row_name]
			btn.pressed.connect(func(): if player and player.stats_component: player.stats_component.allocate_attribute(st, 1))
	var respec := get_node_or_null("%RespecButton")
	if respec:
		respec.pressed.connect(func(): if player and player.stats_component: player.stats_component.respec_attributes())
	var sc = player.stats_component if player else null
	if sc:
		if sc.has_signal("stats_changed") and not sc.stats_changed.is_connected(_refresh_stats):
			sc.stats_changed.connect(_refresh_stats)
		if sc.has_signal("attribute_points_changed"):
			sc.attribute_points_changed.connect(func(_u): _refresh_stats())


# ─── Reparent live content from the existing windows ─────────────────────────
func _absorb_windows() -> void:
	if _absorbed:
		return
	var src := get_parent()  # CanvasLayer/MoveableWindows
	if src == null:
		return
	var eqw := src.get_node_or_null("EquipmentWindow")
	_absorb(eqw, equip_host)
	if eqw:
		# Mock = no Equipment/Pets toggle: show gear AND pet together (pet under gear).
		var toggle := equip_host.find_child("TabButtons", true, false)
		if toggle is CanvasItem:
			(toggle as CanvasItem).visible = false
		if "equipment_panel" in eqw and is_instance_valid(eqw.equipment_panel):
			var ep := eqw.equipment_panel as Control
			ep.visible = true
			ep.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		if "pet_tab_content" in eqw and is_instance_valid(eqw.pet_tab_content):
			var pc := eqw.pet_tab_content as Control
			pc.visible = true
			pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
			var roster := pc.find_child("ListPanel", true, false)
			if roster is CanvasItem:
				(roster as CanvasItem).visible = false
	var grid := equip_host.find_child("GridContainer", true, false)
	if grid is GridContainer:
		(grid as GridContainer).columns = 2
	# Stats: the panel is authored; just disable the old stats window shell.
	var sw := src.get_node_or_null("StatsWindow")
	if sw:
		sw.set_process(false)
		sw.set_process_input(false)
		if sw is CanvasItem:
			(sw as CanvasItem).visible = false
	_absorb(src.get_node_or_null("InventoryWindow"), inv_host)
	for g in inv_host.find_children("", "GridContainer", true, false):
		(g as GridContainer).columns = 6
	_ability_shell = src.get_node_or_null("AbilityWindow")
	_absorb(_ability_shell, abil_host)
	_absorbed = true
	_show_tab(0)


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
	_hide_named(host, ["CloseButton", "TitleLabel"])
	if w is CanvasItem:
		(w as CanvasItem).visible = false


func _is_big(c: Control) -> bool:
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


# ─── Tabs ────────────────────────────────────────────────────────────────────
func _on_tab_changed(idx: int) -> void:
	_show_tab(idx)


func _show_tab(idx: int) -> void:
	if is_instance_valid(character_page):
		character_page.visible = idx == 0
	if is_instance_valid(abilities_page):
		abilities_page.visible = idx == 1
	if idx == 1 and _ability_shell and _ability_shell.has_method("load_ability_list"):
		_ability_shell.call("load_ability_list")
	if idx == 0:
		_refresh_header()
		_refresh_stats()


func _open_to_tab(idx: int) -> void:
	visible = true
	move_to_front()
	if is_instance_valid(tab_bar):
		tab_bar.current_tab = idx
	_show_tab(idx)


# ─── Fill the authored header + stats with live values ───────────────────────
func _refresh_header() -> void:
	var hn := get_node_or_null("%HdrName") as Label
	var hs := get_node_or_null("%HdrSub") as Label
	if player == null or hn == null:
		return
	hn.text = str(player.username) if "username" in player else "Player"
	var lvl: int = 0
	if "level_component" in player and player.level_component:
		lvl = int(player.level_component.level)
	var cls := ""
	if player.has_method("get_active_discipline"):
		var d: int = player.get_active_discipline()
		if d >= 0 and d < _DISC_NAMES.size():
			cls = _DISC_NAMES[d]
	if hs:
		hs.text = "Lv %d   %s" % [lvl, cls]
	if is_instance_valid(title_label):
		title_label.text = "CHARACTER   ·   %s   Lv %d   %s" % [hn.text, lvl, cls]


func _refresh_stats() -> void:
	if player == null or not is_instance_valid(stats_root):
		return
	var sc = player.stats_component
	if sc == null:
		return
	var S = Constants.StatType
	if "health_component" in player and player.health_component:
		_set_row("HpRow", "%d/%d" % [player.health_component.current_health, player.health_component.max_health])
	if "mana_component" in player and player.mana_component:
		_set_row("MpRow", "%d/%d" % [player.mana_component.current_mana, player.mana_component.max_mana])
	_set_row("AtkRow", str(int(sc.stats.get(S.WEAPONATTACK).total_value)))
	_set_row("MAtkRow", str(int(sc.stats.get(S.MAGICATTACK).total_value)))
	_set_row("DefRow", str(int(sc.stats.get(S.DEFENSE).total_value)))
	_set_row("MDefRow", str(int(sc.stats.get(S.MAGICDEFENSE).total_value)))
	_set_row("CritRateRow", "%d%%" % int(sc.stats.get(S.CRITCHANCE).total_value))
	_set_row("CritDmgRow", "%d%%" % int(sc.stats.get(S.CRITDAMAGE).total_value))
	if "combat_component" in player and player.combat_component:
		_set_row("DmgRangeRow", "%d ~ %d" % [player.combat_component.display_min_damage, player.combat_component.display_max_damage])
	var unspent := get_node_or_null("%UnspentLabel") as Label
	if unspent:
		unspent.text = "ATTRIBUTES   —   Unspent: %d" % sc.get_attribute_points_unused()
	for row_name in _ATTR_ROWS:
		var v := stats_root.get_node_or_null(row_name + "/V") as Label
		if v:
			v.text = str(sc.get_allocated_attribute(_ATTR_ROWS[row_name]))


func _set_row(row_name: String, txt: String) -> void:
	var v := stats_root.get_node_or_null(row_name + "/V") as Label
	if v:
		v.text = txt


# ─── Window chrome ───────────────────────────────────────────────────────────
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
