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

var player
var _absorbed := false
var _dragging := false
var _drag_offset := Vector2()
var _ability_shell: Node = null

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
	# Default the embedded Equipment/Pets toggle to the gear view (the generic
	# absorb force-shows every moved child, which would reveal both at once).
	if eqw and eqw.has_method("_show_equipment_tab"):
		eqw.call("_show_equipment_tab")
	# Lay the 6 equipment slots out 2-wide (mock paperdoll) instead of a 1-col strip,
	# and top-align the panel (don't let it expand-fill and float the slots centered).
	var grid := equip_host.find_child("GridContainer", true, false)
	if grid is GridContainer:
		(grid as GridContainer).columns = 2
	if eqw and "equipment_panel" in eqw and is_instance_valid(eqw.equipment_panel):
		(eqw.equipment_panel as Control).size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_absorb(src.get_node_or_null("StatsWindow"), stats_host)
	_absorb(src.get_node_or_null("InventoryWindow"), inv_host)
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
