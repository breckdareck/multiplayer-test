extends Panel

## Unified game hub (ADR 0003). The ENTIRE layout lives in game_window.tscn and is
## editable in the Godot editor: the tabbed frame, the 3 Character columns, the
## header card, the full STATS panel, the equipment grid + pet panel, and the
## inventory tabs/slots/monies are all NATIVE authored nodes. (The Abilities tab
## hosts the skill tree as an instanced sub-scene — abilities_window.tscn — since
## it builds its tree procedurally.)
##
## This script is a THIN controller (same shape as game_menu.gd): it only fills
## authored nodes with live values and wires their signals. It does NOT build or
## reparent any UI. The equipment slots / inventory grids / monies are driven by
## the player's components via @export NodePaths (player.tscn) that point straight
## at these native nodes. Non-modal: movable, never locks input.

@onready var title_label: Label = %HubTitle
@onready var tab_bar: TabBar = %HubTabBar
@onready var character_page: Control = %CharacterPage
@onready var abilities_page: Control = %AbilitiesPage
@onready var stats_root: Control = %Stats
@onready var close_button: Button = %HubCloseButton
@onready var abil_host: Control = %AbilHost
@onready var equip_host: Control = %EquipHost

var player
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
	# Skill tree (instanced sub-scene) — refreshed on the Abilities tab.
	_ability_shell = abil_host.get_node_or_null("AbilityWindow") if is_instance_valid(abil_host) else null
	# Pet panel is native here, but its controller wants the player ref (it can't
	# resolve via `owner`, which is the hub). Inject it like equipment_window did.
	var pet := equip_host.get_node_or_null("PetTabContent/PetTab") if is_instance_valid(equip_host) else null
	if pet and pet.has_method("set_owner_player"):
		pet.set_owner_player(player)
	_show_tab(0)


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


# ─── Tabs ────────────────────────────────────────────────────────────────────
func _on_tab_changed(idx: int) -> void:
	_show_tab(idx)


func _show_tab(idx: int) -> void:
	if is_instance_valid(character_page):
		character_page.visible = idx == 0
	if is_instance_valid(abilities_page):
		abilities_page.visible = idx == 1
	if idx == 1 and _ability_shell:
		if _ability_shell.has_method("on_shown"):
			_ability_shell.call("on_shown")
		elif _ability_shell.has_method("load_ability_list"):
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
