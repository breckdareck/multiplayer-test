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
# Economy sink: the attribute Respec button (cost label + affordability) and a
# shared confirmation dialog that warns the player of the monies cost first.
var _respec_button: Button = null
var _confirm_dialog: ConfirmationDialog = null
var _pending_respec: Callable = Callable()

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
	_bind_equipment_views()
	_show_tab(0)


# ─── Equipment slots (ADR 0009 Stage A) ──────────────────────────────────────
# The six equipment slots are authored here in game_window.tscn. Bind each to
# the player's EquipmentComponent SlotData model (push-from-UI) instead of the
# component reaching up into this scene via @export NodePaths.
const _EQUIP_SLOT_KEYS := {
	"HeadSlot": Constants.ArmorType.HEAD, "ChestSlot": Constants.ArmorType.CHEST,
	"LegsSlot": Constants.ArmorType.LEGS, "FeetSlot": Constants.ArmorType.FEET,
	"WeaponSlot": "WEAPON", "SecondaryWeaponSlot": "SECONDARY_WEAPON",
}


func _bind_equipment_views() -> void:
	if player == null or not is_instance_valid(player.equipment_component) \
			or not is_instance_valid(equip_host):
		return
	var grid := equip_host.get_node_or_null("PanelContainer/GridContainer")
	if grid == null:
		return
	var ec = player.equipment_component
	for slot_name in _EQUIP_SLOT_KEYS:
		var view := grid.get_node_or_null(slot_name)
		if view is EquipmentSlot:
			ec.bind_slot_view(_EQUIP_SLOT_KEYS[slot_name], view)


# ─── Wiring the authored stats/attribute controls ────────────────────────────
func _wire_stats_buttons() -> void:
	if not is_instance_valid(stats_root):
		return
	for row_name in _ATTR_ROWS:
		var btn := stats_root.get_node_or_null(row_name + "/Plus")
		if btn:
			var st: int = _ATTR_ROWS[row_name]
			btn.pressed.connect(func(): if player and player.stats_component: player.stats_component.allocate_attribute(st, 1))
	_respec_button = get_node_or_null("%RespecButton")
	if _respec_button:
		# Economy sink: warn (with the monies cost) before respeccing — don't just
		# silently spend on click.
		_respec_button.pressed.connect(_on_attr_respec_pressed)
	var sc = player.stats_component if player else null
	if sc:
		if sc.has_signal("stats_changed") and not sc.stats_changed.is_connected(_refresh_stats):
			sc.stats_changed.connect(_refresh_stats)
		if sc.has_signal("attribute_points_changed"):
			sc.attribute_points_changed.connect(func(_u): _refresh_stats())
	# Render the monies total + re-evaluate respec affordability when it changes.
	# (ADR 0009: the component emits monies_changed; the UI owns its own label
	# instead of the component writing into a UI NodePath.)
	if player and is_instance_valid(player.player_inventory) and player.player_inventory.has_signal("monies_changed"):
		if not player.player_inventory.monies_changed.is_connected(_on_monies_changed):
			player.player_inventory.monies_changed.connect(_on_monies_changed)
	_update_attr_respec_button()
	_refresh_monies()


# ─── Economy: attribute respec cost label + warning dialog ───────────────────
func _update_attr_respec_button() -> void:
	if not is_instance_valid(_respec_button) or player == null or player.stats_component == null:
		return
	var sc = player.stats_component
	var cost: int = sc.get_attribute_respec_cost() if sc.has_method("get_attribute_respec_cost") else 0
	_respec_button.text = "Respec Attributes (%s)" % _fmt_monies(cost)
	var spent: int = sc.get_attribute_points_spent() if sc.has_method("get_attribute_points_spent") else 1
	_respec_button.disabled = (spent <= 0) or (_player_monies() < cost)


func _on_attr_respec_pressed() -> void:
	if player == null or player.stats_component == null:
		return
	var sc = player.stats_component
	var cost: int = sc.get_attribute_respec_cost() if sc.has_method("get_attribute_respec_cost") else 0
	_confirm_respec("Respec ALL attributes for %s monies?\nYou have %s." % [_fmt_monies(cost), _fmt_monies(_player_monies())],
		func(): if player and player.stats_component: player.stats_component.respec_attributes())


## Shared confirmation: shows `text` (incl. the cost) and runs `on_confirm` on OK.
func _confirm_respec(text: String, on_confirm: Callable) -> void:
	_pending_respec = on_confirm
	if not is_instance_valid(_confirm_dialog):
		_confirm_dialog = ConfirmationDialog.new()
		_confirm_dialog.title = "Confirm Respec"
		_confirm_dialog.ok_button_text = "Respec"
		add_child(_confirm_dialog)
		_confirm_dialog.confirmed.connect(_on_respec_confirmed)
	_confirm_dialog.dialog_text = text
	_confirm_dialog.popup_centered()


func _on_respec_confirmed() -> void:
	if _pending_respec.is_valid():
		_pending_respec.call()
	_pending_respec = Callable()


## Monies changed on the component → repaint the count label + respec affordability.
func _on_monies_changed(_new_amount: int) -> void:
	_refresh_monies()
	_update_attr_respec_button()


## Paint the authored MoniesCountLabel from the component's current total.
func _refresh_monies() -> void:
	var lbl: Label = get_node_or_null("%MoniesCountLabel")
	if is_instance_valid(lbl):
		lbl.text = _fmt_monies(_player_monies())


func _player_monies() -> int:
	if player and is_instance_valid(player.player_inventory):
		return player.player_inventory.monies_amount
	return 0


func _fmt_monies(amount: int) -> String:
	if player and is_instance_valid(player.player_inventory) and player.player_inventory.inventory_component:
		return player.player_inventory.inventory_component.format_number_with_commas(amount)
	return str(amount)


# ─── Tabs ────────────────────────────────────────────────────────────────────
func _on_tab_changed(idx: int) -> void:
	_show_tab(idx)


func _show_tab(idx: int) -> void:
	if is_instance_valid(character_page):
		character_page.visible = idx == 0
	if is_instance_valid(abilities_page):
		abilities_page.visible = idx == 1
	if idx == 1 and _ability_shell:
		# The skill tree is in the `ui_window` group, so player_hud's ESC/death
		# "close all windows" flips its OWN `visible` off (even while it sits on the
		# hidden Character page). The hub owns the page, so re-assert its visibility
		# here — otherwise switching back to Abilities shows a blank page.
		if _ability_shell is CanvasItem:
			(_ability_shell as CanvasItem).visible = true
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
	_update_attr_respec_button()
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
	# PR 18: Accuracy = ACCURACY stat + DEX utility (StatsComponent.DEX_TO_ACCURACY
	# % per DEX point — invisible until now). Evasion = EVASIONCHANCE stat raw.
	var acc_stat: float = 0.0
	if sc.stats.has(S.ACCURACY):
		acc_stat = float(sc.stats[S.ACCURACY].total_value)
	var dex_bonus: float = float(sc.stats.get(S.DEXTERITY).total_value) * StatsComponent.DEX_TO_ACCURACY
	_set_row("AccRow", "%.1f%%" % (acc_stat + dex_bonus))
	var eva_stat: float = 0.0
	if sc.stats.has(S.EVASIONCHANCE):
		eva_stat = float(sc.stats[S.EVASIONCHANCE].total_value)
	_set_row("EvaRow", "%.1f%%" % eva_stat)
	if "combat_component" in player and player.combat_component:
		_set_row("DmgRangeRow", "%d ~ %d" % [player.combat_component.display_min_damage, player.combat_component.display_max_damage])
	var unspent := get_node_or_null("%UnspentLabel") as Label
	if unspent:
		unspent.text = "ATTRIBUTES   —   Unspent: %d" % sc.get_attribute_points_unused()
	# Show the OVERALL total (base + allocated + mastery + gear + buffs), with the
	# points the player invested shown in parens so both are visible at a glance.
	for row_name in _ATTR_ROWS:
		var v := stats_root.get_node_or_null(row_name + "/V") as Label
		if v:
			var st: int = _ATTR_ROWS[row_name]
			var total: int = int(sc.stats.get(st).total_value)
			var alloc: int = sc.get_allocated_attribute(st)
			v.text = "%d  (+%d)" % [total, alloc] if alloc > 0 else str(total)


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
