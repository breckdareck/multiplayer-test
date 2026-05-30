extends Panel

## Unified game hub (ADR 0003). Reparents the existing standalone windows into a
## tabbed hub at runtime:
##   Character tab = Equipment | Stats | Inventory (3 columns; pet stays embedded
##                   in the equipment window's own Equipment/Pets toggle)
##   Abilities tab = the v2 skill tree window
## Each absorbed window keeps its own script/logic + LIVE component references (the
## components hold node-reference @exports that survive reparenting — no NodePath
## edits needed). The hub suppresses each window's chrome (title/close/drag) and
## stops its per-frame hotkey poll, providing ONE chrome + hotkey set + tabs.
## Non-modal: movable, never locks input. Path-resolved (no class_name).

@onready var title_label: Label = %HubTitle
@onready var tab_bar: TabBar = %HubTabBar
@onready var character_page: HBoxContainer = %CharacterPage
@onready var abilities_page: Control = %AbilitiesPage
@onready var close_button: Button = %HubCloseButton

var player
var _absorbed := false
var _dragging := false
var _drag_offset := Vector2()

# Old window node name -> which page it joins.
const CHAR_WINDOWS := ["EquipmentWindow", "StatsWindow", "InventoryWindow"]
const ABIL_WINDOW := "AbilityWindow"
# Hotkey -> tab index (0 = Character, 1 = Abilities).
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
	for wname in CHAR_WINDOWS:
		_absorb(src.get_node_or_null(wname), character_page)
	_absorb(src.get_node_or_null(ABIL_WINDOW), abilities_page)
	_absorbed = true
	_show_tab(0)


## Reparents one window into `page`, stops its input, and flattens its chrome.
func _absorb(w: Node, page: Node) -> void:
	if w == null or page == null or not is_instance_valid(w):
		return
	# Stop the window's own hotkey poll + drag (its _process / input handlers).
	w.set_process(false)
	w.set_process_input(false)
	w.set_process_unhandled_input(false)
	# Flatten its outer panel so the hub's chrome is the only frame.
	if w is Control:
		(w as Control).add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_hide_chrome(w)
	# Reparent into the page; let the container size it.
	if w.get_parent():
		w.get_parent().remove_child(w)
	page.add_child(w)
	if w is Control:
		var c := w as Control
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.position = Vector2.ZERO
		c.visible = true


## Hides a window's own title bar + close button (the hub provides them). The
## title is the direct-child Label used as its drag handle; close is "CloseButton".
func _hide_chrome(w: Node) -> void:
	for child in w.get_children():
		if child is Label and child.name == "Label":
			child.visible = false
		elif child.name == "CloseButton":
			child.visible = false
	# Some windows (Equipment) keep the close button deeper; hide any found.
	var cb := w.find_child("CloseButton", true, false)
	if cb is CanvasItem:
		(cb as CanvasItem).visible = false


func _on_tab_changed(idx: int) -> void:
	_show_tab(idx)


func _show_tab(idx: int) -> void:
	if is_instance_valid(character_page):
		character_page.visible = idx == 0
	if is_instance_valid(abilities_page):
		abilities_page.visible = idx == 1
	# The ability window refreshes its tree on its own open; trigger it on tab show.
	if idx == 1 and is_instance_valid(abilities_page):
		var aw := abilities_page.get_node_or_null(ABIL_WINDOW)
		if aw and aw.has_method("load_ability_list"):
			aw.call("load_ability_list")


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
