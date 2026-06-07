@tool
class_name ResourceEditorGUI
extends Control

const ResourceTypeConfig = preload("res://addons/resource_editor/resource_type_config.gd")

# ── Color palette ──────────────────────────────────────────────────────────────
const C_DARK   = Color(0.11, 0.12, 0.15)
const C_CARD   = Color(0.15, 0.16, 0.19)
const C_BORDER = Color(0.22, 0.24, 0.30)
const C_DIM    = Color(0.50, 0.53, 0.60)
const C_TEXT   = Color(0.88, 0.88, 0.90)
const C_OK     = Color(0.42, 0.85, 0.52)
const C_ERR    = Color(1.00, 0.35, 0.35)

# Per-category accent colors
const CATEGORY_COLORS: Dictionary = {
	"Ability System": Color(0.75, 0.48, 1.00),   # purple
	"Item System":    Color(1.00, 0.82, 0.28),   # gold
	"Buff System":    Color(0.42, 0.85, 0.52),   # green
	"Class System":   Color(0.30, 0.85, 0.78),   # teal
	"Enemy System":   Color(0.90, 0.35, 0.35),   # red
	"Quest System":   Color(1.00, 0.60, 0.20),   # orange
}

# Per-type icons shown in the browser tree
const TYPE_ICONS: Dictionary = {
	"Abilities":   "⚡",
	"Items":       "◈",
	"Weapons":     "⚔",
	"Armor":       "🛡",
	"Consumables": "🧪",
	"Buffs":       "✦",
	"Disciplines": "★",
	"Enemies":     "☠",
	"Quests":      "📜",
	"VFX Effects": "✨",
	"Ability Upgrades": "⬆",
}

# ── @onready refs (paths must match ResourceEditorGUI.tscn exactly) ────────────
@onready var resource_type_selector = $Panel/MainHSplit/ResourceBrowser/ResourceTypeSelector
@onready var search_edit            = $Panel/MainHSplit/ResourceBrowser/SearchEdit
@onready var refresh_button         = $Panel/MainHSplit/ResourceBrowser/RefreshButton
@onready var resource_tree          = $Panel/MainHSplit/ResourceBrowser/ResourceTree

@onready var general_settings_panel = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings

@onready var ability_id_edit       = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_ID/AbilityIDEdit
@onready var ability_name_edit     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Name/AbilityNameEdit
@onready var description_edit      = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Desc/DescriptionEdit
@onready var icon_path_picker      = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Icon/IconPathPicker
@onready var max_level_spinbox     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_MaxLevel/MaxLevelSpinBox
@onready var ability_type_option   = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Type/AbilityTypeOption
@onready var required_class_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Class/RequiredClassOption
@onready var required_weapon_option= $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GeneralSettings/MarginContainer/Form/HBox_Weapon/RequiredWeaponOption

@onready var active_behavior_panel    = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior
@onready var active_behavior_inspector= $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/ContentVBox/ActiveBehaviorInspector

@onready var formula_editor_panel  = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor
@onready var formula_tree          = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HSplit/FormulaTree
@onready var formula_inspector     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HSplit/FormulaInspector
@onready var add_formula_button    = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HeaderButtons/AddFormulaButton
@onready var formula_help_button   = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HeaderButtons/HelpButton
@onready var formula_preset_option = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/FormulaEditor/HeaderButtons/PresetOption

# Quest editor refs
@onready var quest_editor_panel        = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor
@onready var quest_id_edit             = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_QuestID/QuestIDEdit
@onready var quest_name_edit           = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_QuestName/QuestNameEdit
@onready var quest_description_edit    = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_Desc/QuestDescriptionEdit
@onready var quest_required_level_spin = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_Level/RequiredLevelSpinBox
@onready var quest_prereq_option       = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_Prereq/PrereqQuestOption
@onready var quest_npc_only_check      = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_Flags/NpcOnlyCheck
@onready var quest_sort_order_spin     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/HBox_SortOrder/SortOrderSpinBox
@onready var quest_objectives_list     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/ObjectivesSection/ObjectivesList
@onready var quest_add_objective_btn   = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/ObjectivesSection/ObjectivesHeader/AddObjectiveButton
@onready var quest_reward_exp_spin     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/RewardsSection/HBox_RewardExp/RewardExpSpinBox
@onready var quest_reward_coins_spin   = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/RewardsSection/HBox_RewardCoins/RewardCoinsSpinBox
@onready var quest_reward_items_edit   = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/QuestEditor/MarginContainer/Form/RewardsSection/HBox_RewardItems/RewardItemsEdit

@onready var generic_resource_inspector = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/GenericResourceInspector

@onready var new_button       = $Panel/MainHSplit/EditorPanel/Header/FileButtons/NewButton
@onready var save_button      = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveButton
@onready var save_as_button   = $Panel/MainHSplit/EditorPanel/Header/FileButtons/SaveAsButton
@onready var duplicate_button = $Panel/MainHSplit/EditorPanel/Header/FileButtons/DuplicateButton
@onready var delete_button    = $Panel/MainHSplit/EditorPanel/Header/FileButtons/DeleteButton
@onready var preview_button   = $Panel/MainHSplit/EditorPanel/Header/FileButtons/PreviewButton
@onready var file_dialog      = $FileDialog

@onready var visualizer_container     = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/ContentVBox/VisualizerContainer
@onready var visualizer_control       = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/ContentVBox/VisualizerContainer/PanelContainer/VisualizerControl
@onready var visualizer_player_sprite = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent/ActiveBehavior/MarginContainer/ContentVBox/VisualizerContainer/PanelContainer/VisualizerControl/PlayerSprite

# ── Member vars ────────────────────────────────────────────────────────────────
var resource_types: Array[ResourceTypeConfig.ResourceType] = []
var current_resource_type: ResourceTypeConfig.ResourceType
var current_resource: Resource
var current_scaling_data: AbilityScalingData
var is_updating_ui: bool = false
var selected_formula_key: String = ""
var current_editing_formula: AbilityScalingFormula = null

# VFX override section (built programmatically below the ActiveBehavior inspector).
# Lets the user see which cast/hit effect an ability resolves to (VfxCatalog) and
# override it per ability via ActiveBehaviorData.cast_vfx / hit_vfx, with a live
# looping preview of each.
var _vfx_section: VBoxContainer = null
var _vfx_cast_option: OptionButton = null
var _vfx_hit_option: OptionButton = null
var _vfx_resolved_label: Label = null
var _vfx_cast_preview: AnimatedSprite2D = null
var _vfx_hit_preview: AnimatedSprite2D = null

# Upgrade-tree editor (built programmatically, inserted after the Formula card).
# Shown for AbilityData of either type; manages the ability's external upgrade
# .tres files + ext_resource refs. See upgrade_tree_editor.gd + ADR 0010.
var _upgrade_editor: UpgradeTreeEditor = null
var _upgrade_card: PanelContainer = null

# Multi-select replacements for the required_class / required_weapon dropdowns.
# AbilityData stores these as Array[...]; the old single OptionButtons silently
# truncated to index 0 on save. These MenuButtons edit the FULL arrays.
var _req_class_menu: MenuButton = null
var _req_weapon_menu: MenuButton = null

# ability_id -> ability_name, lazily filled by _scan_all_abilities() (used to
# label ability-damage-modifier formula rows by the ability they target).
var _ability_name_cache: Dictionary = {}

# Advanced ability fields (built programmatically; previously only reachable via
# the generic inspector, which the dock hides for abilities). damage_stat,
# skill-tree placement, applies_buff / applies_target_debuff, prerequisites.
var _adv_card: PanelContainer = null
var _adv_damage_stat: OptionButton = null
var _adv_tree_path: OptionButton = null
var _adv_tree_depth: SpinBox = null
var _adv_buff_picker: EditorResourcePicker = null
var _adv_debuff_picker: EditorResourcePicker = null
var _adv_prereq_host: VBoxContainer = null

# Discipline skill-tree placement board (separate Window, opened from a header
# button). See discipline_board.gd.
var _board_window: DisciplineBoard = null
var _board_button: Button = null

# Validation dashboard (separate Window). See validation_dashboard.gd.
var _validation_window: ValidationDashboard = null
# Batch edit (separate Window). See batch_edit.gd.
var _batch_window: BatchEditWindow = null

# Cross-resource "Related" panel + lazily-built reverse-reference index.
var _related_card: PanelContainer = null
var _related_host: VBoxContainer = null
var _rel_index_built: bool = false
var _rel_upgrade_to_ability: Dictionary = {}   # upgrade .tres path -> ability path
var _rel_weapon_to_abilities: Dictionary = {}  # WeaponType int -> [ability path]
var _rel_buff_to_abilities: Dictionary = {}    # buff .tres path -> [ability path]

# Live preview for the VFX Effects resource type (a VfxEffectData .tres). Built
# once, shown only while editing that type; rebuilds as the inspector fields
# change so tuning fps/scale/tint/sheet is visible immediately.
var _vfx_effect_panel: PanelContainer = null
var _vfx_effect_sprite: AnimatedSprite2D = null
var _vfx_effect_info: Label = null
var _vfx_effect_stage: Control = null
var _vfx_effect_char: Sprite2D = null  # faint character reference in the preview
var _vfx_dragging: bool = false  # dragging the preview effect to set its offset
var _vfx_anchor_screen: Vector2 = Vector2.ZERO  # screen pos of the offset=0 anchor
var _vfx_preview_zoom: float = 3.5              # world px -> preview px (wheel/buttons)
var _vfx_preview_pan: Vector2 = Vector2.ZERO    # middle-drag pan of the view
var _vfx_panning: bool = false
var _vfx_zoom_label: Label = null

# VFX overlay inside the ability hitbox visualizer: the resolved CAST effect on
# the player body and the HIT effect at the hitbox center, so placement/offset
# can be judged against the character + hitbox.
var _vis_cast_vfx: AnimatedSprite2D = null
var _vis_hit_vfx: AnimatedSprite2D = null
var _vis_show_vfx: bool = true
## Player body-center anchor for cast VFX in the visualizer, in world units
## relative to the player origin (feet). Mirrors ability.gd's _VFX_CAST_BODY_OFFSET.
const _VIS_CAST_BODY_OFFSET := Vector2(0, -18)
## Default/min/max preview zoom (world px -> preview px). The preview mirrors the
## in-game cast frame: character FEET are the origin, the cast anchor is feet +
## _VIS_CAST_BODY_OFFSET, and the effect sits at (anchor + offset) * zoom — so an
## offset dialled in here equals the in-game offset exactly, just magnified.
const _VFX_PREVIEW_DEFAULT_ZOOM: float = 3.5
const _VFX_PREVIEW_MIN_ZOOM: float = 0.5
const _VFX_PREVIEW_MAX_ZOOM: float = 16.0
## How far above the stage bottom the character's FEET sit (before pan).
const _VFX_PREVIEW_FEET_MARGIN: float = 30.0

# Theme state – kept as refs so _update_accent() can mutate them in place
var _title_label:       Label          = null
var _status_label:      Label          = null
var _tree_panel_sb:     StyleBoxFlat   = null
var _tree_selected_sb:  StyleBoxFlat   = null
var _ftree_panel_sb:    StyleBoxFlat   = null
var _ftree_selected_sb: StyleBoxFlat   = null
var _current_accent:    Color          = CATEGORY_COLORS["Ability System"]

# Search / cache / dirty / dialog state
var _search_filter: String = ""
var _scanned_entries: Array = [] # [{path, res, folder_parts, name}]
var _path_to_tree_item: Dictionary = {} # res_path -> TreeItem
var _status_version: int = 0
var _dirty: bool = false
var _pending_action: Callable = Callable() # queued action to run after dirty confirm
var _help_dialog: AcceptDialog = null
var _popup_body_label: Label = null
var _confirm_delete_dialog: ConfirmationDialog = null
var _unsaved_dialog: ConfirmationDialog = null

# Theming registries (drained when accent changes)
var _accent_appliers: Array = []      # Array of Callable(Color) -> void
var _section_labels: Array = []        # Label refs (kept after card wrap)
var _section_label_meta: Array = []    # Matching text for each label
var _status_count_label: Label = null  # right-aligned resource count in status bar
var _status_type_chip: Label = null    # left chip showing current type icon
var _browser_count_label: Label = null # under search bar, shows result counts

# Tree right-click context menu
var _tree_context_menu: PopupMenu = null
var _tree_context_path: String = ""
enum _CtxAction { OPEN, DUPLICATE, DELETE, REVEAL, COPY_ID, COPY_PATH }

# Empty-state placeholder (a card shown above the tree when no resources exist)
var _empty_state_panel: PanelContainer = null
var _empty_state_label: Label = null

# Collapsible section state — keyed by SectionLabel
var _section_bodies: Dictionary = {}    # Label -> Array[Control]
var _section_collapsed: Dictionary = {} # Label -> bool

# Persisted dock state key
const _STATE_KEY = "resource_editor/last_state"

# Formula curve chart
var _curve_chart: Control = null

var formula_presets = {
	"Linear +1/level":  {"type": AbilityScalingFormula.ScalingType.FLAT,          "base": 0,   "per_level": 1.0},
	"Linear +5/level":  {"type": AbilityScalingFormula.ScalingType.FLAT,          "base": 0,   "per_level": 5.0},
	"100 + 10/level":   {"type": AbilityScalingFormula.ScalingType.FLAT,          "base": 100, "per_level": 10.0},
	"Exponential 10%":  {"type": AbilityScalingFormula.ScalingType.MULTIPLICATIVE,"base": 100, "mult": 1.1},
	"Exponential 20%":  {"type": AbilityScalingFormula.ScalingType.MULTIPLICATIVE,"base": 100, "mult": 1.2},
}

# ── Lifecycle ──────────────────────────────────────────────────────────────────
func _ready() -> void:
	_apply_base_theme()
	_add_status_bar()
	_load_resource_types()
	_populate_option_buttons()
	_build_required_multiselects()
	_populate_formula_presets()
	_connect_signals()
	if resource_types.size() > 0:
		# Try to restore the last session's selection first
		if not _restore_dock_state():
			current_resource_type = resource_types[0]
			_update_accent(CATEGORY_COLORS.get(current_resource_type.category, C_DIM))
			_scan_for_resources()
			_on_new_button_pressed()


# ── Base theme (called once in _ready after @onready resolution) ───────────────
func _apply_base_theme() -> void:
	# Root panel: dark background, shrunk to leave 26 px for status bar
	var panel = $Panel
	var root_sb = StyleBoxFlat.new()
	root_sb.bg_color = C_DARK
	panel.add_theme_stylebox_override("panel", root_sb)
	panel.offset_bottom = -26

	$Panel/MainHSplit.add_theme_constant_override("separation", 10)
	$Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent.add_theme_constant_override("separation", 16)
	$Panel/MainHSplit/ResourceBrowser.add_theme_constant_override("separation", 6)
	$Panel/MainHSplit/EditorPanel/Header.add_theme_constant_override("separation", 8)
	$Panel/MainHSplit/EditorPanel.add_theme_constant_override("separation", 10)

	# ── Browser header ─────────────────────────────────────────────────────
	var browser_lbl = $Panel/MainHSplit/ResourceBrowser/Label
	browser_lbl.text = "PROJECT RESOURCES"
	browser_lbl.add_theme_font_size_override("font_size", 11)
	browser_lbl.add_theme_color_override("font_color", C_DIM)

	# Title — larger now that we have a chip-style breadcrumb beside it
	_title_label = $Panel/MainHSplit/EditorPanel/Header/Title
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", _current_accent)

	# Themed tree styleboxes (these vars persist so _update_accent mutates them in place)
	_tree_panel_sb = _make_tree_panel_sb()
	resource_tree.add_theme_stylebox_override("panel", _tree_panel_sb)
	_tree_selected_sb = _make_tree_selected_sb()
	resource_tree.add_theme_stylebox_override("selected",       _tree_selected_sb)
	resource_tree.add_theme_stylebox_override("selected_focus", _tree_selected_sb)
	resource_tree.add_theme_color_override("font_color",          C_TEXT)
	resource_tree.add_theme_color_override("font_color_selected", Color.WHITE)
	resource_tree.add_theme_color_override("guide_color",         Color(C_BORDER, 0.5))
	resource_tree.add_theme_constant_override("item_margin", 6)
	resource_tree.add_theme_constant_override("v_separation", 3)

	_ftree_panel_sb = _make_tree_panel_sb()
	formula_tree.add_theme_stylebox_override("panel", _ftree_panel_sb)
	_ftree_selected_sb = _make_tree_selected_sb()
	formula_tree.add_theme_stylebox_override("selected",       _ftree_selected_sb)
	formula_tree.add_theme_stylebox_override("selected_focus", _ftree_selected_sb)
	formula_tree.add_theme_color_override("font_color",          C_TEXT)
	formula_tree.add_theme_color_override("font_color_selected", Color.WHITE)
	formula_tree.add_theme_constant_override("item_margin", 6)
	formula_tree.add_theme_constant_override("v_separation", 3)

	# Card-wrap each major section in the editor panel
	_wrap_sections_in_cards()

	# Build the advanced-fields card (after GeneralSettings) and the upgrade-tree
	# editor card (after the Formula card).
	_build_advanced_section()
	_build_upgrade_section()
	_build_related_section()
	_build_board_button()

	# Style all input controls with accent focus borders
	_polish_inputs()

	# Section headers — call AFTER wrap so we can cache the labels
	_cache_section_labels()
	_restyle_section_labels(_current_accent)
	_add_section_dividers()
	_create_curve_chart()
	_make_sections_collapsible()

	# File buttons & helper buttons
	_style_btn(refresh_button, C_DIM, false)
	_style_btn(new_button,      C_DIM,          false)
	_style_btn(save_button,     _current_accent, true)
	_style_btn(save_as_button,  C_DIM,          false)
	_style_btn(duplicate_button, C_DIM,         false)
	_style_btn(delete_button,   C_ERR,          false)
	_style_btn(preview_button,  C_DIM,          false)
	_style_btn(add_formula_button, C_DIM,        false)
	_style_btn(formula_help_button, C_DIM,       false)

	_apply_button_icons()
	_polish_visualizer_panel()


# ── Card wrapping ──────────────────────────────────────────────────────────────
func _wrap_sections_in_cards() -> void:
	# Existing section VBoxes get hoisted into a PanelContainer with a rounded
	# card stylebox + left-accent stripe. @onready refs are by node reference,
	# not path, so re-parenting here doesn't break them.
	for section_name in ["GeneralSettings", "ActiveBehavior", "FormulaEditor", "QuestEditor", "GenericResourceInspector"]:
		var section = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent.get_node_or_null(section_name)
		if section:
			_wrap_in_card(section)


func _wrap_in_card(section: Control) -> void:
	var parent = section.get_parent()
	var idx = section.get_index()

	var card = PanelContainer.new()
	card.name = section.name + "Card"
	card.size_flags_horizontal = section.size_flags_horizontal if section.size_flags_horizontal != 0 else Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = section.size_flags_vertical
	card.visible = section.visible  # mirror initial visibility (e.g. GenericResourceInspector starts hidden)

	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = Color(_current_accent, 0.40)
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 3
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_size = 3
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 1)
	card.add_theme_stylebox_override("panel", sb)

	parent.remove_child(section)
	card.add_child(section)
	parent.add_child(card)
	parent.move_child(card, idx)

	# Pump existing per-section MarginContainers' padding down a bit – the card
	# now provides outer padding, so the inner margin can be smaller.
	var inner_margin = section.get_node_or_null("MarginContainer")
	if inner_margin:
		inner_margin.add_theme_constant_override("margin_left", 0)
		inner_margin.add_theme_constant_override("margin_right", 0)
		inner_margin.add_theme_constant_override("margin_top", 4)

	_accent_appliers.append(func(c: Color):
		sb.border_color = Color(c, 0.40)
	)


# ── Upgrade-tree editor card ────────────────────────────────────────────────────
func _build_upgrade_section() -> void:
	if is_instance_valid(_upgrade_editor):
		return
	var content = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent

	_upgrade_editor = UpgradeTreeEditor.new()
	_upgrade_editor.name = "UpgradeTreeEditor"
	_upgrade_editor.dirty_changed.connect(func(): _set_dirty(true))
	_upgrade_editor.structure_changed.connect(_on_upgrade_structure_changed)

	_upgrade_card = PanelContainer.new()
	_upgrade_card.name = "UpgradeTreeCard"
	_upgrade_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = Color(_current_accent, 0.40)
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 3
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_size = 3
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 1)
	_upgrade_card.add_theme_stylebox_override("panel", sb)
	_upgrade_card.add_child(_upgrade_editor)
	content.add_child(_upgrade_card)

	var fcard = content.get_node_or_null("FormulaEditorCard")
	if fcard:
		content.move_child(_upgrade_card, fcard.get_index() + 1)

	_accent_appliers.append(func(c: Color):
		sb.border_color = Color(c, 0.40))
	_upgrade_card.visible = false


func _set_upgrade_card_visible(vis: bool) -> void:
	if is_instance_valid(_upgrade_card):
		_upgrade_card.visible = vis


# ── Discipline board (opened from the header button) ────────────────────────────
func _build_board_button() -> void:
	if is_instance_valid(_board_button):
		return
	var fb = new_button.get_parent()
	if not is_instance_valid(fb):
		return
	_board_button = Button.new()
	_board_button.text = "🌲 Tree"
	_board_button.tooltip_text = "Open the discipline skill-tree placement board"
	_board_button.pressed.connect(_open_board)
	_style_btn(_board_button, C_DIM, false)
	fb.add_child(_board_button)

	var problems_btn := Button.new()
	problems_btn.text = "⚠ Problems"
	problems_btn.tooltip_text = "Scan all resources for authoring problems"
	problems_btn.pressed.connect(_open_problems)
	_style_btn(problems_btn, C_DIM, false)
	fb.add_child(problems_btn)

	var batch_btn := Button.new()
	batch_btn.text = "≣ Batch"
	batch_btn.tooltip_text = "Batch-edit a field across many resources of the current type"
	batch_btn.pressed.connect(_open_batch)
	_style_btn(batch_btn, C_DIM, false)
	fb.add_child(batch_btn)


func _open_board() -> void:
	if not is_instance_valid(_board_window):
		_board_window = DisciplineBoard.new()
		add_child(_board_window)
	_board_window.open()


# ── Related / cross-resource navigation panel ───────────────────────────────────
func _build_related_section() -> void:
	if is_instance_valid(_related_card):
		return
	var content = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent
	_related_card = _new_accent_card("RelatedCard")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_related_card.add_child(col)
	var title := Label.new()
	title.text = "🔗  RELATED"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", _current_accent)
	col.add_child(title)
	_accent_appliers.append(func(c: Color): title.add_theme_color_override("font_color", c))
	_related_host = VBoxContainer.new()
	_related_host.add_theme_constant_override("separation", 3)
	col.add_child(_related_host)
	content.add_child(_related_card)
	_related_card.visible = false


func _invalidate_related_index() -> void:
	_rel_index_built = false


func _ensure_related_index() -> void:
	if _rel_index_built:
		return
	_rel_index_built = true
	_rel_upgrade_to_ability.clear()
	_rel_weapon_to_abilities.clear()
	_rel_buff_to_abilities.clear()
	_index_ability_dir("res://resources/Abilities")


func _index_ability_dir(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		var full := path.path_join(f)
		if dir.current_is_dir():
			if not f.begins_with("."):
				_index_ability_dir(full)
		elif f.ends_with(".tres"):
			var res = load(full)
			if res is AbilityData:
				var a := res as AbilityData
				if a.upgrades != null:
					for u in a.upgrades:
						if u is AbilityUpgradeData and not u.resource_path.is_empty():
							_rel_upgrade_to_ability[u.resource_path] = full
				if a.required_weapon_types != null:
					for wt in a.required_weapon_types:
						if not _rel_weapon_to_abilities.has(wt):
							_rel_weapon_to_abilities[wt] = []
						_rel_weapon_to_abilities[wt].append(full)
				for buff_field in [a.applies_buff, a.applies_target_debuff]:
					if buff_field is Resource and not buff_field.resource_path.is_empty():
						if not _rel_buff_to_abilities.has(buff_field.resource_path):
							_rel_buff_to_abilities[buff_field.resource_path] = []
						_rel_buff_to_abilities[buff_field.resource_path].append(full)
		f = dir.get_next()
	dir.list_dir_end()


func _update_related_ui(res: Resource) -> void:
	if not is_instance_valid(_related_card):
		return
	for c in _related_host.get_children():
		c.queue_free()
	var added := 0

	if res is AbilityData:
		var a := res as AbilityData
		if a.applies_buff is Resource and not a.applies_buff.resource_path.is_empty():
			added += _add_related_link("Applies buff", a.applies_buff.resource_path)
		if a.applies_target_debuff is Resource and not a.applies_target_debuff.resource_path.is_empty():
			added += _add_related_link("Applies debuff", a.applies_target_debuff.resource_path)
		if a.upgrades != null:
			for u in a.upgrades:
				if u is AbilityUpgradeData and not u.resource_path.is_empty():
					added += _add_related_link("Upgrade: " + (u.upgrade_name if not u.upgrade_name.is_empty() else u.upgrade_id), u.resource_path)
		if a.prerequisite_abilities != null:
			for k in a.prerequisite_abilities:
				if k is Resource and not k.resource_path.is_empty():
					added += _add_related_link("Requires (Lv %d)" % int(a.prerequisite_abilities[k]), k.resource_path)
	elif res is AbilityUpgradeData:
		_ensure_related_index()
		var parent = _rel_upgrade_to_ability.get(res.resource_path, "")
		if parent != "":
			added += _add_related_link("Parent ability", parent)
	elif res is WeaponData:
		_ensure_related_index()
		var list: Array = _rel_weapon_to_abilities.get((res as WeaponData).weapon_type, [])
		for ap in list:
			added += _add_related_link("Ability for this weapon", ap)
	elif res is BuffData:
		_ensure_related_index()
		var blist: Array = _rel_buff_to_abilities.get(res.resource_path, [])
		for ap in blist:
			added += _add_related_link("Applied by ability", ap)
	elif res is EnemyData:
		# Drops reference items by NAME (not a resource ref), so show as text.
		var e := res as EnemyData
		if e.item_drops != null:
			for d in e.item_drops:
				if d != null and "item_name" in d and not str(d.item_name).is_empty():
					var lbl := Label.new()
					lbl.text = "💧 Drops: %s (%.0f%%)" % [d.item_name, float(d.drop_chance) * 100.0]
					lbl.add_theme_font_size_override("font_size", 11)
					lbl.add_theme_color_override("font_color", C_DIM)
					_related_host.add_child(lbl)
					added += 1

	_related_card.visible = added > 0


func _add_related_link(label: String, path: String) -> int:
	var btn := Button.new()
	btn.text = "→ %s  ·  %s" % [label, path.get_file()]
	btn.tooltip_text = path
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.flat = true
	btn.add_theme_color_override("font_color", _current_accent)
	btn.pressed.connect(func(): _jump_to_resource(path))
	_related_host.add_child(btn)
	return 1


func _open_problems() -> void:
	if not is_instance_valid(_validation_window):
		_validation_window = ValidationDashboard.new()
		_validation_window.jump_requested.connect(_jump_to_resource)
		add_child(_validation_window)
	_validation_window.open()


func _open_batch() -> void:
	if not current_resource_type:
		return
	if not is_instance_valid(_batch_window):
		_batch_window = BatchEditWindow.new()
		_batch_window.applied.connect(func():
			_invalidate_related_index()
			_scan_for_resources())
		add_child(_batch_window)
	_batch_window.open_for(current_resource_type.display_name, current_resource_type.script_path, current_resource_type.base_folder)


# Jump to a resource by path: switch to its type, scan, load it, select in tree.
func _jump_to_resource(path: String) -> void:
	if path.is_empty():
		return
	var res = load(path)
	if res == null:
		return
	var idx := _type_index_for_resource(res)
	_guard_unsaved(func():
		if idx >= 0:
			resource_type_selector.select(idx)
			current_resource_type = resource_types[idx]
			_update_accent(CATEGORY_COLORS.get(current_resource_type.category, C_DIM))
			_scan_for_resources()
		_load_resource(path)
		var item = _path_to_tree_item.get(path, null)
		if item:
			item.select(0)
		_save_dock_state()
	)


func _type_index_for_resource(res: Resource) -> int:
	var rs := res.get_script()
	if rs == null:
		return -1
	var inherit := -1
	for i in resource_types.size():
		var ts = load(resource_types[i].script_path)
		if ts == null:
			continue
		if rs == ts:
			return i  # exact match wins (e.g. WeaponData -> "Weapons", not "Items")
		if inherit == -1 and _script_matches_or_inherits(rs, ts):
			inherit = i
	return inherit


# Add/remove already wrote the upgrade files + re-saved the parent ability; just
# refresh the browser so new/removed upgrade .tres show under the browsable type.
func _on_upgrade_structure_changed() -> void:
	_scan_for_resources()


# ── Shared accent-card builder (used by the programmatic sections) ───────────────
func _new_accent_card(card_name: String) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = card_name
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = Color(_current_accent, 0.40)
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_width_left = 3
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 12
	sb.content_margin_bottom = 14
	sb.shadow_size = 3
	sb.shadow_color = Color(0, 0, 0, 0.30)
	sb.shadow_offset = Vector2(0, 1)
	card.add_theme_stylebox_override("panel", sb)
	_accent_appliers.append(func(c: Color): sb.border_color = Color(c, 0.40))
	return card


# ── Advanced ability fields card ────────────────────────────────────────────────
var _prereq_rows: Array = []  # [{picker, spin}] for the prerequisite editor

func _build_advanced_section() -> void:
	if is_instance_valid(_adv_card):
		return
	var content = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent
	_adv_card = _new_accent_card("AdvancedFieldsCard")
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	_adv_card.add_child(col)

	var title := Label.new()
	title.text = "✚  ADVANCED"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", _current_accent)
	col.add_child(title)
	_accent_appliers.append(func(c: Color): title.add_theme_color_override("font_color", c))

	# damage_stat
	_adv_damage_stat = OptionButton.new()
	for key in Constants.StatType:
		_adv_damage_stat.add_item(key, Constants.StatType[key])
	_adv_damage_stat.item_selected.connect(func(_i):
		if _editing_ability():
			(current_resource as AbilityData).damage_stat = _adv_damage_stat.get_selected_id()
			_set_dirty(true))
	col.add_child(_adv_labeled_row("Damage Stat", _adv_damage_stat,
		"Stat the ability's damage scales from (WEAPONATTACK / MAGICATTACK / …)."))

	# Skill-tree placement (also editable on the discipline board).
	var tree_row := HBoxContainer.new()
	tree_row.add_theme_constant_override("separation", 6)
	var tp_lbl := Label.new(); tp_lbl.text = "Tree Path"; tp_lbl.add_theme_color_override("font_color", C_DIM)
	tree_row.add_child(tp_lbl)
	_adv_tree_path = OptionButton.new()
	_adv_tree_path.add_item("None", -1)
	_adv_tree_path.add_item("Path A", 0)
	_adv_tree_path.add_item("Path B", 1)
	_adv_tree_path.item_selected.connect(func(_i):
		if _editing_ability():
			(current_resource as AbilityData).tree_path = _adv_tree_path.get_selected_id()
			_set_dirty(true))
	tree_row.add_child(_adv_tree_path)
	var td_lbl := Label.new(); td_lbl.text = "Depth"; td_lbl.add_theme_color_override("font_color", C_DIM)
	tree_row.add_child(td_lbl)
	_adv_tree_depth = SpinBox.new()
	_adv_tree_depth.min_value = 0
	_adv_tree_depth.max_value = 20
	_adv_tree_depth.value_changed.connect(func(v):
		if _editing_ability():
			(current_resource as AbilityData).tree_depth = int(v)
			_set_dirty(true))
	tree_row.add_child(_adv_tree_depth)
	col.add_child(tree_row)

	# applies_buff / applies_target_debuff (duration formulas show in the Formula tree).
	_adv_buff_picker = EditorResourcePicker.new()
	_adv_buff_picker.base_type = "BuffData"
	_adv_buff_picker.resource_changed.connect(func(_r):
		if _editing_ability():
			(current_resource as AbilityData).applies_buff = _adv_buff_picker.get_edited_resource()
			_set_dirty(true)
			_update_formula_tree())
	col.add_child(_adv_labeled_row("Applies Buff (self)", _adv_buff_picker,
		"BuffData applied to the caster. Duration formula appears in the Formula tree."))

	_adv_debuff_picker = EditorResourcePicker.new()
	_adv_debuff_picker.base_type = "BuffData"
	_adv_debuff_picker.resource_changed.connect(func(_r):
		if _editing_ability():
			(current_resource as AbilityData).applies_target_debuff = _adv_debuff_picker.get_edited_resource()
			_set_dirty(true)
			_update_formula_tree())
	col.add_child(_adv_labeled_row("Applies Debuff (target)", _adv_debuff_picker,
		"BuffData applied to each enemy hit. Duration formula appears in the Formula tree."))

	# prerequisite_abilities
	var prereq_header := HBoxContainer.new()
	var ph_lbl := Label.new()
	ph_lbl.text = "Prerequisites"
	ph_lbl.add_theme_color_override("font_color", C_DIM)
	ph_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ph_lbl.tooltip_text = "Abilities that must reach a level before this one can be learned."
	prereq_header.add_child(ph_lbl)
	var add_prereq := Button.new()
	add_prereq.text = "+ Prereq"
	add_prereq.pressed.connect(_on_add_prereq_pressed)
	prereq_header.add_child(add_prereq)
	col.add_child(prereq_header)
	_adv_prereq_host = VBoxContainer.new()
	_adv_prereq_host.add_theme_constant_override("separation", 4)
	col.add_child(_adv_prereq_host)

	content.add_child(_adv_card)
	var gcard = content.get_node_or_null("GeneralSettingsCard")
	if gcard:
		content.move_child(_adv_card, gcard.get_index() + 1)
	_adv_card.visible = false


func _adv_labeled_row(label_text: String, control: Control, tip: String = "") -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_color_override("font_color", C_DIM)
	if not tip.is_empty():
		lbl.tooltip_text = tip
	row.add_child(lbl)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _editing_ability() -> bool:
	return not is_updating_ui and current_resource is AbilityData


func _set_advanced_card_visible(vis: bool) -> void:
	if is_instance_valid(_adv_card):
		_adv_card.visible = vis


func _update_advanced_ui(ability: AbilityData) -> void:
	if not is_instance_valid(_adv_card):
		return
	_adv_damage_stat.selected = _adv_damage_stat.get_item_index(ability.damage_stat)
	_adv_tree_path.selected = _adv_tree_path.get_item_index(ability.tree_path) if _adv_tree_path.get_item_index(ability.tree_path) >= 0 else 0
	_adv_tree_depth.value = ability.tree_depth
	_adv_buff_picker.set_edited_resource(ability.applies_buff)
	_adv_debuff_picker.set_edited_resource(ability.applies_target_debuff)
	_rebuild_prereq_rows(ability)


func _rebuild_prereq_rows(ability: AbilityData) -> void:
	_prereq_rows.clear()
	for c in _adv_prereq_host.get_children():
		c.queue_free()
	for prereq in ability.prerequisite_abilities:
		_add_prereq_row(ability, prereq, int(ability.prerequisite_abilities[prereq]))


func _add_prereq_row(ability: AbilityData, prereq_ability: Resource, level: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var picker := EditorResourcePicker.new()
	picker.base_type = "AbilityData"
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if prereq_ability:
		picker.set_edited_resource(prereq_ability)
	picker.resource_changed.connect(func(_r): _commit_prereqs(ability))
	row.add_child(picker)
	var lvl_lbl := Label.new(); lvl_lbl.text = "Lv"; lvl_lbl.add_theme_color_override("font_color", C_DIM)
	row.add_child(lvl_lbl)
	var spin := SpinBox.new()
	spin.min_value = 1
	spin.max_value = 100
	spin.value = level
	spin.value_changed.connect(func(_v): _commit_prereqs(ability))
	row.add_child(spin)
	var rm := Button.new()
	rm.text = "✕"
	rm.add_theme_color_override("font_color", C_ERR)
	rm.pressed.connect(func():
		_prereq_rows = _prereq_rows.filter(func(e): return e.row != row)
		row.queue_free()
		_commit_prereqs.call_deferred(ability))
	row.add_child(rm)
	_adv_prereq_host.add_child(row)
	_prereq_rows.append({"row": row, "picker": picker, "spin": spin})


func _on_add_prereq_pressed() -> void:
	if not _editing_ability():
		return
	_add_prereq_row(current_resource as AbilityData, null, 1)


# Rewrite the typed Dictionary[AbilityData,int] in place from the current rows.
func _commit_prereqs(ability: AbilityData) -> void:
	if not is_instance_valid(_adv_card):
		return
	ability.prerequisite_abilities.clear()
	for e in _prereq_rows:
		if not is_instance_valid(e.row):
			continue
		var res = e.picker.get_edited_resource()
		if res is AbilityData:
			ability.prerequisite_abilities[res] = int(e.spin.value)
	_set_dirty(true)


# ── Section label cache + restyle ──────────────────────────────────────────────
func _cache_section_labels() -> void:
	_section_labels.clear()
	_section_label_meta.clear()
	var content = $Panel/MainHSplit/EditorPanel/ScrollContainer/EditorContent
	var sections: Array = [
		["GeneralSettings", "◈  GENERAL SETTINGS",   "SectionLabel"],
		["ActiveBehavior",  "⚔  ACTIVE BEHAVIOR",    "SectionLabel"],
		["FormulaEditor",   "📊  FORMULA EDITOR",    "SectionLabel"],
		["QuestEditor",     "📜  QUEST DETAILS",     "SectionLabel"],
	]
	for entry in sections:
		# Sections were re-parented under "<name>Card" by _wrap_sections_in_cards.
		var section = content.get_node_or_null(entry[0] + "Card/" + entry[0])
		if not section:
			section = content.get_node_or_null(entry[0])
		if not section:
			continue
		var lbl: Label = section.get_node_or_null(entry[2])
		if lbl:
			_section_labels.append(lbl)
			_section_label_meta.append(entry[1])


func _restyle_section_labels(color: Color) -> void:
	for i in range(_section_labels.size()):
		var lbl: Label = _section_labels[i]
		if not is_instance_valid(lbl):
			continue
		var base_text = _section_label_meta[i] if i < _section_label_meta.size() else lbl.text
		# Preserve the collapse chevron if set
		var chev = "▾  " if not _section_collapsed.get(lbl, false) else "▸  "
		lbl.text = chev + base_text
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", color)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT


# Make each section header clickable; clicking toggles the rest of the section.
func _make_sections_collapsible() -> void:
	for lbl in _section_labels:
		if not is_instance_valid(lbl):
			continue
		var section = lbl.get_parent()
		if not section:
			continue
		# Capture all children except the label itself — these get hidden when collapsed.
		var body: Array = []
		for child in section.get_children():
			if child != lbl and child is Control:
				body.append(child)
		_section_bodies[lbl] = body
		_section_collapsed[lbl] = false
		lbl.mouse_filter = Control.MOUSE_FILTER_STOP
		lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		lbl.gui_input.connect(_on_section_header_input.bind(lbl))


func _on_section_header_input(event: InputEvent, lbl: Label) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		_toggle_section_collapsed(lbl)


func _toggle_section_collapsed(lbl: Label) -> void:
	var collapsed = not _section_collapsed.get(lbl, false)
	_section_collapsed[lbl] = collapsed
	var body: Array = _section_bodies.get(lbl, [])
	for ctrl in body:
		if is_instance_valid(ctrl):
			ctrl.visible = not collapsed
	# Refresh the chevron in the header
	_restyle_section_labels(_current_accent)


# ── Section header divider (thin accent line under each section title) ────────
func _add_section_dividers() -> void:
	for lbl in _section_labels:
		if not is_instance_valid(lbl):
			continue
		var section = lbl.get_parent()
		if not section:
			continue
		var sep = HSeparator.new()
		sep.name = "HeaderDivider"
		var sep_sb = StyleBoxFlat.new()
		sep_sb.bg_color = Color(_current_accent, 0.25)
		sep_sb.content_margin_top = 0
		sep_sb.content_margin_bottom = 0
		sep.add_theme_stylebox_override("separator", sep_sb)
		sep.add_theme_constant_override("separation", 4)
		_accent_appliers.append(func(c: Color):
			sep_sb.bg_color = Color(c, 0.25)
		)
		section.add_child(sep)
		section.move_child(sep, lbl.get_index() + 1)


# ── Formula curve chart ────────────────────────────────────────────────────────
func _create_curve_chart() -> void:
	if is_instance_valid(_curve_chart):
		return
	var wrap = VBoxContainer.new()
	wrap.name = "CurveChartWrap"
	wrap.add_theme_constant_override("separation", 4)

	var hdr = Label.new()
	hdr.text = "📈  CURVE PREVIEW"
	hdr.add_theme_font_size_override("font_size", 10)
	hdr.add_theme_color_override("font_color", C_DIM)
	wrap.add_child(hdr)

	_curve_chart = Control.new()
	_curve_chart.custom_minimum_size = Vector2(0, 140)
	_curve_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_curve_chart.draw.connect(_draw_curve_chart)
	_curve_chart.resized.connect(func(): _curve_chart.queue_redraw())
	wrap.add_child(_curve_chart)

	# Add inside the FormulaEditor section so it collapses with it
	if formula_editor_panel:
		formula_editor_panel.add_child(wrap)


func _draw_curve_chart() -> void:
	if not is_instance_valid(_curve_chart):
		return
	var size = _curve_chart.size
	var rect = Rect2(Vector2.ZERO, size)

	# Background
	var bg = StyleBoxFlat.new()
	bg.bg_color = C_DARK.darkened(0.10)
	bg.border_color = C_BORDER
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(4)
	_curve_chart.draw_style_box(bg, rect)

	var font = ThemeDB.fallback_font
	if not font:
		return

	if not current_editing_formula or not current_resource is AbilityData:
		_curve_chart.draw_string(font, Vector2(12, size.y / 2 + 4),
			"Select a formula on the left to preview its curve.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, C_DIM)
		return

	var ability := current_resource as AbilityData
	var max_level: int = max(1, ability.max_level)

	var values: Array[float] = []
	var max_val = -INF
	var min_val = INF
	for lvl in range(1, max_level + 1):
		var v: float = float(current_editing_formula.calculate(lvl))
		values.append(v)
		if v > max_val: max_val = v
		if v < min_val: min_val = v
	if absf(max_val - min_val) < 0.001:
		max_val = min_val + 1.0

	var pad_l = 40.0
	var pad_r = 12.0
	var pad_t = 12.0
	var pad_b = 22.0
	var plot_w = size.x - pad_l - pad_r
	var plot_h = size.y - pad_t - pad_b
	if plot_w <= 1 or plot_h <= 1:
		return

	var origin = Vector2(pad_l, pad_t + plot_h)

	# Subtle horizontal grid lines (3 ticks)
	for i in range(4):
		var y = pad_t + plot_h * float(i) / 3.0
		_curve_chart.draw_line(Vector2(pad_l, y), Vector2(pad_l + plot_w, y), Color(C_BORDER, 0.4), 1)

	# Axes
	_curve_chart.draw_line(origin, Vector2(pad_l + plot_w, origin.y), C_BORDER, 1)
	_curve_chart.draw_line(origin, Vector2(pad_l, pad_t), C_BORDER, 1)

	# Curve points
	var points: PackedVector2Array = PackedVector2Array()
	for i in range(values.size()):
		var lvl = i + 1
		var v = values[i]
		var fx: float = 0.0 if max_level == 1 else float(lvl - 1) / float(max_level - 1)
		var fy: float = (v - min_val) / (max_val - min_val)
		points.push_back(Vector2(pad_l + plot_w * fx, pad_t + plot_h - plot_h * fy))

	# Filled area under curve (semi-transparent accent)
	if points.size() >= 2:
		var fill_poly: PackedVector2Array = points.duplicate()
		fill_poly.push_back(Vector2(points[points.size() - 1].x, origin.y))
		fill_poly.push_back(Vector2(points[0].x, origin.y))
		_curve_chart.draw_colored_polygon(fill_poly, Color(_current_accent, 0.15))
		_curve_chart.draw_polyline(points, _current_accent, 2.0, true)

	# Sample dots
	for p in points:
		_curve_chart.draw_circle(p, 2.5, _current_accent)

	# Axis labels
	_curve_chart.draw_string(font, Vector2(4, pad_t + 8),                "%.1f" % max_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	_curve_chart.draw_string(font, Vector2(4, pad_t + plot_h),           "%.1f" % min_val, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	_curve_chart.draw_string(font, Vector2(pad_l - 2, origin.y + 14),    "1",            HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)
	_curve_chart.draw_string(font, Vector2(pad_l + plot_w - 16, origin.y + 14), str(max_level), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, C_DIM)


func _refresh_curve_chart() -> void:
	if is_instance_valid(_curve_chart):
		_curve_chart.queue_redraw()


# ── Persisted dock state ───────────────────────────────────────────────────────
func _save_dock_state() -> void:
	if not Engine.is_editor_hint():
		return
	var settings = EditorInterface.get_editor_settings()
	if not settings:
		return
	var type_name := ""
	if current_resource_type:
		type_name = current_resource_type.display_name
	var resource_path := ""
	if current_resource and not current_resource.resource_path.is_empty():
		resource_path = current_resource.resource_path
	settings.set_project_metadata("resource_editor", "last_state", {
		"type": type_name,
		"resource": resource_path,
	})


func _restore_dock_state() -> bool:
	if not Engine.is_editor_hint():
		return false
	var settings = EditorInterface.get_editor_settings()
	if not settings:
		return false
	var state = settings.get_project_metadata("resource_editor", "last_state", null)
	if not state is Dictionary:
		return false
	var saved_type = state.get("type", "")
	var saved_resource = state.get("resource", "")

	# Restore the type dropdown
	for i in range(resource_types.size()):
		if resource_types[i].display_name == saved_type:
			current_resource_type = resource_types[i]
			resource_type_selector.select(i)
			_update_accent(CATEGORY_COLORS.get(current_resource_type.category, C_DIM))
			_scan_for_resources()
			break

	# Restore the resource if it still exists
	if saved_resource != "" and FileAccess.file_exists(saved_resource):
		_load_resource(saved_resource)
		var item = _path_to_tree_item.get(saved_resource, null)
		if item:
			item.select(0)
		return true
	return false


# ── Reusable stylebox factories ────────────────────────────────────────────────
func _make_tree_panel_sb() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.set_border_width_all(1)
	sb.border_color = Color(_current_accent, 0.35)
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(4)
	_accent_appliers.append(func(c: Color):
		sb.border_color = Color(c, 0.35)
	)
	return sb


func _make_tree_selected_sb() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = Color(_current_accent, 0.22)
	sb.set_border_width_all(0)
	sb.set_corner_radius_all(4)
	_accent_appliers.append(func(c: Color):
		sb.bg_color = Color(c, 0.22)
	)
	return sb


func _make_input_normal_sb() -> StyleBoxFlat:
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_DARK
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 5
	sb.content_margin_bottom = 5
	return sb


func _make_input_hover_sb() -> StyleBoxFlat:
	var sb = _make_input_normal_sb()
	sb.bg_color = C_DARK.lightened(0.04)
	sb.border_color = Color(_current_accent, 0.55)
	_accent_appliers.append(func(c: Color):
		sb.border_color = Color(c, 0.55)
	)
	return sb


func _make_input_focus_sb() -> StyleBoxFlat:
	var sb = _make_input_normal_sb()
	sb.border_color = _current_accent
	sb.set_border_width_all(2)
	sb.content_margin_left = 7
	sb.content_margin_right = 7
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	_accent_appliers.append(func(c: Color):
		sb.border_color = c
	)
	return sb


# ── Input control polish ───────────────────────────────────────────────────────
func _polish_inputs() -> void:
	# LineEdits
	for le in [ability_id_edit, ability_name_edit, search_edit,
			   quest_id_edit, quest_name_edit, quest_reward_items_edit]:
		_style_line_edit(le)
	_style_text_edit(description_edit)
	_style_text_edit(quest_description_edit)
	for sb in [max_level_spinbox, quest_required_level_spin, quest_sort_order_spin,
			   quest_reward_exp_spin, quest_reward_coins_spin]:
		_style_spin_box(sb)
	for ob in [resource_type_selector, ability_type_option, required_class_option,
			   required_weapon_option, formula_preset_option, quest_prereq_option]:
		_style_option_button(ob)
	_style_check_box(quest_npc_only_check)
	# Search bar gets a magnifier icon if available
	if is_instance_valid(search_edit):
		var icon = _editor_icon("Search")
		if icon:
			search_edit.right_icon = icon


func _style_line_edit(le: LineEdit) -> void:
	if not is_instance_valid(le):
		return
	le.add_theme_stylebox_override("normal", _make_input_normal_sb())
	le.add_theme_stylebox_override("focus",  _make_input_focus_sb())
	le.add_theme_color_override("font_color",             C_TEXT)
	le.add_theme_color_override("font_placeholder_color", C_DIM)
	le.add_theme_color_override("caret_color",            _current_accent)
	le.add_theme_color_override("selection_color",        Color(_current_accent, 0.30))
	le.add_theme_font_size_override("font_size", 12)
	_accent_appliers.append(func(c: Color):
		le.add_theme_color_override("caret_color",     c)
		le.add_theme_color_override("selection_color", Color(c, 0.30))
	)


func _style_text_edit(te: TextEdit) -> void:
	if not is_instance_valid(te):
		return
	te.add_theme_stylebox_override("normal", _make_input_normal_sb())
	te.add_theme_stylebox_override("focus",  _make_input_focus_sb())
	te.add_theme_color_override("font_color",      C_TEXT)
	te.add_theme_color_override("caret_color",     _current_accent)
	te.add_theme_color_override("selection_color", Color(_current_accent, 0.30))
	te.add_theme_font_size_override("font_size", 12)
	_accent_appliers.append(func(c: Color):
		te.add_theme_color_override("caret_color",     c)
		te.add_theme_color_override("selection_color", Color(c, 0.30))
	)


func _style_spin_box(sb: SpinBox) -> void:
	if not is_instance_valid(sb):
		return
	# SpinBox draws its inner LineEdit – style that instead.
	_style_line_edit(sb.get_line_edit())


func _style_option_button(ob: OptionButton) -> void:
	if not is_instance_valid(ob):
		return
	ob.add_theme_stylebox_override("normal",  _make_input_normal_sb())
	ob.add_theme_stylebox_override("hover",   _make_input_hover_sb())
	ob.add_theme_stylebox_override("pressed", _make_input_hover_sb())
	ob.add_theme_stylebox_override("focus",   _make_input_focus_sb())
	ob.add_theme_color_override("font_color",         C_TEXT)
	ob.add_theme_color_override("font_hover_color",   Color.WHITE)
	ob.add_theme_color_override("font_pressed_color", Color.WHITE)
	ob.add_theme_font_size_override("font_size", 12)


func _style_check_box(cb: CheckBox) -> void:
	if not is_instance_valid(cb):
		return
	cb.add_theme_color_override("font_color",         C_TEXT)
	cb.add_theme_color_override("font_hover_color",   Color.WHITE)
	cb.add_theme_color_override("font_pressed_color", _current_accent)
	cb.add_theme_color_override("font_focus_color",   _current_accent)
	cb.add_theme_font_size_override("font_size", 12)
	_accent_appliers.append(func(c: Color):
		cb.add_theme_color_override("font_pressed_color", c)
		cb.add_theme_color_override("font_focus_color",   c)
	)


# ── Visualizer panel polish ────────────────────────────────────────────────────
func _polish_visualizer_panel() -> void:
	if not is_instance_valid(visualizer_container):
		return
	var pc = visualizer_container.get_node_or_null("PanelContainer")
	if pc:
		var sb = StyleBoxFlat.new()
		sb.bg_color = C_DARK.darkened(0.10)
		sb.border_color = C_BORDER
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		pc.add_theme_stylebox_override("panel", sb)
	# Polish the info labels above the visualizer too
	var info: Label = visualizer_container.get_node_or_null("InfoLabel")
	if info:
		info.add_theme_color_override("font_color", C_DIM)
		info.add_theme_font_size_override("font_size", 11)
	var hlbl: Label = visualizer_container.get_node_or_null("Label")
	if hlbl:
		hlbl.add_theme_color_override("font_color", C_TEXT)
		hlbl.add_theme_font_size_override("font_size", 13)

	# Mouse wheel zoom on the visualizer
	if is_instance_valid(visualizer_control):
		visualizer_control.mouse_filter = Control.MOUSE_FILTER_STOP
		if not visualizer_control.gui_input.is_connected(_on_visualizer_gui_input):
			visualizer_control.gui_input.connect(_on_visualizer_gui_input)

	# Zoom controls row beneath the preview
	if visualizer_container.get_node_or_null("ZoomRow") == null:
		var row = HBoxContainer.new()
		row.name = "ZoomRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", 6)
		visualizer_container.add_child(row)

		var zoom_out = Button.new()
		zoom_out.text = " − "
		zoom_out.tooltip_text = "Zoom out"
		zoom_out.pressed.connect(func(): _set_visualizer_zoom(_visualizer_zoom / 1.25))
		_style_btn(zoom_out, C_DIM, false)
		row.add_child(zoom_out)

		_zoom_label = Label.new()
		_zoom_label.text = "Zoom: %.1fx" % _visualizer_zoom
		_zoom_label.custom_minimum_size = Vector2(90, 0)
		_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_zoom_label.add_theme_font_size_override("font_size", 11)
		_zoom_label.add_theme_color_override("font_color", C_DIM)
		row.add_child(_zoom_label)

		var zoom_in = Button.new()
		zoom_in.text = " + "
		zoom_in.tooltip_text = "Zoom in"
		zoom_in.pressed.connect(func(): _set_visualizer_zoom(_visualizer_zoom * 1.25))
		_style_btn(zoom_in, C_DIM, false)
		row.add_child(zoom_in)

		var reset = Button.new()
		reset.text = " Reset "
		reset.tooltip_text = "Reset zoom to default"
		reset.pressed.connect(func(): _set_visualizer_zoom(_VISUALIZER_DEFAULT_ZOOM))
		_style_btn(reset, C_DIM, false)
		row.add_child(reset)

		# Toggle the cast/hit VFX overlay so it doesn't obscure the hitbox.
		var vfx_toggle = CheckBox.new()
		vfx_toggle.text = "VFX"
		vfx_toggle.tooltip_text = "Show the resolved cast (on the body) and hit (at the hitbox) VFX"
		vfx_toggle.button_pressed = _vis_show_vfx
		_style_check_box(vfx_toggle)
		vfx_toggle.toggled.connect(func(on: bool):
			_vis_show_vfx = on
			_update_visualizer_vfx())
		row.add_child(vfx_toggle)


# ── Editor icons (best-effort: returns null when the editor theme isn't ready) ──
func _editor_icon(icon_name: String) -> Texture2D:
	if not Engine.is_editor_hint():
		return null
	var theme = EditorInterface.get_editor_theme()
	if theme and theme.has_icon(icon_name, "EditorIcons"):
		return theme.get_icon(icon_name, "EditorIcons")
	return null


func _apply_button_icons() -> void:
	var icon_map = {
		new_button:           "Add",
		save_button:          "Save",
		save_as_button:       "Save",
		duplicate_button:     "Duplicate",
		delete_button:        "Remove",
		preview_button:       "Search",
		refresh_button:       "Reload",
		add_formula_button:   "Add",
		formula_help_button:  "Help",
	}
	for btn in icon_map:
		var icon = _editor_icon(icon_map[btn])
		if icon and is_instance_valid(btn):
			btn.icon = icon
			# Add a hair of horizontal separation between icon and label
			btn.add_theme_constant_override("h_separation", 4)


func _add_status_bar() -> void:
	var bar = PanelContainer.new()
	var bar_sb = StyleBoxFlat.new()
	bar_sb.bg_color = C_DARK
	bar_sb.border_width_top = 1
	bar_sb.border_color = C_BORDER
	bar_sb.set_content_margin_all(0)
	bar.add_theme_stylebox_override("panel", bar_sb)
	bar.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bar.offset_top = -26
	add_child(bar)

	var m = MarginContainer.new()
	m.add_theme_constant_override("margin_left",   12)
	m.add_theme_constant_override("margin_right",  12)
	m.add_theme_constant_override("margin_top",     5)
	m.add_theme_constant_override("margin_bottom",  5)
	bar.add_child(m)

	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	m.add_child(row)

	# Left chip — shows current type icon and category
	_status_type_chip = Label.new()
	_status_type_chip.text = ""
	_status_type_chip.add_theme_font_size_override("font_size", 10)
	_status_type_chip.add_theme_color_override("font_color", _current_accent)
	_status_type_chip.custom_minimum_size = Vector2(110, 0)
	row.add_child(_status_type_chip)
	_accent_appliers.append(func(c: Color):
		if is_instance_valid(_status_type_chip):
			_status_type_chip.add_theme_color_override("font_color", c)
	)

	# Center status message (expands)
	_status_label = Label.new()
	_status_label.text = "Select a resource type to browse or create new."
	_status_label.add_theme_font_size_override("font_size", 10)
	_status_label.add_theme_color_override("font_color", C_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_status_label)

	# Right resource count
	_status_count_label = Label.new()
	_status_count_label.text = ""
	_status_count_label.add_theme_font_size_override("font_size", 10)
	_status_count_label.add_theme_color_override("font_color", C_DIM)
	_status_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(_status_count_label)


func _refresh_status_chrome() -> void:
	if current_resource_type:
		var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈")
		if is_instance_valid(_status_type_chip):
			_status_type_chip.text = icon + "  " + current_resource_type.display_name.to_upper()
	if is_instance_valid(_status_count_label):
		var n = _scanned_entries.size()
		if not _search_filter.is_empty():
			var visible := 0
			var fl = _search_filter.to_lower()
			for e in _scanned_entries:
				if str(e.name).to_lower().contains(fl):
					visible += 1
			_status_count_label.text = "%d / %d resources" % [visible, n]
		else:
			_status_count_label.text = "%d resources" % n


# ── Reactive accent update ─────────────────────────────────────────────────────
func _update_accent(color: Color) -> void:
	_current_accent = color

	if _title_label:
		_title_label.add_theme_color_override("font_color", color)

	# Drive every accent-tracked stylebox / color through its registered applier.
	for applier in _accent_appliers:
		if applier is Callable and applier.is_valid():
			applier.call(color)

	# Save button uses the legacy _style_btn helper which builds new styleboxes
	_style_btn(save_button, color, true)
	_restyle_section_labels(color)
	_refresh_status_chrome()
	_refresh_curve_chart()


# ── Button styling helper ──────────────────────────────────────────────────────
func _style_btn(btn: Button, color: Color, accent: bool) -> void:
	if not is_instance_valid(btn):
		return
	btn.add_theme_font_size_override("font_size", 10)

	var n = StyleBoxFlat.new()
	var h = StyleBoxFlat.new()
	var p = StyleBoxFlat.new()

	if accent:
		n.bg_color = Color(color, 0.15)
		n.set_border_width_all(1)
		n.border_color = Color(color, 0.70)
		n.set_corner_radius_all(3)
		n.set_content_margin_all(5)
		h.bg_color = Color(color, 0.28)
		h.set_border_width_all(1)
		h.border_color = color
		h.set_corner_radius_all(3)
		h.set_content_margin_all(5)
		p.bg_color = Color(color, 0.40)
		p.set_border_width_all(1)
		p.border_color = color
		p.set_corner_radius_all(3)
		p.set_content_margin_all(5)
		btn.add_theme_color_override("font_color",         color)
		btn.add_theme_color_override("font_hover_color",   color)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	else:
		n.bg_color = C_CARD
		n.set_border_width_all(1)
		n.border_color = C_BORDER
		n.set_corner_radius_all(3)
		n.set_content_margin_all(5)
		h.bg_color = C_CARD.lightened(0.06)
		h.set_border_width_all(1)
		h.border_color = Color(0.42, 0.44, 0.50)
		h.set_corner_radius_all(3)
		h.set_content_margin_all(5)
		p.bg_color = C_DARK
		p.set_border_width_all(1)
		p.border_color = C_BORDER
		p.set_corner_radius_all(3)
		p.set_content_margin_all(5)
		btn.add_theme_color_override("font_color",         Color(0.80, 0.82, 0.85))
		btn.add_theme_color_override("font_hover_color",   Color.WHITE)
		btn.add_theme_color_override("font_pressed_color", Color.WHITE)

	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)
	btn.add_theme_stylebox_override("focus",   n)


# ── Status bar helper ──────────────────────────────────────────────────────────
func _set_status(msg: String, is_err: bool = false) -> void:
	if not is_instance_valid(_status_label):
		return
	_status_label.text = msg
	_status_label.add_theme_color_override("font_color", C_ERR if is_err else C_OK)
	_status_version += 1
	var my_version = _status_version
	if not is_err:
		get_tree().create_timer(4.0).timeout.connect(func():
			if not is_instance_valid(_status_label):
				return
			if my_version != _status_version:
				return  # superseded by a newer status message
			_status_label.add_theme_color_override("font_color", C_DIM)
		)


# ========================================
# INITIALIZATION
# ========================================
func _load_resource_types() -> void:
	resource_types = ResourceTypeConfig.get_all_resource_types()
	if resource_type_selector:
		resource_type_selector.clear()
		for i in range(resource_types.size()):
			resource_type_selector.add_item(resource_types[i].display_name, i)


func _populate_option_buttons() -> void:
	_populate_option_button(ability_type_option, Constants.AbilityType)
	_populate_option_button(required_class_option, Constants.ClassType)
	_populate_option_button(required_weapon_option, Constants.WeaponType)


func _populate_option_button(button: OptionButton, enum_dict: Dictionary) -> void:
	button.clear()
	for key in enum_dict:
		button.add_item(key, enum_dict[key])


# ── Multi-select dropdowns (required_class / required_weapon_types) ─────────────
func _build_required_multiselects() -> void:
	_req_class_menu = _replace_option_with_multiselect(required_class_option, Constants.ClassType)
	_req_weapon_menu = _replace_option_with_multiselect(required_weapon_option, Constants.WeaponType)


func _replace_option_with_multiselect(opt: OptionButton, enum_dict: Dictionary) -> MenuButton:
	var mb := MenuButton.new()
	mb.name = opt.name + "Multi"
	mb.flat = false
	mb.size_flags_horizontal = opt.size_flags_horizontal
	mb.custom_minimum_size = opt.custom_minimum_size
	mb.text = "(none)"
	var pop := mb.get_popup()
	pop.hide_on_checkable_item_selection = false  # stay open while ticking
	for key in enum_dict:
		pop.add_check_item(key, enum_dict[key])
	pop.id_pressed.connect(func(id: int):
		var i := pop.get_item_index(id)
		pop.set_item_checked(i, not pop.is_item_checked(i))
		_update_multiselect_text(mb)
		_on_general_info_changed())
	_style_btn(mb, C_DIM, false)
	var parent := opt.get_parent()
	var idx := opt.get_index()
	opt.visible = false
	parent.add_child(mb)
	parent.move_child(mb, idx)
	return mb


func _multiselect_ids(mb: MenuButton) -> Array:
	var out: Array = []
	if not is_instance_valid(mb):
		return out
	var pop := mb.get_popup()
	for i in pop.item_count:
		if pop.is_item_checkable(i) and pop.is_item_checked(i):
			out.append(pop.get_item_id(i))
	return out


func _set_multiselect_ids(mb: MenuButton, ids) -> void:
	if not is_instance_valid(mb):
		return
	var pop := mb.get_popup()
	for i in pop.item_count:
		pop.set_item_checked(i, ids != null and ids.has(pop.get_item_id(i)))
	_update_multiselect_text(mb)


func _update_multiselect_text(mb: MenuButton) -> void:
	if not is_instance_valid(mb):
		return
	var pop := mb.get_popup()
	var names: Array = []
	for i in pop.item_count:
		if pop.is_item_checked(i):
			names.append(pop.get_item_text(i))
	mb.text = ", ".join(names) if not names.is_empty() else "(none)"


func _populate_formula_presets() -> void:
	formula_preset_option.clear()
	formula_preset_option.add_item("-- Select Preset --", -1)
	var idx = 0
	for preset_name in formula_presets:
		formula_preset_option.add_item(preset_name, idx)
		idx += 1


func _connect_signals() -> void:
	new_button.pressed.connect(_on_new_button_pressed)
	save_button.pressed.connect(_on_save_button_pressed)
	save_as_button.pressed.connect(_on_save_as_button_pressed)
	duplicate_button.pressed.connect(_on_duplicate_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	preview_button.pressed.connect(_on_preview_button_pressed)
	file_dialog.file_selected.connect(_on_file_selected)

	resource_type_selector.item_selected.connect(_on_resource_type_changed)
	refresh_button.pressed.connect(_scan_for_resources)
	resource_tree.item_selected.connect(_on_resource_tree_item_selected)
	resource_tree.item_mouse_selected.connect(_on_tree_item_mouse_selected)
	search_edit.text_changed.connect(_on_search_changed)

	ability_name_edit.text_changed.connect(_on_general_info_changed)
	description_edit.text_changed.connect(_on_general_info_changed)
	icon_path_picker.resource_changed.connect(_on_general_info_changed)
	max_level_spinbox.value_changed.connect(_on_general_info_changed)
	ability_type_option.item_selected.connect(_on_ability_type_changed)
	# required_class / required_weapon are handled by the multi-select MenuButtons
	# (_build_required_multiselects); the original OptionButtons are hidden.

	formula_help_button.pressed.connect(_show_formula_help)

	visualizer_control.draw.connect(_draw_hitbox_visualization)

	add_formula_button.pressed.connect(_on_add_formula_pressed)
	formula_preset_option.item_selected.connect(_on_preset_selected)
	formula_tree.item_selected.connect(_on_formula_tree_selected)

	# Quest editor signals
	quest_id_edit.text_changed.connect(_on_quest_field_changed)
	quest_name_edit.text_changed.connect(_on_quest_field_changed)
	quest_description_edit.text_changed.connect(_on_quest_field_changed)
	quest_required_level_spin.value_changed.connect(_on_quest_field_changed)
	quest_prereq_option.item_selected.connect(_on_quest_field_changed)
	quest_npc_only_check.toggled.connect(_on_quest_field_changed)
	quest_sort_order_spin.value_changed.connect(_on_quest_field_changed)
	quest_reward_exp_spin.value_changed.connect(_on_quest_field_changed)
	quest_reward_coins_spin.value_changed.connect(_on_quest_field_changed)
	quest_reward_items_edit.text_changed.connect(_on_quest_field_changed)
	quest_add_objective_btn.pressed.connect(_on_add_objective_pressed)


# ========================================
# FILE BROWSER
# ========================================
func _on_resource_type_changed(index: int) -> void:
	if index < 0 or index >= resource_types.size():
		return
	_guard_unsaved(func():
		current_resource_type = resource_types[index]
		var accent = CATEGORY_COLORS.get(current_resource_type.category, C_DIM)
		_update_accent(accent)
		_scan_for_resources()
		_on_new_button_pressed()
		_save_dock_state()
	)


func _scan_for_resources() -> void:
	if not current_resource_type:
		return

	_scanned_entries.clear()
	var resource_script = load(current_resource_type.script_path)
	if not resource_script:
		push_error("Could not find script: " + current_resource_type.script_path)
		_rebuild_tree()
		return

	var path = current_resource_type.base_folder
	if DirAccess.dir_exists_absolute(path):
		_collect_resources(path, resource_script, [])

	_rebuild_tree()
	_refresh_status_chrome()


func _collect_resources(path: String, script_to_match: Script, folder_parts: Array) -> void:
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var full = path.path_join(fname)
			if dir.current_is_dir():
				var sub = folder_parts.duplicate()
				sub.append(fname)
				_collect_resources(full, script_to_match, sub)
			elif fname.get_extension() == "tres":
				var res = load(full)
				if res and _script_matches_or_inherits(res.get_script(), script_to_match):
					_scanned_entries.append({
						"path": full,
						"res": res,
						"folder_parts": folder_parts,
						"name": _resource_display_name(res, fname),
					})
		fname = dir.get_next()
	dir.list_dir_end()


# Matches when res_script == target OR target is anywhere up res_script's chain.
# Without this, "Items" can't show Weapons/Armor/Consumables (which extend ItemData).
func _script_matches_or_inherits(res_script: Script, target: Script) -> bool:
	var s = res_script
	while s:
		if s == target:
			return true
		s = s.get_base_script()
	return false


func _rebuild_tree() -> void:
	resource_tree.clear()
	_path_to_tree_item.clear()
	var root = resource_tree.create_item()

	# Toggle the empty-state placeholder card based on whether we have anything.
	_update_empty_state_visibility()

	if not current_resource_type:
		return

	var accent = CATEGORY_COLORS.get(current_resource_type.category, C_DIM)
	var icon   = TYPE_ICONS.get(current_resource_type.display_name, "◈")
	var folder_items: Dictionary = {} # "a/b" -> TreeItem

	var filter_lc = _search_filter.to_lower()
	var visible_count := 0

	for entry in _scanned_entries:
		if not filter_lc.is_empty() and not str(entry.name).to_lower().contains(filter_lc):
			continue

		var parent_item = root
		var folder_key = ""
		for fname in entry.folder_parts:
			folder_key = folder_key.path_join(fname) if not folder_key.is_empty() else fname
			if folder_items.has(folder_key):
				parent_item = folder_items[folder_key]
			else:
				var folder = resource_tree.create_item(parent_item)
				folder.set_text(0, "📁  " + fname)
				folder.set_custom_color(0, C_DIM)
				folder.set_selectable(0, false)
				folder_items[folder_key] = folder
				parent_item = folder

		var item = resource_tree.create_item(parent_item)
		var validation_msg := _validate_resource(entry.res)
		var label_prefix = "⚠  " if not validation_msg.is_empty() else icon + "  "
		item.set_text(0, label_prefix + entry.name)
		item.set_metadata(0, entry.path)
		item.set_custom_color(0, C_ERR if not validation_msg.is_empty() else accent)

		# Thumbnail
		var thumb = _resource_thumbnail(entry.res)
		if thumb:
			item.set_icon(0, thumb)
			item.set_icon_max_width(0, 22)

		# Hover tooltip with quick context
		item.set_tooltip_text(0, _build_tooltip(entry, validation_msg))

		_path_to_tree_item[entry.path] = item
		visible_count += 1

	# Show the empty/no-matches placeholder as a tree row when appropriate
	if visible_count == 0:
		var empty = resource_tree.create_item(root)
		if _scanned_entries.is_empty():
			empty.set_text(0, "  No %s yet — use New or the empty-state button" % current_resource_type.display_name.to_lower())
		else:
			empty.set_text(0, "  No matches for \"%s\"" % _search_filter)
		empty.set_custom_color(0, C_DIM)
		empty.set_selectable(0, false)


# Extract the resource's icon Texture2D (varies by type) for the tree thumbnail.
func _resource_thumbnail(res: Resource) -> Texture2D:
	if not res:
		return null
	for prop in ["ability_icon", "icon", "buff_icon"]:
		if prop in res:
			var t = res.get(prop)
			if t is Texture2D:
				return t
	return null


# Returns "" when the resource looks complete, or a human-readable reason when
# something common is missing. Drives the warning chip on the tree row + title.
func _validate_resource(res: Resource) -> String:
	if not res:
		return ""
	var issues: Array[String] = []
	if res is AbilityData:
		var a := res as AbilityData
		if a.ability_name.strip_edges().is_empty():
			issues.append("missing name")
		if a.ability_icon == null:
			issues.append("no icon")
		if a.max_level <= 0:
			issues.append("max_level is 0")
		if a.scaling_data == null:
			issues.append("no scaling_data")
	elif res is QuestData:
		var q := res as QuestData
		if q.quest_id.strip_edges().is_empty():
			issues.append("missing quest_id")
		if q.quest_name.strip_edges().is_empty():
			issues.append("missing name")
		if q.objectives.is_empty():
			issues.append("no objectives")
		else:
			# A single missing target on a KILL/COLLECT objective is the most
			# common silent-failure bug — call it out specifically.
			for obj in q.objectives:
				var t := int(obj.get("type", 0))
				if t != QuestData.ObjectiveType.REACH_LEVEL and str(obj.get("target", "")).strip_edges().is_empty():
					issues.append("objective has no target")
					break
	else:
		var name_val = null
		for prop in ["name", "_discipline_name", "monster_name", "buff_name"]:
			if prop in res:
				var v = res.get(prop)
				if v != null and str(v).strip_edges() != "":
					name_val = v
					break
		if name_val == null:
			issues.append("missing name")
		if "icon" in res and res.get("icon") == null:
			issues.append("no icon")
		if "buff_icon" in res and res.get("buff_icon") == null:
			issues.append("no icon")
	return ", ".join(issues)


func _build_tooltip(entry: Dictionary, validation_msg: String) -> String:
	var lines: Array[String] = []
	lines.append(str(entry.name))
	lines.append(entry.path)
	var res: Resource = entry.res
	if res is AbilityData:
		var a := res as AbilityData
		var type_name = "Active" if a.ability_type == Constants.AbilityType.ACTIVE else "Passive"
		lines.append("%s · max_level %d" % [type_name, a.max_level])
		if not a.ability_id.is_empty():
			lines.append("id: " + a.ability_id)
	elif res is ItemData:
		var rarity_val = res.get("rarity")
		if rarity_val != null and "ItemRarity" in Constants:
			var keys = Constants.ItemRarity.keys()
			if rarity_val >= 0 and rarity_val < keys.size():
				lines.append("Rarity: " + str(keys[rarity_val]))
		var item_id = res.get("item_id")
		if item_id != null and str(item_id) != "":
			lines.append("id: " + str(item_id))
	elif res is BuffData:
		if res.get("is_debuff"):
			lines.append("Debuff")
		else:
			lines.append("Buff")
		var bid = res.get("buff_id")
		if bid != null and str(bid) != "":
			lines.append("id: " + str(bid))
	elif res is QuestData:
		var q := res as QuestData
		var bits: Array[String] = []
		bits.append("Lv %d" % q.required_level)
		bits.append("%d obj" % q.objectives.size())
		if q.reward_exp > 0:
			bits.append("%d EXP" % q.reward_exp)
		if q.reward_coins > 0:
			bits.append("%d coins" % q.reward_coins)
		if q.npc_only:
			bits.append("NPC-only")
		lines.append(" · ".join(bits))
		if not q.quest_id.is_empty():
			lines.append("id: " + q.quest_id)
		if not q.prerequisite_quest_id.is_empty():
			lines.append("after: " + q.prerequisite_quest_id)
	if not validation_msg.is_empty():
		lines.append("")
		lines.append("⚠ " + validation_msg)
	return "\n".join(lines)


# ========================================
# TREE CONTEXT MENU
# ========================================
func _ensure_context_menu() -> void:
	if is_instance_valid(_tree_context_menu):
		return
	_tree_context_menu = PopupMenu.new()
	_tree_context_menu.add_item("Open",                _CtxAction.OPEN)
	_tree_context_menu.add_separator()
	_tree_context_menu.add_item("Duplicate",           _CtxAction.DUPLICATE)
	_tree_context_menu.add_item("Delete",              _CtxAction.DELETE)
	_tree_context_menu.add_separator()
	_tree_context_menu.add_item("Reveal in FileSystem", _CtxAction.REVEAL)
	_tree_context_menu.add_item("Copy ID",              _CtxAction.COPY_ID)
	_tree_context_menu.add_item("Copy Resource Path",   _CtxAction.COPY_PATH)
	_tree_context_menu.id_pressed.connect(_on_context_menu_action)
	add_child(_tree_context_menu)


func _on_tree_item_mouse_selected(pos: Vector2, mouse_button: int) -> void:
	if mouse_button != MOUSE_BUTTON_RIGHT:
		return
	var item = resource_tree.get_selected()
	if not item:
		return
	var path = item.get_metadata(0)
	if not path or str(path).is_empty():
		return
	_tree_context_path = str(path)
	_ensure_context_menu()
	_tree_context_menu.position = Vector2i(resource_tree.get_screen_position() + pos)
	_tree_context_menu.popup()


func _on_context_menu_action(id: int) -> void:
	if _tree_context_path.is_empty():
		return
	var path = _tree_context_path
	match id:
		_CtxAction.OPEN:
			_guard_unsaved(func(): _load_resource(path))
		_CtxAction.DUPLICATE:
			# Load first so current_resource matches the menu target, then duplicate
			if not current_resource or current_resource.resource_path != path:
				_load_resource(path)
			_on_duplicate_pressed()
		_CtxAction.DELETE:
			if not current_resource or current_resource.resource_path != path:
				_load_resource(path)
			_on_delete_pressed()
		_CtxAction.REVEAL:
			if Engine.is_editor_hint():
				var fs = EditorInterface.get_file_system_dock()
				if fs:
					fs.navigate_to_path(path)
		_CtxAction.COPY_ID:
			var res = load(path)
			var id_val := ""
			if res:
				for prop in ["ability_id", "item_id", "buff_id", "quest_id", "_discipline_name"]:
					if prop in res:
						id_val = str(res.get(prop))
						break
			DisplayServer.clipboard_set(id_val)
			_set_status("Copied ID: " + id_val)
		_CtxAction.COPY_PATH:
			DisplayServer.clipboard_set(path)
			_set_status("Copied path: " + path.get_file())


# ========================================
# KEYBOARD SHORTCUTS
# ========================================
func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return

	# Don't steal keys from text-entry controls.
	var focus_owner := get_viewport().gui_get_focus_owner()
	if focus_owner is LineEdit or focus_owner is TextEdit or focus_owner is SpinBox:
		# Allow Ctrl+S even inside text fields
		if not (key.ctrl_pressed and key.keycode == KEY_S):
			return

	if key.ctrl_pressed and key.keycode == KEY_S:
		_on_save_button_pressed()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_N:
		_on_new_button_pressed()
		get_viewport().set_input_as_handled()
	elif key.ctrl_pressed and key.keycode == KEY_D:
		_on_duplicate_pressed()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_DELETE and current_resource and not current_resource.resource_path.is_empty():
		_on_delete_pressed()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_F2 and is_instance_valid(ability_name_edit) and ability_name_edit.visible:
		ability_name_edit.grab_focus()
		ability_name_edit.select_all()
		get_viewport().set_input_as_handled()
	elif key.keycode == KEY_ESCAPE and is_instance_valid(search_edit):
		if not search_edit.text.is_empty():
			search_edit.text = ""
			_on_search_changed("")
			get_viewport().set_input_as_handled()


# ========================================
# EMPTY STATE PLACEHOLDER
# ========================================
func _ensure_empty_state() -> void:
	if is_instance_valid(_empty_state_panel):
		return
	_empty_state_panel = PanelContainer.new()
	_empty_state_panel.visible = false
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_CARD
	sb.border_color = Color(_current_accent, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(8)
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 18
	sb.content_margin_bottom = 18
	_empty_state_panel.add_theme_stylebox_override("panel", sb)
	_accent_appliers.append(func(c: Color):
		sb.border_color = Color(c, 0.35)
	)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty_state_panel.add_child(col)

	_empty_state_label = Label.new()
	_empty_state_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_state_label.add_theme_font_size_override("font_size", 12)
	_empty_state_label.add_theme_color_override("font_color", C_DIM)
	col.add_child(_empty_state_label)

	var btn = Button.new()
	btn.text = "  + Create first one  "
	btn.pressed.connect(_on_new_button_pressed)
	_style_btn(btn, _current_accent, true)
	col.add_child(btn)

	# Insert above the resource tree
	var browser = $Panel/MainHSplit/ResourceBrowser
	browser.add_child(_empty_state_panel)
	browser.move_child(_empty_state_panel, resource_tree.get_index())


func _update_empty_state_visibility() -> void:
	_ensure_empty_state()
	if _scanned_entries.is_empty() and current_resource_type:
		if is_instance_valid(_empty_state_label):
			_empty_state_label.text = "No %s in this project yet." % current_resource_type.display_name
		_empty_state_panel.visible = true
		resource_tree.visible = false
	else:
		_empty_state_panel.visible = false
		resource_tree.visible = true


func _on_search_changed(new_text: String) -> void:
	_search_filter = new_text.strip_edges()
	_rebuild_tree()
	_refresh_status_chrome()


func _resource_display_name(res: Resource, fallback: String) -> String:
	for prop in ["ability_name", "quest_name", "name", "_discipline_name", "monster_name", "buff_name"]:
		var val = res.get(prop) if res.has_method("get") else null
		if val != null and str(val) != "":
			return str(val)
	return fallback.get_basename()


# ========================================
# FILE OPERATIONS
# ========================================
func _on_new_button_pressed() -> void:
	if not current_resource_type:
		return
	_guard_unsaved(func():
		resource_tree.deselect_all()
		_disconnect_dirty_tracking()
		current_resource = ResourceTypeConfig.create_new_resource(current_resource_type)
		if current_resource is AbilityData:
			current_scaling_data = current_resource.scaling_data
		_connect_dirty_tracking()
		_set_dirty(false)
		# Reactive title
		if _title_label and current_resource_type:
			var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈")
			_title_label.text = icon + "  New " + current_resource_type.display_name
		if is_instance_valid(_status_label):
			_status_label.text = "New %s — fill in the fields and save." % current_resource_type.display_name
			_status_label.add_theme_color_override("font_color", C_DIM)
			_status_version += 1
		_update_ui()
	)


func _on_save_button_pressed() -> void:
	if not current_resource:
		return
	if current_resource.resource_path.is_empty():
		_on_save_as_button_pressed()
	else:
		_save_resource(current_resource.resource_path)


func _on_save_as_button_pressed() -> void:
	if not current_resource_type:
		return
	file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	file_dialog.clear_filters()
	file_dialog.add_filter("*.tres", current_resource_type.display_name + " Resource")
	if not current_resource_type.base_folder.is_empty() and DirAccess.dir_exists_absolute(current_resource_type.base_folder):
		file_dialog.current_dir = current_resource_type.base_folder
	file_dialog.popup_centered()


func _on_file_selected(path: String) -> void:
	if file_dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		_save_resource(path)
	elif file_dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE:
		_load_resource(path)


func _save_resource(path: String) -> void:
	if not current_resource:
		return
	var err = ResourceSaver.save(current_resource, path)
	if err == OK:
		# Persist any pending upgrade-field edits, then re-point the editor at the
		# (possibly newly-assigned) ability path.
		if current_resource is AbilityData and is_instance_valid(_upgrade_editor):
			_upgrade_editor.save_all()
			_upgrade_editor.set_ability(current_resource, current_resource.resource_path)
		_set_dirty(false)
		_invalidate_related_index()  # refs may have changed
		_set_status("Saved → " + path.get_file())
		_scan_for_resources()
		var item = _path_to_tree_item.get(current_resource.resource_path, null)
		if item:
			item.select(0)
	else:
		_set_status("Save failed (error %d)" % err, true)


func _load_resource(path: String) -> void:
	_disconnect_dirty_tracking()
	current_resource = load(path)
	if not current_resource:
		_set_status("Failed to load: " + path.get_file(), true)
		return

	if current_resource is AbilityData:
		var ability = current_resource as AbilityData
		if ability.scaling_data:
			current_scaling_data = ability.scaling_data
		if not ability.active_behavior:
			ability.active_behavior = ActiveBehaviorData.new()
			ability.active_behavior.resource_local_to_scene = true
		if not ability.scaling_data:
			ability.scaling_data = AbilityScalingData.new()
			ability.scaling_data.resource_local_to_scene = true
			current_scaling_data = ability.scaling_data

	_connect_dirty_tracking()
	_set_dirty(false)
	_update_ui()
	_set_status("Loaded: " + path.get_file())
	_save_dock_state()


func _on_resource_tree_item_selected() -> void:
	var selected = resource_tree.get_selected()
	if not selected:
		return
	var path = selected.get_metadata(0)
	if not path or path.is_empty():
		return
	if current_resource and current_resource.resource_path == path:
		return
	_guard_unsaved(func(): _load_resource(path))


# ========================================
# DUPLICATE / DELETE
# ========================================
func _on_duplicate_pressed() -> void:
	if not current_resource:
		_set_status("Nothing to duplicate.", true)
		return
	var dup = current_resource.duplicate(true)
	dup.resource_path = ""
	if dup is AbilityData:
		var ab = dup as AbilityData
		if ab.ability_name:
			ab.ability_name = ab.ability_name + " (Copy)"
	elif dup is QuestData:
		var dq = dup as QuestData
		# Wipe quest_id so save data doesn't accidentally reuse the source quest's
		# progress — quest_id is the persistence key and must be unique per quest.
		dq.quest_id = ""
		if not dq.quest_name.is_empty():
			dq.quest_name = dq.quest_name + " (Copy)"
	else:
		var n = dup.get("name")
		if n != null and str(n) != "":
			dup.set("name", str(n) + " (Copy)")
	_disconnect_dirty_tracking()
	current_resource = dup
	if current_resource is AbilityData:
		current_scaling_data = current_resource.scaling_data
	_connect_dirty_tracking()
	_set_dirty(true)
	resource_tree.deselect_all()
	_update_ui()
	_set_status("Duplicated — Save As to write a new file.")


func _on_delete_pressed() -> void:
	if not current_resource or current_resource.resource_path.is_empty():
		_set_status("Nothing to delete (resource is unsaved).", true)
		return

	if not is_instance_valid(_confirm_delete_dialog):
		_confirm_delete_dialog = ConfirmationDialog.new()
		_confirm_delete_dialog.title = "Delete Resource"
		_confirm_delete_dialog.ok_button_text = "Delete"
		_confirm_delete_dialog.confirmed.connect(_perform_delete)
		_style_popup_window(_confirm_delete_dialog)
		add_child(_confirm_delete_dialog)
	_confirm_delete_dialog.dialog_text = "Permanently delete this file?\n\n%s" % current_resource.resource_path
	_confirm_delete_dialog.popup_centered()


func _perform_delete() -> void:
	if not current_resource or current_resource.resource_path.is_empty():
		return
	var path = current_resource.resource_path
	var os_path = ProjectSettings.globalize_path(path)
	var err = DirAccess.remove_absolute(os_path)
	if err == OK:
		# Best-effort cleanup of Godot's UID sidecar
		var uid_path = os_path + ".uid"
		if FileAccess.file_exists(uid_path):
			DirAccess.remove_absolute(uid_path)
		_set_status("Deleted → " + path.get_file())
		_disconnect_dirty_tracking()
		current_resource = null
		current_scaling_data = null
		_scan_for_resources()
		_on_new_button_pressed()
	else:
		_set_status("Delete failed (error %d)" % err, true)


# ========================================
# DIRTY STATE TRACKING
# ========================================
func _connect_dirty_tracking() -> void:
	if not current_resource:
		return
	if not current_resource.changed.is_connected(_on_current_resource_changed):
		current_resource.changed.connect(_on_current_resource_changed)
	# Inspector edits target sub-resources whose `changed` won't bubble up. Hook
	# the common ones so any inspector edit still flips dirty state.
	for sub in _ability_subresources(current_resource):
		if sub and not sub.changed.is_connected(_on_current_resource_changed):
			sub.changed.connect(_on_current_resource_changed)


func _disconnect_dirty_tracking() -> void:
	if not current_resource:
		return
	if current_resource.changed.is_connected(_on_current_resource_changed):
		current_resource.changed.disconnect(_on_current_resource_changed)
	for sub in _ability_subresources(current_resource):
		if sub and sub.changed.is_connected(_on_current_resource_changed):
			sub.changed.disconnect(_on_current_resource_changed)


# Returns sub-resources of an AbilityData whose changed signal we want to track.
# Tolerates missing properties via `in` so AbilityData shape changes don't crash.
func _ability_subresources(res: Resource) -> Array:
	var out: Array = []
	if not (res is AbilityData):
		return out
	for prop_name in ["scaling_data", "active_behavior", "level_data"]:
		if not (prop_name in res):
			continue
		var val = res.get(prop_name)
		if val is Resource:
			out.append(val)
		elif val is Array:
			for entry in val:
				if entry is Resource:
					out.append(entry)
	return out


func _on_current_resource_changed() -> void:
	if is_updating_ui:
		return
	_set_dirty(true)
	# Live-update tree label when name changes
	if current_resource and not current_resource.resource_path.is_empty():
		var item: TreeItem = _path_to_tree_item.get(current_resource.resource_path, null)
		if item:
			var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈") if current_resource_type else "◈"
			item.set_text(0, icon + "  " + _resource_display_name(current_resource, current_resource.resource_path.get_file()))
	# Live-update title
	if _title_label and current_resource_type:
		var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈")
		var rname = _resource_display_name(current_resource, current_resource_type.display_name)
		_title_label.text = ("● " if _dirty else "") + icon + "  " + rname


func _set_dirty(dirty: bool) -> void:
	_dirty = dirty
	if not _title_label:
		return
	var text = _title_label.text
	var has_marker = text.begins_with("● ")
	if dirty and not has_marker:
		_title_label.text = "● " + text
	elif not dirty and has_marker:
		_title_label.text = text.substr(2)


# Show an unsaved-changes prompt before running `action`; otherwise run it now.
func _guard_unsaved(action: Callable) -> void:
	if not _dirty or not current_resource:
		action.call()
		return

	if not is_instance_valid(_unsaved_dialog):
		_unsaved_dialog = ConfirmationDialog.new()
		_unsaved_dialog.title = "Unsaved Changes"
		_unsaved_dialog.dialog_text = "You have unsaved changes. Discard them?"
		_unsaved_dialog.ok_button_text = "Discard"
		_unsaved_dialog.confirmed.connect(func():
			if _pending_action.is_valid():
				var a = _pending_action
				_pending_action = Callable()
				_set_dirty(false)
				a.call()
		)
		_style_popup_window(_unsaved_dialog)
		add_child(_unsaved_dialog)
	_pending_action = action
	_unsaved_dialog.popup_centered()


# ========================================
# UI UPDATE - MAIN
# ========================================
func _update_ui() -> void:
	if not current_resource:
		return

	is_updating_ui = true

	# Reactive title: show type icon + resource name (preserve dirty marker)
	if _title_label and current_resource_type:
		var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈")
		var rname = _resource_display_name(current_resource, current_resource_type.display_name)
		_title_label.text = ("● " if _dirty else "") + icon + "  " + rname

	if current_resource is AbilityData:
		var ability = current_resource as AbilityData
		_show_ability_ui()

		ability_id_edit.text = ability.ability_id
		ability_name_edit.text = ability.ability_name
		description_edit.text = ability.description
		icon_path_picker.set_edited_resource(ability.ability_icon)
		max_level_spinbox.value = ability.max_level
		ability_type_option.selected = ability.ability_type

		_set_multiselect_ids(_req_class_menu, ability.required_class)
		_set_multiselect_ids(_req_weapon_menu, ability.required_weapon_types)

		# Ensure scaling_data exists, then refresh the formula tree
		if not ability.scaling_data:
			ability.scaling_data = AbilityScalingData.new()
			ability.scaling_data.resource_local_to_scene = true
			current_scaling_data = ability.scaling_data
		_update_formula_tree()
		_update_active_behavior_ui()
		_update_advanced_ui(ability)
		if is_instance_valid(_upgrade_editor):
			_upgrade_editor.set_ability(ability, ability.resource_path)
	elif current_resource is QuestData:
		_show_quest_ui()
		_update_quest_ui()
	else:
		_hide_ability_ui()
		_hide_quest_ui()
		if generic_resource_inspector:
			generic_resource_inspector.edit(current_resource)

	# VFX Effects type gets a live animated preview below its inspector.
	_update_vfx_effect_ui()

	# Cross-resource "Related" links (shown for any type that has relations).
	_update_related_ui(current_resource)

	is_updating_ui = false


func _show_ability_ui() -> void:
	_set_section_visible(general_settings_panel, true)
	_set_section_visible(formula_editor_panel, true)
	_set_section_visible(active_behavior_panel, true)
	_set_section_visible(quest_editor_panel, false)
	_set_advanced_card_visible(true)
	_set_upgrade_card_visible(true)
	if generic_resource_inspector:
		_set_section_visible(generic_resource_inspector, false)
		generic_resource_inspector.edit(null)


func _hide_ability_ui() -> void:
	_set_section_visible(general_settings_panel, false)
	_set_section_visible(formula_editor_panel, false)
	_set_section_visible(active_behavior_panel, false)
	_set_advanced_card_visible(false)
	_set_upgrade_card_visible(false)
	if generic_resource_inspector:
		_set_section_visible(generic_resource_inspector, true)


# ── Quest UI section toggles ──────────────────────────────────────────────────
func _show_quest_ui() -> void:
	_set_section_visible(general_settings_panel, false)
	_set_section_visible(formula_editor_panel, false)
	_set_section_visible(active_behavior_panel, false)
	_set_section_visible(quest_editor_panel, true)
	_set_advanced_card_visible(false)
	_set_upgrade_card_visible(false)
	if generic_resource_inspector:
		_set_section_visible(generic_resource_inspector, false)
		generic_resource_inspector.edit(null)


func _hide_quest_ui() -> void:
	_set_section_visible(quest_editor_panel, false)


# Toggle a section AND its wrapping card (from _wrap_in_card) together, so non-
# ability resources don't see empty card outlines stacked above the inspector.
func _set_section_visible(section: Control, vis: bool) -> void:
	if not is_instance_valid(section):
		return
	section.visible = vis
	var parent = section.get_parent()
	if parent and parent is PanelContainer and str(parent.name).ends_with("Card"):
		parent.visible = vis


func _update_active_behavior_ui() -> void:
	if not current_resource or not current_resource is AbilityData:
		_set_section_visible(active_behavior_panel, false)
		active_behavior_inspector.edit(null)
		return

	var ability = current_resource as AbilityData
	if ability.ability_type == Constants.AbilityType.ACTIVE:
		_set_section_visible(active_behavior_panel, true)
		active_behavior_inspector.edit(ability.active_behavior)
		_build_vfx_section()
		_update_vfx_ui(ability)
		if ability.active_behavior:
			if not ability.active_behavior.changed.is_connected(_on_active_behavior_changed):
				ability.active_behavior.changed.connect(_on_active_behavior_changed)
			if not visualizer_player_sprite.texture:
				var t = load("res://assets/UI/beginner_portrait.tres")
				if t:
					visualizer_player_sprite.texture = t
			_update_visualizer_sprite_pos()
			_update_visualizer_vfx()
			visualizer_control.queue_redraw()
	else:
		_set_section_visible(active_behavior_panel, false)
		active_behavior_inspector.edit(null)
		_update_visualizer_vfx()  # hides the overlay for passives


# ========================================
# VFX OVERRIDE SECTION (cast / hit effect picker + preview)
# ========================================

## Builds the VFX picker once, inserted directly under the ActiveBehavior
## inspector and above the hitbox visualizer. Two dropdowns (cast / hit) listing
## every VfxCatalog key plus "(auto)", a label showing what the ability actually
## resolves to, and two looping preview sprites.
func _build_vfx_section() -> void:
	if is_instance_valid(_vfx_section):
		return
	var content_vbox = active_behavior_inspector.get_parent()
	if not is_instance_valid(content_vbox):
		return

	_vfx_section = VBoxContainer.new()
	_vfx_section.name = "VfxOverrideSection"
	_vfx_section.add_theme_constant_override("separation", 6)

	# Header.
	var header = Label.new()
	header.text = "✦ Ability VFX"
	header.add_theme_color_override("font_color", C_TEXT)
	header.add_theme_font_size_override("font_size", 13)
	_vfx_section.add_child(header)

	var hint = Label.new()
	hint.text = "Pick an effect, or leave (auto) to use the per-ability default. Cast plays at the caster; Hit plays on each struck enemy."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_color_override("font_color", C_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	_vfx_section.add_child(hint)

	_vfx_cast_option = _make_vfx_row("Cast VFX:")
	_vfx_hit_option = _make_vfx_row("Hit VFX:")

	# Resolved-effect readout (what the ability will actually use).
	_vfx_resolved_label = Label.new()
	_vfx_resolved_label.add_theme_color_override("font_color", C_OK)
	_vfx_resolved_label.add_theme_font_size_override("font_size", 11)
	_vfx_section.add_child(_vfx_resolved_label)

	# Preview row — two looping tiles, cast on the left, hit on the right.
	var preview_row = HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 14)
	preview_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_vfx_cast_preview = _make_vfx_preview_tile(preview_row, "Cast")
	_vfx_hit_preview = _make_vfx_preview_tile(preview_row, "Hit")
	_vfx_section.add_child(preview_row)

	content_vbox.add_child(_vfx_section)
	# Place right after the inspector, before the visualizer.
	content_vbox.move_child(_vfx_section, active_behavior_inspector.get_index() + 1)


## Builds one labeled OptionButton row populated with every VfxCatalog key plus a
## leading "(auto)" entry, appends it to _vfx_section, wires its change signal,
## and returns the OptionButton.
func _make_vfx_row(label_text: String) -> OptionButton:
	var row = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl = Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(90, 0)
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)

	var ob = OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_option_button(ob)
	_populate_vfx_option_items(ob)
	row.add_child(ob)
	_vfx_section.add_child(row)
	ob.item_selected.connect(func(_i): _on_vfx_override_changed())
	return ob


## (Re)fills a VFX dropdown with the current catalog keys: "(auto)" → "" (unset:
## cast = none, hit = weapon fallback), "None" → NONE_KEY (explicitly suppress), then every
## concrete catalog key. Called on first build AND each time the picker is shown,
## so a VfxEffectData .tres you just added/renamed appears without an editor
## restart. Selection is restored by the caller via _select_vfx_option.
func _populate_vfx_option_items(ob: OptionButton) -> void:
	ob.clear()
	ob.add_item("(auto)", 0)
	ob.set_item_metadata(0, "")
	ob.add_item("None (no effect)", 1)
	ob.set_item_metadata(1, VfxCatalog.NONE_KEY)
	var idx := 2
	for key in VfxCatalog.all_keys():
		ob.add_item(key, idx)
		ob.set_item_metadata(idx, key)
		idx += 1


## Builds a captioned preview tile (a dark panel holding a looping
## AnimatedSprite2D) and appends it to `parent`. Returns the AnimatedSprite2D.
func _make_vfx_preview_tile(parent: Control, caption: String) -> AnimatedSprite2D:
	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var cap = Label.new()
	cap.text = caption
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.add_theme_color_override("font_color", C_DIM)
	cap.add_theme_font_size_override("font_size", 11)
	col.add_child(cap)

	var pc = PanelContainer.new()
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_DARK.darkened(0.10)
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	pc.add_theme_stylebox_override("panel", sb)

	var holder = Control.new()
	holder.custom_minimum_size = Vector2(96, 96)
	var spr = AnimatedSprite2D.new()
	spr.position = Vector2(48, 48)  # center of the 96×96 tile
	holder.add_child(spr)
	pc.add_child(holder)
	col.add_child(pc)
	parent.add_child(col)
	return spr


## Syncs the dropdowns, resolved-effect label, and previews to the given ability.
func _update_vfx_ui(ability: AbilityData) -> void:
	if not is_instance_valid(_vfx_cast_option):
		return
	# Re-scan resources/VFX/ and rebuild the option lists so a VfxEffectData you
	# just created/renamed shows up immediately (the catalog caches its folder
	# scan; invalidate forces a fresh read).
	VfxCatalog.invalidate()
	_populate_vfx_option_items(_vfx_cast_option)
	_populate_vfx_option_items(_vfx_hit_option)
	var ab = ability.active_behavior
	# .get() + String coercion: a placeholder/stale resource instance can hand
	# back Nil for an exported property, which the typed helpers below reject.
	var cast_override: String = _vfx_key_str(ab, "cast_vfx")
	var hit_override: String = _vfx_key_str(ab, "hit_vfx")
	_select_vfx_option(_vfx_cast_option, cast_override)
	_select_vfx_option(_vfx_hit_option, hit_override)

	# Resolved keys = what the ability ACTUALLY uses (explicit cast_vfx/hit_vfx,
	# else "" for cast / weapon-element fallback for hit). Shown even on (auto).
	var resolved_cast: String = VfxCatalog.resolve_cast(ability)
	var resolved_hit: String = VfxCatalog.resolve_hit(ability)
	_vfx_resolved_label.text = "Resolves to →  Cast: %s    Hit: %s" % [
		resolved_cast if resolved_cast != "" else "(none)",
		resolved_hit if resolved_hit != "" else "(none)"]

	_play_vfx_preview(_vfx_cast_preview, resolved_cast)
	_play_vfx_preview(_vfx_hit_preview, resolved_hit)


## Null-safe read of a String override property off an ActiveBehaviorData. .get()
## avoids an "invalid index" error on a stale/placeholder instance; non-String
## (including Nil) coerces to "" so the typed pickers never receive Nil.
func _vfx_key_str(ab, prop: String) -> String:
	if ab == null:
		return ""
	var v = ab.get(prop)
	return v if v is String else ""


## Selects the OptionButton item whose metadata equals `key` (falls back to the
## leading "(auto)" entry).
func _select_vfx_option(ob: OptionButton, key: String) -> void:
	for i in range(ob.item_count):
		if str(ob.get_item_metadata(i)) == key:
			ob.select(i)
			return
	ob.select(0)


## Plays a catalog effect on a preview sprite, looping regardless of the recipe's
## one-shot flag (a duplicated SpriteFrames so the shared gameplay cache stays
## one-shot), scaled to fit the 96×96 tile. Empty key clears the tile.
func _play_vfx_preview(spr: AnimatedSprite2D, key: String) -> void:
	if not is_instance_valid(spr):
		return
	if key == "":
		spr.sprite_frames = null
		return
	var src := VfxCatalog.get_frames(key)
	if src == null:
		spr.sprite_frames = null
		return
	var sf: SpriteFrames = src.duplicate(true)
	sf.set_animation_loop("play", true)
	spr.sprite_frames = sf
	spr.animation = "play"
	var def: Dictionary = VfxCatalog.get_def(key)
	# Fit the largest frame dimension into ~72px so big sheets don't overflow.
	var frame_dim: float = float(maxi(int(def.get("fw", 32)), int(def.get("fh", 32))))
	var fit: float = 72.0 / maxf(1.0, frame_dim)
	spr.scale = Vector2.ONE * fit
	spr.modulate = def.get("modulate", Color.WHITE)
	spr.play("play")


## Writes the dropdown selections back to the ActiveBehaviorData and refreshes.
func _on_vfx_override_changed() -> void:
	if is_updating_ui or not current_resource or not current_resource is AbilityData:
		return
	var ability := current_resource as AbilityData
	var ab := ability.active_behavior
	if not ab:
		return
	var cast_meta = _vfx_cast_option.get_item_metadata(_vfx_cast_option.selected)
	var hit_meta = _vfx_hit_option.get_item_metadata(_vfx_hit_option.selected)
	ab.cast_vfx = str(cast_meta) if cast_meta != null else ""
	ab.hit_vfx = str(hit_meta) if hit_meta != null else ""
	ab.emit_changed()  # marks the inspector + dirty tracking
	_set_dirty(true)
	_update_vfx_ui(ability)  # refresh resolved label + previews
	_update_visualizer_vfx()  # refresh the overlay on the character/hitbox


# ========================================
# VFX EFFECTS TYPE — live animated preview
# ========================================

## Builds the preview panel once (a captioned dark tile holding an
## AnimatedSprite2D) directly under the generic inspector.
func _build_vfx_effect_preview() -> void:
	if is_instance_valid(_vfx_effect_panel):
		return
	if not is_instance_valid(generic_resource_inspector):
		return
	# The inspector is wrapped in a single-child "…Card" PanelContainer, so the
	# preview must be a sibling of that card (under EditorContent), not a second
	# child of the card. Fall back to the direct parent if unwrapped.
	var anchor: Control = generic_resource_inspector
	var parent = anchor.get_parent()
	if is_instance_valid(parent) and str(parent.name).ends_with("Card"):
		anchor = parent
		parent = parent.get_parent()
	if not is_instance_valid(parent):
		return

	_vfx_effect_panel = PanelContainer.new()
	_vfx_effect_panel.name = "VfxEffectPreview"
	var sb = StyleBoxFlat.new()
	sb.bg_color = C_DARK.darkened(0.10)
	sb.border_color = C_BORDER
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	_vfx_effect_panel.add_theme_stylebox_override("panel", sb)

	var col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.alignment = BoxContainer.ALIGNMENT_CENTER

	var title = Label.new()
	title.text = "✨ Live Preview"
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 13)
	col.add_child(title)

	var stage = Control.new()
	stage.custom_minimum_size = Vector2(0, 520)
	stage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stage.size_flags_vertical = Control.SIZE_EXPAND_FILL
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_STOP
	stage.tooltip_text = "Left-drag: set offset  •  Middle-drag: pan  •  Wheel: zoom.\nCrosshair = offset (0,0); line = floor."
	stage.gui_input.connect(_on_vfx_preview_gui_input)
	_vfx_effect_stage = stage
	# Floor line at the feet + the offset=0 anchor crosshair (positions computed
	# in _refresh and cached in _vfx_anchor_screen so the draw stays cheap).
	stage.draw.connect(func():
		var fy: float = stage.size.y - _VFX_PREVIEW_FEET_MARGIN
		stage.draw_line(Vector2(0, fy), Vector2(stage.size.x, fy), Color(0.4, 0.45, 0.5, 0.4), 1.0)
		var a := _vfx_anchor_screen
		var mc := Color(0.5, 0.6, 0.75, 0.7)
		stage.draw_line(a - Vector2(8, 0), a + Vector2(8, 0), mc, 1.0)
		stage.draw_line(a - Vector2(0, 8), a + Vector2(0, 8), mc, 1.0)
		stage.draw_circle(a, 2.0, mc))
	stage.resized.connect(func():
		stage.queue_redraw()
		if current_resource is VfxEffectData:
			_refresh_vfx_effect_preview(current_resource))
	# Faint character reference (the same portrait the ability hitbox visualizer
	# uses, positioned/scaled the same way) so the offset is judged against a body.
	_vfx_effect_char = Sprite2D.new()
	_vfx_effect_char.modulate = Color(1, 1, 1, 0.4)
	var portrait = load("res://assets/UI/beginner_portrait.tres")
	if portrait:
		_vfx_effect_char.texture = portrait
	stage.add_child(_vfx_effect_char)
	_vfx_effect_sprite = AnimatedSprite2D.new()
	stage.add_child(_vfx_effect_sprite)
	col.add_child(stage)

	# Zoom controls (mirrors the hitbox visualizer).
	var zrow := HBoxContainer.new()
	zrow.alignment = BoxContainer.ALIGNMENT_CENTER
	zrow.add_theme_constant_override("separation", 6)
	var zout := Button.new()
	zout.text = " − "
	zout.tooltip_text = "Zoom out"
	zout.pressed.connect(func(): _vfx_set_zoom(_vfx_preview_zoom / 1.25))
	_style_btn(zout, C_DIM, false)
	zrow.add_child(zout)
	_vfx_zoom_label = Label.new()
	_vfx_zoom_label.text = "%.1f×" % _vfx_preview_zoom
	_vfx_zoom_label.custom_minimum_size = Vector2(50, 0)
	_vfx_zoom_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vfx_zoom_label.add_theme_color_override("font_color", C_DIM)
	_vfx_zoom_label.add_theme_font_size_override("font_size", 11)
	zrow.add_child(_vfx_zoom_label)
	var zin := Button.new()
	zin.text = " + "
	zin.tooltip_text = "Zoom in"
	zin.pressed.connect(func(): _vfx_set_zoom(_vfx_preview_zoom * 1.25))
	_style_btn(zin, C_DIM, false)
	zrow.add_child(zin)
	var zreset := Button.new()
	zreset.text = " Reset "
	zreset.tooltip_text = "Reset zoom + pan"
	zreset.pressed.connect(_vfx_reset_view)
	_style_btn(zreset, C_DIM, false)
	zrow.add_child(zreset)
	col.add_child(zrow)

	_vfx_effect_info = Label.new()
	_vfx_effect_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vfx_effect_info.add_theme_color_override("font_color", C_DIM)
	_vfx_effect_info.add_theme_font_size_override("font_size", 11)
	col.add_child(_vfx_effect_info)

	_vfx_effect_panel.add_child(col)
	parent.add_child(_vfx_effect_panel)
	parent.move_child(_vfx_effect_panel, anchor.get_index() + 1)


## Shows + drives the preview while a VfxEffectData is the current resource;
## hides it for any other type. Connects the resource's `changed` signal so
## editing fps/scale/tint/sheet/frames updates the animation immediately and
## invalidates the runtime catalog cache so live gameplay reloads on next use.
func _update_vfx_effect_ui() -> void:
	var is_vfx: bool = current_resource is VfxEffectData
	_build_vfx_effect_preview()
	if not is_instance_valid(_vfx_effect_panel):
		return
	_vfx_effect_panel.visible = is_vfx
	if not is_vfx:
		return

	var vfx := current_resource as VfxEffectData
	if not vfx.changed.is_connected(_on_vfx_effect_changed):
		vfx.changed.connect(_on_vfx_effect_changed)
	_refresh_vfx_effect_preview(vfx)


## Rebuilds the preview animation from the (possibly unsaved) resource, looping
## regardless of the recipe's one-shot flag, scaled to fit the stage.
func _refresh_vfx_effect_preview(vfx: VfxEffectData) -> void:
	if not is_instance_valid(_vfx_effect_sprite):
		return
	var sf: SpriteFrames = VfxCatalog.build_frames_from_resource(vfx)
	if sf == null:
		_vfx_effect_sprite.sprite_frames = null
		_vfx_effect_info.text = "(no sheet assigned)"
		return
	sf.set_animation_loop("play", true)  # always loop in the editor
	_vfx_effect_sprite.sprite_frames = sf
	_vfx_effect_sprite.animation = "play"
	_vfx_effect_sprite.modulate = vfx.modulate

	# Faithful in-game frame: feet = origin, zoom magnifies. The effect's real
	# scale (vfx.scale) and the offset are BOTH multiplied by the same zoom, so
	# what you place here is exactly what spawns in game (just larger on screen).
	var z: float = _vfx_preview_zoom
	var feet := _vfx_preview_feet()
	var aoff := _vfx_anchor_world(vfx)            # world anchor (cast=body, ground=feet)
	var off: Vector2 = vfx.offset if vfx.offset is Vector2 else Vector2.ZERO
	_vfx_anchor_screen = feet + aoff * z

	# Character ref: same placement/scale convention as the hitbox visualizer.
	if is_instance_valid(_vfx_effect_char) and _vfx_effect_char.texture != null:
		_vfx_effect_char.scale = Vector2.ONE * GAME_PLAYER_SCALE * z
		_vfx_effect_char.position = feet + Vector2(0, (GAME_PLAYER_OFFSET_Y * z) / GAME_PLAYER_SCALE)

	_vfx_effect_sprite.scale = Vector2.ONE * maxf(0.05, vfx.scale) * z
	_vfx_effect_sprite.position = feet + (aoff + off) * z
	_vfx_effect_sprite.play("play")
	if is_instance_valid(_vfx_effect_stage):
		_vfx_effect_stage.queue_redraw()  # move the crosshair/floor markers

	var n: int = sf.get_frame_count("play")
	var faces: bool = vfx.face_direction if vfx.face_direction is bool else true
	_vfx_effect_info.text = "%s  •  %d frames @ %.0f fps  •  %s  •  offset (%.0f, %.0f)  •  %s" % [
		vfx.effect_key if vfx.effect_key != "" else "(no key)",
		n, vfx.fps, "loop" if vfx.loop else "one-shot",
		off.x, off.y, "faces dir" if faces else "no flip"]


## Character FEET point in the preview (the in-game cast origin), including pan.
func _vfx_preview_feet() -> Vector2:
	var sw: float = _vfx_effect_stage.size.x if is_instance_valid(_vfx_effect_stage) else 240.0
	var sh: float = _vfx_effect_stage.size.y if is_instance_valid(_vfx_effect_stage) else 190.0
	return Vector2(sw * 0.5, sh - _VFX_PREVIEW_FEET_MARGIN) + _vfx_preview_pan


## World-space anchor (offset=0 point) for an effect by its category, matching
## in-game: ground effects sit at the feet; cast/impact at body-center.
func _vfx_anchor_world(vfx: VfxEffectData) -> Vector2:
	if vfx != null and vfx.category == "ground":
		return Vector2.ZERO
	return _VIS_CAST_BODY_OFFSET


## Live-update on any inspector edit; also drop the runtime cache so a saved
## change is picked up in-game without an editor restart.
func _on_vfx_effect_changed() -> void:
	if not (current_resource is VfxEffectData):
		return
	VfxCatalog.invalidate()
	_refresh_vfx_effect_preview(current_resource as VfxEffectData)


## Preview interaction: LEFT-drag sets the effect's offset; MIDDLE-drag pans the
## view; mouse WHEEL zooms (around the cursor). Pan/zoom are view-only and never
## change the saved offset.
func _on_vfx_preview_gui_input(event: InputEvent) -> void:
	if not (current_resource is VfxEffectData) or not is_instance_valid(_vfx_effect_stage):
		return
	var vfx := current_resource as VfxEffectData
	var mb := event as InputEventMouseButton
	if mb != null:
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				if mb.pressed:
					_vfx_dragging = true
					_set_vfx_offset_from_pos(vfx, mb.position)
				elif _vfx_dragging:
					_vfx_dragging = false
					vfx.emit_changed()  # commit: dirty + cache invalidate
					_set_dirty(true)
				return
			MOUSE_BUTTON_MIDDLE:
				_vfx_panning = mb.pressed
				return
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_vfx_zoom_at(mb.position, 1.15)
				return
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_vfx_zoom_at(mb.position, 1.0 / 1.15)
				return
	var mm := event as InputEventMouseMotion
	if mm != null:
		if _vfx_dragging:
			_set_vfx_offset_from_pos(vfx, mm.position)
		elif _vfx_panning:
			_vfx_preview_pan += mm.relative
			_refresh_vfx_effect_preview(vfx)


## Zooms by `factor` while keeping the world point under `pivot` fixed on screen,
## then refreshes. Pan is adjusted so the cursor stays anchored (intuitive zoom).
func _vfx_zoom_at(pivot: Vector2, factor: float) -> void:
	var old_z: float = _vfx_preview_zoom
	var new_z: float = clampf(old_z * factor, _VFX_PREVIEW_MIN_ZOOM, _VFX_PREVIEW_MAX_ZOOM)
	if is_equal_approx(new_z, old_z):
		return
	# Keep the world point under the cursor put: world = (pivot - feet)/old_z,
	# and we want feet' so pivot = feet' + world*new_z. feet includes pan, so the
	# pan delta is the feet delta.
	var feet := _vfx_preview_feet()
	var world := (pivot - feet) / old_z
	var new_feet := pivot - world * new_z
	_vfx_preview_pan += (new_feet - feet)
	_vfx_preview_zoom = new_z
	if is_instance_valid(_vfx_zoom_label):
		_vfx_zoom_label.text = "%.1f×" % _vfx_preview_zoom
	if current_resource is VfxEffectData:
		_refresh_vfx_effect_preview(current_resource as VfxEffectData)


## Sets zoom directly (buttons), zooming around the stage center.
func _vfx_set_zoom(value: float) -> void:
	if is_instance_valid(_vfx_effect_stage):
		_vfx_zoom_at(_vfx_effect_stage.size * 0.5, value / maxf(0.01, _vfx_preview_zoom))


## Resets zoom + pan to the default framing.
func _vfx_reset_view() -> void:
	_vfx_preview_zoom = _VFX_PREVIEW_DEFAULT_ZOOM
	_vfx_preview_pan = Vector2.ZERO
	if is_instance_valid(_vfx_zoom_label):
		_vfx_zoom_label.text = "%.1f×" % _vfx_preview_zoom
	if current_resource is VfxEffectData:
		_refresh_vfx_effect_preview(current_resource as VfxEffectData)


## Sets the effect's offset from a preview-local mouse position, inverting the
## same feet/anchor/zoom transform used to draw it — so the resulting offset is
## in WORLD px and equals what spawns in game. Rounded to whole px; live-refreshes
## without committing (the commit happens on mouse release).
func _set_vfx_offset_from_pos(vfx: VfxEffectData, local_pos: Vector2) -> void:
	var z: float = _vfx_preview_zoom
	var feet := _vfx_preview_feet()
	var aoff := _vfx_anchor_world(vfx)
	vfx.offset = (((local_pos - feet) / z) - aoff).round()
	_refresh_vfx_effect_preview(vfx)


# ========================================
# GENERAL INFO HANDLERS
# ========================================
func _on_general_info_changed(value = null) -> void:
	if is_updating_ui or not current_resource or not current_resource is AbilityData:
		return
	var ability = current_resource as AbilityData
	ability.ability_name = ability_name_edit.text
	ability.description = description_edit.text
	ability.max_level = int(max_level_spinbox.value)
	ability.ability_icon = icon_path_picker.get_edited_resource()
	ability.ability_type = ability_type_option.get_selected_id()
	# Write the FULL selection sets (multi-select) — no more index-0 truncation.
	ability.required_class.clear()
	for cid in _multiselect_ids(_req_class_menu):
		ability.required_class.append(cid)
	ability.required_weapon_types.clear()
	for wid in _multiselect_ids(_req_weapon_menu):
		ability.required_weapon_types.append(wid)
	_set_dirty(true)
	# Live-update tree label as the user types
	if not ability.resource_path.is_empty():
		var item: TreeItem = _path_to_tree_item.get(ability.resource_path, null)
		if item:
			var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈") if current_resource_type else "◈"
			item.set_text(0, icon + "  " + _resource_display_name(ability, ability.resource_path.get_file()))
	if _title_label and current_resource_type:
		var icon2 = TYPE_ICONS.get(current_resource_type.display_name, "◈")
		var rname = _resource_display_name(ability, current_resource_type.display_name)
		_title_label.text = ("● " if _dirty else "") + icon2 + "  " + rname
	_refresh_curve_chart()


func _on_ability_type_changed(index: int) -> void:
	_on_general_info_changed()
	_update_active_behavior_ui()
	if current_resource and current_resource is AbilityData:
		_update_formula_tree()


# ========================================
# QUEST EDITOR
# ========================================
# Push the QuestData fields into the form widgets, then rebuild the objectives
# list (each row is its own OptionButton + LineEdit + SpinBox + delete button).
func _update_quest_ui() -> void:
	if not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData

	quest_id_edit.text = quest.quest_id
	quest_name_edit.text = quest.quest_name
	quest_description_edit.text = quest.description
	quest_required_level_spin.value = quest.required_level
	quest_npc_only_check.button_pressed = quest.npc_only
	quest_sort_order_spin.value = quest.sort_order
	quest_reward_exp_spin.value = quest.reward_exp
	quest_reward_coins_spin.value = quest.reward_coins
	quest_reward_items_edit.text = ", ".join(quest.reward_items)

	_populate_quest_prereq_options(quest)
	_rebuild_objectives_list(quest)


# Scan every other QuestData on disk so the prereq dropdown lists real chain
# targets instead of forcing the user to memorize quest_id strings.
func _populate_quest_prereq_options(quest: QuestData) -> void:
	quest_prereq_option.clear()
	quest_prereq_option.add_item("(None)", 0)
	quest_prereq_option.set_item_metadata(0, "")
	var selected_index := 0
	var all_quests := _scan_all_quest_ids(quest)
	for i in range(all_quests.size()):
		var entry: Dictionary = all_quests[i]
		quest_prereq_option.add_item(entry.label, i + 1)
		quest_prereq_option.set_item_metadata(i + 1, entry.quest_id)
		if entry.quest_id == quest.prerequisite_quest_id:
			selected_index = i + 1
	# Prereq was set to a quest that doesn't exist on disk — preserve the string
	# so we don't silently lose user data, surface it as a free-text fallback row.
	if selected_index == 0 and not quest.prerequisite_quest_id.is_empty():
		quest_prereq_option.add_item("⚠ unknown: " + quest.prerequisite_quest_id, quest_prereq_option.item_count)
		quest_prereq_option.set_item_metadata(quest_prereq_option.item_count - 1, quest.prerequisite_quest_id)
		selected_index = quest_prereq_option.item_count - 1
	quest_prereq_option.select(selected_index)


# Walk resources/Quests/ looking for QuestData .tres files. Returns
# [{label, quest_id}] sorted by quest_id, excluding the quest being edited.
func _scan_all_quest_ids(exclude: QuestData) -> Array:
	var out: Array = []
	var base := "res://resources/Quests"
	if not DirAccess.dir_exists_absolute(base):
		return out
	_scan_quests_recursive(base, out, exclude)
	out.sort_custom(func(a, b): return str(a.quest_id) < str(b.quest_id))
	return out


func _scan_quests_recursive(path: String, out: Array, exclude: QuestData) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if fname != "." and fname != "..":
			var full := path.path_join(fname)
			if dir.current_is_dir():
				_scan_quests_recursive(full, out, exclude)
			elif fname.get_extension() == "tres":
				var res := load(full)
				if res is QuestData and res != exclude:
					var q := res as QuestData
					if not q.quest_id.is_empty():
						var label = q.quest_id
						if not q.quest_name.is_empty():
							label += "  —  " + q.quest_name
						out.append({"quest_id": q.quest_id, "label": label})
		fname = dir.get_next()
	dir.list_dir_end()


# Wipe and rebuild every objective row to reflect quest.objectives. Cheaper than
# diffing because objectives are short (~1–5 per quest) and edits already trigger
# a full UI refresh via _set_dirty + _update_ui downstream.
func _rebuild_objectives_list(quest: QuestData) -> void:
	for child in quest_objectives_list.get_children():
		child.queue_free()

	if quest.objectives.is_empty():
		var hint := Label.new()
		hint.text = "  No objectives yet — click + Add Objective to create one."
		hint.add_theme_color_override("font_color", C_DIM)
		hint.add_theme_font_size_override("font_size", 11)
		quest_objectives_list.add_child(hint)
		return

	for i in range(quest.objectives.size()):
		var row := _build_objective_row(i, quest.objectives[i])
		quest_objectives_list.add_child(row)


# A single objective row: [Type ▼] [target text] [× amount SpinBox] [✕ remove].
# Each control captures `idx` via closure so it can update the dict in-place.
func _build_objective_row(idx: int, objective: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	# Index pill
	var idx_lbl := Label.new()
	idx_lbl.text = "#%d" % (idx + 1)
	idx_lbl.custom_minimum_size = Vector2(34, 0)
	idx_lbl.add_theme_color_override("font_color", C_DIM)
	idx_lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(idx_lbl)

	# Type dropdown
	var type_option := OptionButton.new()
	for key in QuestData.ObjectiveType:
		type_option.add_item(str(key), QuestData.ObjectiveType[key])
	var current_type := int(objective.get("type", QuestData.ObjectiveType.KILL))
	type_option.select(_index_for_id(type_option, current_type))
	type_option.custom_minimum_size = Vector2(120, 0)
	_style_option_button(type_option)
	type_option.item_selected.connect(func(_sel): _on_objective_type_changed(idx, type_option))
	row.add_child(type_option)

	# Target — for KILL/COLLECT this is an enemy/item name; for REACH_LEVEL it's
	# unused (we still keep the field around so a future objective type can use it).
	var target_edit := LineEdit.new()
	target_edit.text = str(objective.get("target", ""))
	target_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	target_edit.placeholder_text = _placeholder_for_objective_type(current_type)
	target_edit.editable = current_type != QuestData.ObjectiveType.REACH_LEVEL
	_style_line_edit(target_edit)
	target_edit.text_changed.connect(func(new_text): _on_objective_target_changed(idx, new_text))
	row.add_child(target_edit)

	# Amount — for KILL/COLLECT it's the count; for REACH_LEVEL it's the level number.
	var amount_label := Label.new()
	amount_label.text = "×" if current_type != QuestData.ObjectiveType.REACH_LEVEL else "Lv"
	amount_label.add_theme_color_override("font_color", C_DIM)
	row.add_child(amount_label)

	var amount_spin := SpinBox.new()
	amount_spin.min_value = 1
	amount_spin.max_value = 9999
	amount_spin.value = int(objective.get("amount", 1))
	amount_spin.custom_minimum_size = Vector2(80, 0)
	_style_spin_box(amount_spin)
	amount_spin.value_changed.connect(func(v): _on_objective_amount_changed(idx, int(v)))
	row.add_child(amount_spin)

	# Remove
	var remove_btn := Button.new()
	remove_btn.text = " ✕ "
	remove_btn.tooltip_text = "Delete this objective"
	_style_btn(remove_btn, C_ERR, false)
	remove_btn.pressed.connect(func(): _on_objective_remove(idx))
	row.add_child(remove_btn)

	return row


# OptionButton's `select(index)` takes a popup index, not an id — translate.
func _index_for_id(option: OptionButton, id: int) -> int:
	for i in range(option.item_count):
		if option.get_item_id(i) == id:
			return i
	return 0


func _placeholder_for_objective_type(type: int) -> String:
	match type:
		QuestData.ObjectiveType.KILL:
			return "Enemy monster_name (exact match, e.g. \"Slime\")"
		QuestData.ObjectiveType.COLLECT:
			return "Item NAME (exact match, e.g. \"Health Potion\")"
		QuestData.ObjectiveType.REACH_LEVEL:
			return "(target unused — set the level in the Lv field)"
	return ""


func _on_add_objective_pressed() -> void:
	if not current_resource or not current_resource is QuestData:
		return
	if is_updating_ui:
		return
	var quest := current_resource as QuestData
	quest.objectives.append({
		"type": QuestData.ObjectiveType.KILL,
		"target": "",
		"amount": 1,
	})
	quest.emit_changed()
	_set_dirty(true)
	_rebuild_objectives_list(quest)


func _on_objective_remove(idx: int) -> void:
	if not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData
	if idx < 0 or idx >= quest.objectives.size():
		return
	quest.objectives.remove_at(idx)
	quest.emit_changed()
	_set_dirty(true)
	_rebuild_objectives_list(quest)


func _on_objective_type_changed(idx: int, option: OptionButton) -> void:
	if not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData
	if idx < 0 or idx >= quest.objectives.size():
		return
	var obj: Dictionary = quest.objectives[idx]
	obj["type"] = option.get_selected_id()
	# Clearing target for REACH_LEVEL keeps the saved dict tidy
	if obj["type"] == QuestData.ObjectiveType.REACH_LEVEL:
		obj["target"] = ""
	quest.objectives[idx] = obj
	quest.emit_changed()
	_set_dirty(true)
	_rebuild_objectives_list(quest)  # rebuild so placeholders/editable flags update


func _on_objective_target_changed(idx: int, new_text: String) -> void:
	if is_updating_ui:
		return
	if not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData
	if idx < 0 or idx >= quest.objectives.size():
		return
	var obj: Dictionary = quest.objectives[idx]
	obj["target"] = new_text
	quest.objectives[idx] = obj
	quest.emit_changed()
	_set_dirty(true)


func _on_objective_amount_changed(idx: int, value: int) -> void:
	if is_updating_ui:
		return
	if not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData
	if idx < 0 or idx >= quest.objectives.size():
		return
	var obj: Dictionary = quest.objectives[idx]
	obj["amount"] = value
	quest.objectives[idx] = obj
	quest.emit_changed()
	_set_dirty(true)


# Single handler for the scalar quest fields. Mirrors _on_general_info_changed
# (the ability equivalent) — pulls every widget's value into the resource and
# refreshes the tree label / title so renames are live.
func _on_quest_field_changed(_value = null) -> void:
	if is_updating_ui or not current_resource or not current_resource is QuestData:
		return
	var quest := current_resource as QuestData
	quest.quest_id = quest_id_edit.text
	quest.quest_name = quest_name_edit.text
	quest.description = quest_description_edit.text
	quest.required_level = int(quest_required_level_spin.value)
	# Prereq comes from the dropdown's per-item metadata (the actual quest_id),
	# not the visible label.
	var sel = quest_prereq_option.get_selected_id()
	var meta = quest_prereq_option.get_item_metadata(quest_prereq_option.selected)
	quest.prerequisite_quest_id = str(meta) if meta != null else ""
	quest.npc_only = quest_npc_only_check.button_pressed
	quest.sort_order = int(quest_sort_order_spin.value)
	quest.reward_exp = int(quest_reward_exp_spin.value)
	quest.reward_coins = int(quest_reward_coins_spin.value)
	quest.reward_items = _parse_reward_items_csv(quest_reward_items_edit.text)
	_set_dirty(true)
	# Live-update tree label as the user types
	if not quest.resource_path.is_empty():
		var item: TreeItem = _path_to_tree_item.get(quest.resource_path, null)
		if item:
			var icon = TYPE_ICONS.get(current_resource_type.display_name, "◈") if current_resource_type else "◈"
			item.set_text(0, icon + "  " + _resource_display_name(quest, quest.resource_path.get_file()))
	if _title_label and current_resource_type:
		var icon2 = TYPE_ICONS.get(current_resource_type.display_name, "◈")
		var rname = _resource_display_name(quest, current_resource_type.display_name)
		_title_label.text = ("● " if _dirty else "") + icon2 + "  " + rname


# Comma-separated text → trimmed Array[String] (empties dropped). The reverse of
# the join we do when populating quest_reward_items_edit. Note: returns Array[String]
# explicitly because QuestData.reward_items is typed and a loose Array would error.
func _parse_reward_items_csv(text: String) -> Array[String]:
	var out: Array[String] = []
	for piece in text.split(","):
		var trimmed := str(piece).strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


# ========================================
# FORMULA EDITOR - TREE VIEW
# ========================================
func _update_formula_tree() -> void:
	formula_tree.clear()
	formula_inspector.edit(null)
	if not current_resource or not current_resource is AbilityData or not current_scaling_data:
		return

	var ability = current_resource as AbilityData
	var root = formula_tree.create_item()

	var basic_stats = formula_tree.create_item(root)
	basic_stats.set_text(0, "📊 Basic Stats")
	basic_stats.set_selectable(0, false)
	basic_stats.set_custom_color(0, C_DIM)

	_add_formula_item(basic_stats, "Mana Cost",   "mana_cost_formula",      current_scaling_data.mana_cost_formula)
	_add_formula_item(basic_stats, "Cooldown",    "cooldown_formula",        current_scaling_data.cooldown_formula)
	_add_formula_item(basic_stats, "Damage %",    "damage_percent_formula",  current_scaling_data.damage_percent_formula)
	_add_formula_item(basic_stats, "Max Targets", "max_targets_formula",     current_scaling_data.max_targets_formula)
	_add_formula_item(basic_stats, "Max Hits",    "max_hits_formula",        current_scaling_data.max_hits_formula)
	_add_formula_item(basic_stats, "Cast Time",   "cast_time_formula",       current_scaling_data.cast_time_formula)

	# Buff/debuff duration formulas (live on AbilityData, shown only when a
	# buff/debuff is assigned in the Advanced card).
	if ability.applies_buff or ability.applies_target_debuff:
		var durations = formula_tree.create_item(root)
		durations.set_text(0, "⏱ Durations")
		durations.set_selectable(0, false)
		durations.set_custom_color(0, C_DIM)
		if ability.applies_buff:
			_add_formula_item(durations, "Buff Duration", "buff_duration_formula", ability.buff_duration_formula)
		if ability.applies_target_debuff:
			_add_formula_item(durations, "Debuff Duration", "debuff_duration_formula", ability.debuff_duration_formula)

	if ability.ability_type == Constants.AbilityType.PASSIVE:
		var stat_bonuses = formula_tree.create_item(root)
		stat_bonuses.set_text(0, "💪 Stat Bonuses")
		stat_bonuses.set_selectable(0, false)
		stat_bonuses.set_custom_color(0, C_DIM)
		for stat_formula in current_scaling_data.stat_bonus_formulas:
			if stat_formula:
				var stat_name = Constants.StatType.keys()[stat_formula.stat_type]
				_add_stat_bonus_item(stat_bonuses, stat_name, stat_formula)

	if current_scaling_data.ability_damage_modifier_formulas.size() > 0:
		if _ability_name_cache.is_empty():
			_scan_all_abilities()  # warm names so rows read by target ability
		var modifiers = formula_tree.create_item(root)
		modifiers.set_text(0, "⚔️ Ability Modifiers")
		modifiers.set_selectable(0, false)
		modifiers.set_custom_color(0, C_DIM)
		for ability_id in current_scaling_data.ability_damage_modifier_formulas:
			var disp: String = _ability_name_cache.get(ability_id, ability_id)
			_add_formula_item(modifiers, "→ " + disp, "damage_mod_" + ability_id,
				current_scaling_data.ability_damage_modifier_formulas[ability_id])

	if current_scaling_data.proc_chance_formula or current_scaling_data.proc_damage_formula:
		var procs = formula_tree.create_item(root)
		procs.set_text(0, "⚡ Proc Effects")
		procs.set_selectable(0, false)
		procs.set_custom_color(0, C_DIM)
		_add_formula_item(procs, "Proc Chance", "proc_chance_formula", current_scaling_data.proc_chance_formula)
		_add_formula_item(procs, "Proc Damage", "proc_damage_formula", current_scaling_data.proc_damage_formula)


func _add_formula_item(parent: TreeItem, label: String, key: String, formula: AbilityScalingFormula) -> void:
	var item = formula_tree.create_item(parent)
	item.set_text(0, label)
	item.set_metadata(0, key)
	if formula:
		item.set_text(1, _get_formula_preview(formula))
		item.set_custom_color(1, C_OK)
	else:
		item.set_text(1, "Not Set")
		item.set_custom_color(1, C_DIM)


func _add_stat_bonus_item(parent: TreeItem, stat_name: String, stat_formula: StatBonusFormula) -> void:
	var item = formula_tree.create_item(parent)
	item.set_text(0, stat_name)
	item.set_metadata(0, {"type": "stat_bonus", "resource": stat_formula})

	var parts = []
	if stat_formula.flat_bonus_formula:
		parts.append("Flat: " + _get_formula_preview(stat_formula.flat_bonus_formula))
	if stat_formula.percent_bonus_formula:
		parts.append("%: " + _get_formula_preview(stat_formula.percent_bonus_formula))
	item.set_text(1, " | ".join(parts) if parts.size() > 0 else "Not Set")


func _get_formula_preview(formula: AbilityScalingFormula) -> String:
	match formula.scaling_type:
		AbilityScalingFormula.ScalingType.FLAT:
			return "%.1f + (Lv × %.1f)" % [formula.base_value, formula.per_level]
		AbilityScalingFormula.ScalingType.MULTIPLICATIVE:
			return "%.1f × %.2f^Lv" % [formula.base_value, formula.multiplier]
		AbilityScalingFormula.ScalingType.STEPPED:
			return "Breakpoints: %d" % formula.step_values.size()
		AbilityScalingFormula.ScalingType.CUSTOM:
			return "Custom"
	return "?"


# ========================================
# FORMULA EDITOR - DETAIL EDITING
# ========================================
func _on_formula_tree_selected() -> void:
	var selected = formula_tree.get_selected()
	if not selected:
		formula_inspector.edit(null)
		current_editing_formula = null
		return

	var metadata = selected.get_metadata(0)
	if metadata is String:
		selected_formula_key = metadata
		var formula = _get_formula_by_key(metadata)
		if not formula:
			formula = AbilityScalingFormula.new()
			formula.resource_local_to_scene = true
			_assign_formula_to_key(metadata, formula)
		current_editing_formula = formula
		formula_inspector.edit(formula)
		if not formula.changed.is_connected(_refresh_curve_chart):
			formula.changed.connect(_refresh_curve_chart)
	elif metadata is Dictionary and metadata.has("type") and metadata.type == "stat_bonus":
		selected_formula_key = ""
		current_editing_formula = null
		formula_inspector.edit(metadata.resource)
	_refresh_curve_chart()


func _get_formula_by_key(key: String) -> AbilityScalingFormula:
	match key:
		"mana_cost_formula":      return current_scaling_data.mana_cost_formula
		"cooldown_formula":       return current_scaling_data.cooldown_formula
		"damage_percent_formula": return current_scaling_data.damage_percent_formula
		"max_targets_formula":    return current_scaling_data.max_targets_formula
		"max_hits_formula":       return current_scaling_data.max_hits_formula
		"cast_time_formula":      return current_scaling_data.cast_time_formula
		"proc_chance_formula":    return current_scaling_data.proc_chance_formula
		"proc_damage_formula":    return current_scaling_data.proc_damage_formula
		"buff_duration_formula":
			return (current_resource as AbilityData).buff_duration_formula if current_resource is AbilityData else null
		"debuff_duration_formula":
			return (current_resource as AbilityData).debuff_duration_formula if current_resource is AbilityData else null
	if key.begins_with("damage_mod_"):
		return current_scaling_data.ability_damage_modifier_formulas.get(key.replace("damage_mod_", ""), null)
	return null


func _assign_formula_to_key(key: String, formula: AbilityScalingFormula) -> void:
	match key:
		"mana_cost_formula":      current_scaling_data.mana_cost_formula = formula
		"cooldown_formula":       current_scaling_data.cooldown_formula = formula
		"damage_percent_formula": current_scaling_data.damage_percent_formula = formula
		"max_targets_formula":    current_scaling_data.max_targets_formula = formula
		"max_hits_formula":       current_scaling_data.max_hits_formula = formula
		"cast_time_formula":      current_scaling_data.cast_time_formula = formula
		"proc_chance_formula":    current_scaling_data.proc_chance_formula = formula
		"proc_damage_formula":    current_scaling_data.proc_damage_formula = formula
		"buff_duration_formula":
			if current_resource is AbilityData:
				(current_resource as AbilityData).buff_duration_formula = formula
		"debuff_duration_formula":
			if current_resource is AbilityData:
				(current_resource as AbilityData).debuff_duration_formula = formula
	if key.begins_with("damage_mod_"):
		current_scaling_data.ability_damage_modifier_formulas[key.replace("damage_mod_", "")] = formula


# ========================================
# FORMULA EDITOR - ADD & PRESETS
# ========================================
func _on_add_formula_pressed() -> void:
	var popup = PopupMenu.new()
	popup.add_item("Stat Bonus (Passive)", 0)
	popup.add_item("Ability Damage Modifier", 1)
	popup.id_pressed.connect(func(id):
		match id:
			0: _add_stat_bonus()
			1: _add_ability_modifier()
		popup.queue_free()
	)
	add_child(popup)
	popup.position = add_formula_button.global_position + Vector2(0, add_formula_button.size.y)
	popup.popup()


func _add_stat_bonus() -> void:
	var new_stat_formula = StatBonusFormula.new()
	new_stat_formula.resource_local_to_scene = true
	new_stat_formula.stat_type = Constants.StatType.STRENGTH
	current_scaling_data.stat_bonus_formulas.append(new_stat_formula)
	_update_formula_tree()
	_set_dirty(true)


## Adds an ability-damage-modifier formula keyed by another ability's id (this
## ability scales that ability's damage at runtime — see combat.gd
## get_ability_damage_modifier). Pops a menu of eligible abilities.
func _add_ability_modifier() -> void:
	if not current_scaling_data:
		_set_status("Select an ability first.", true)
		return
	var entries := _scan_all_abilities()
	if entries.is_empty():
		_set_status("No abilities found to modify.", true)
		return
	var self_id := (current_resource as AbilityData).ability_id if current_resource is AbilityData else ""
	var popup := PopupMenu.new()
	var ids: Array = []
	for e in entries:
		if e.id == self_id or e.id.is_empty():
			continue
		if current_scaling_data.ability_damage_modifier_formulas.has(e.id):
			continue
		popup.add_item(e.name if not e.name.is_empty() else e.id, ids.size())
		ids.append(e.id)
	if ids.is_empty():
		_set_status("Every other ability already has a damage modifier.", true)
		popup.queue_free()
		return
	popup.id_pressed.connect(func(idx: int):
		var target_id: String = ids[idx]
		var f := AbilityScalingFormula.new()
		f.resource_local_to_scene = true
		f.base_value = 1.0  # multiplier baseline (1.0 = no change)
		current_scaling_data.ability_damage_modifier_formulas[target_id] = f
		_update_formula_tree()
		_set_dirty(true)
		popup.queue_free())
	add_child(popup)
	popup.position = add_formula_button.global_position + Vector2(0, add_formula_button.size.y)
	popup.popup()


## Recursively load every AbilityData .tres, returning [{id, name}] and warming
## _ability_name_cache. Used by the ability-modifier picker + its tree labels.
func _scan_all_abilities() -> Array:
	var out: Array = []
	_ability_name_cache.clear()
	_scan_abilities_recursive("res://resources/Abilities", out)
	return out


func _scan_abilities_recursive(path: String, out: Array) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		var full := path.path_join(fname)
		if dir.current_is_dir():
			if not fname.begins_with("."):
				_scan_abilities_recursive(full, out)
		elif fname.ends_with(".tres"):
			var res = load(full)
			if res is AbilityData:
				out.append({"id": res.ability_id, "name": res.ability_name})
				_ability_name_cache[res.ability_id] = res.ability_name
		fname = dir.get_next()
	dir.list_dir_end()


func _on_preset_selected(index: int) -> void:
	if index < 0 or not current_editing_formula:
		return
	var preset_name = formula_preset_option.get_item_text(index)
	if not formula_presets.has(preset_name):
		return
	var preset = formula_presets[preset_name]
	current_editing_formula.scaling_type = preset.type
	current_editing_formula.base_value = preset.get("base", 0)
	match preset.type:
		AbilityScalingFormula.ScalingType.FLAT:
			current_editing_formula.per_level = preset.get("per_level", 1.0)
		AbilityScalingFormula.ScalingType.MULTIPLICATIVE:
			current_editing_formula.multiplier = preset.get("mult", 1.1)
	formula_inspector.edit(null)
	formula_inspector.edit(current_editing_formula)
	_update_formula_tree()
	formula_preset_option.select(0)
	_set_dirty(true)


# ========================================
# PREVIEW WINDOW
# ========================================
func _on_preview_button_pressed() -> void:
	if not current_resource or not current_resource is AbilityData:
		return
	var ability = current_resource as AbilityData
	var preview_text = "═══════════════════════════════════════\n"
	preview_text += "    ABILITY PREVIEW\n"
	preview_text += "═══════════════════════════════════════\n\n"
	preview_text += "Name: %s\n" % ability.ability_name
	preview_text += "Type: %s\n" % ("Active" if ability.ability_type == Constants.AbilityType.ACTIVE else "Passive")
	preview_text += "Max Level: %d\n\n" % ability.max_level

	var max_preview = min(ability.max_level, 15)
	for level in range(1, max_preview + 1):
		var level_data = ability.get_level_stats(level)
		if level_data:
			preview_text += "─────────────────────────────────────\n"
			preview_text += "Level %d:\n" % level
			preview_text += "  Mana: %d | Cooldown: %.1fs | Cast: %.1fs\n" % [
				level_data.mana_cost, level_data.cooldown_time, level_data.cast_time]
			preview_text += "  Damage: %d%% | Targets: %d | Hits: %d\n" % [
				level_data.damage_percent, level_data.max_targets, level_data.max_hits]
			if ability.ability_type == Constants.AbilityType.PASSIVE and level_data.stat_bonuses.size() > 0:
				preview_text += "  Stat Bonuses:\n"
				for stat_type in level_data.stat_bonuses:
					var stat = level_data.stat_bonuses[stat_type]
					if stat.flat_bonus_value > 0 or stat.percent_bonus_value > 0:
						preview_text += "    %s: " % Constants.StatType.keys()[stat_type]
						if stat.flat_bonus_value > 0:
							preview_text += "+%d flat " % stat.flat_bonus_value
						if stat.percent_bonus_value > 0:
							preview_text += "+%.1f%% " % stat.percent_bonus_value
						preview_text += "\n"
			if level_data.on_hit_proc:
				preview_text += "  On Hit Proc: %.1f%% chance, %d%% damage\n" % [
					level_data.on_hit_proc.proc_chance * 100, level_data.on_hit_proc.damage_percent]

	if ability.max_level > 15:
		preview_text += "\n... (showing first 15 of %d levels)\n" % ability.max_level
	preview_text += "\n═══════════════════════════════════════\n"
	_show_text_popup("Ability Preview", preview_text)


# ========================================
# HITBOX VISUALIZER
# ========================================
const _VISUALIZER_DEFAULT_ZOOM = 6.0
const _VISUALIZER_MIN_ZOOM     = 1.0
const _VISUALIZER_MAX_ZOOM     = 30.0
const GAME_PLAYER_SCALE        = 1.3
const GAME_PLAYER_OFFSET_Y     = -12.0

var _visualizer_zoom: float = _VISUALIZER_DEFAULT_ZOOM
var _zoom_label: Label = null


func _on_active_behavior_changed() -> void:
	visualizer_control.queue_redraw()
	# The hitbox position or the resolved VFX may have changed — refresh overlay.
	_update_visualizer_vfx()


func _update_visualizer_sprite_pos() -> void:
	if not visualizer_player_sprite.texture:
		return
	visualizer_player_sprite.scale = Vector2.ONE * GAME_PLAYER_SCALE * _visualizer_zoom
	var center = visualizer_control.size / 2
	visualizer_player_sprite.position = center + Vector2(0, (GAME_PLAYER_OFFSET_Y * _visualizer_zoom) / GAME_PLAYER_SCALE)
	_position_visualizer_vfx()


# ── VFX overlay in the ability hitbox visualizer ─────────────────────────────
## Creates the two overlay sprites once, parented to the visualizer Control so
## they share its coordinate space (and z above the hitbox draw).
func _build_visualizer_vfx() -> void:
	if is_instance_valid(_vis_cast_vfx):
		return
	if not is_instance_valid(visualizer_control):
		return
	_vis_cast_vfx = AnimatedSprite2D.new()
	_vis_cast_vfx.z_index = 20
	visualizer_control.add_child(_vis_cast_vfx)
	_vis_hit_vfx = AnimatedSprite2D.new()
	_vis_hit_vfx.z_index = 20
	visualizer_control.add_child(_vis_hit_vfx)


## Resolves the current ability's cast + hit VFX and assigns them to the overlay
## sprites (hidden when the type isn't an ability or the overlay is toggled off).
func _update_visualizer_vfx() -> void:
	_build_visualizer_vfx()
	if not is_instance_valid(_vis_cast_vfx):
		return
	var show: bool = _vis_show_vfx and (current_resource is AbilityData)
	if not show:
		_vis_cast_vfx.visible = false
		_vis_hit_vfx.visible = false
		return
	var ability := current_resource as AbilityData
	_assign_vis_vfx(_vis_cast_vfx, VfxCatalog.resolve_cast(ability))
	_assign_vis_vfx(_vis_hit_vfx, VfxCatalog.resolve_hit(ability))
	_position_visualizer_vfx()


## Loads (a looped copy of) the effect's frames onto an overlay sprite, or hides
## it when the key is empty/unknown.
func _assign_vis_vfx(spr: AnimatedSprite2D, key: String) -> void:
	if not is_instance_valid(spr):
		return
	if key == "" or not VfxCatalog.has(key):
		spr.visible = false
		spr.sprite_frames = null
		return
	var sf: SpriteFrames = VfxCatalog.get_frames(key)
	if sf == null:
		spr.visible = false
		return
	sf = sf.duplicate(true)  # don't mutate the shared runtime cache
	sf.set_animation_loop("play", true)
	spr.sprite_frames = sf
	spr.animation = "play"
	var def: Dictionary = VfxCatalog.get_def(key)
	spr.modulate = def.get("modulate", Color.WHITE)
	spr.set_meta("vfx_key", key)
	spr.visible = true
	spr.play("play")


## Positions/scales the overlay sprites in visualizer space: cast at the player
## body-center + its offset, hit at the hitbox center + its offset, all × zoom.
func _position_visualizer_vfx() -> void:
	if not is_instance_valid(_vis_cast_vfx) or not (current_resource is AbilityData):
		return
	var center: Vector2 = visualizer_control.size / 2
	var z: float = _visualizer_zoom

	if _vis_cast_vfx.visible:
		var cdef: Dictionary = VfxCatalog.get_def(str(_vis_cast_vfx.get_meta("vfx_key", "")))
		var coff: Vector2 = cdef.get("offset", Vector2.ZERO)
		_vis_cast_vfx.position = center + (_VIS_CAST_BODY_OFFSET + coff) * z
		_vis_cast_vfx.scale = Vector2.ONE * float(cdef.get("scale", 1.0)) * z

	if _vis_hit_vfx.visible:
		var ability := current_resource as AbilityData
		var hb: Vector2 = ability.active_behavior.hit_box_position_data if ability.active_behavior else Vector2.ZERO
		var hdef: Dictionary = VfxCatalog.get_def(str(_vis_hit_vfx.get_meta("vfx_key", "")))
		var hoff: Vector2 = hdef.get("offset", Vector2.ZERO)
		_vis_hit_vfx.position = center + (hb + hoff) * z
		_vis_hit_vfx.scale = Vector2.ONE * float(hdef.get("scale", 1.0)) * z


func _set_visualizer_zoom(value: float) -> void:
	_visualizer_zoom = clamp(value, _VISUALIZER_MIN_ZOOM, _VISUALIZER_MAX_ZOOM)
	if is_instance_valid(_zoom_label):
		_zoom_label.text = "Zoom: %.1fx" % _visualizer_zoom
	_update_visualizer_sprite_pos()
	if is_instance_valid(visualizer_control):
		visualizer_control.queue_redraw()


func _on_visualizer_gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return
	if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
		_set_visualizer_zoom(_visualizer_zoom * 1.15)
		visualizer_control.accept_event()
	elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		_set_visualizer_zoom(_visualizer_zoom / 1.15)
		visualizer_control.accept_event()


func _draw_hitbox_visualization() -> void:
	if not current_resource or not current_resource is AbilityData:
		return
	var ability = current_resource as AbilityData
	if not ability.active_behavior:
		return
	_update_visualizer_sprite_pos()
	var center   = visualizer_control.size / 2
	var behavior = ability.active_behavior

	visualizer_control.draw_line(center - Vector2(10, 0), center + Vector2(10, 0), Color.RED, 2)
	visualizer_control.draw_line(center - Vector2(0, 10), center + Vector2(0, 10), Color.RED, 2)

	if behavior.hit_box_shape_data:
		var shape      = behavior.hit_box_shape_data
		var pos_offset = behavior.hit_box_position_data * _visualizer_zoom
		var draw_pos   = center + pos_offset
		var label_text := ""
		var label_anchor = draw_pos

		if shape is CircleShape2D:
			var radius = shape.radius * _visualizer_zoom
			visualizer_control.draw_circle(draw_pos, radius, Color(0, 1, 0, 0.5))
			visualizer_control.draw_arc(draw_pos, radius, 0, TAU, 32, Color.GREEN, 2)
			label_text = "r = %.0f" % shape.radius
			label_anchor = draw_pos + Vector2(-radius, -radius - 6)
		elif shape is RectangleShape2D:
			var size = shape.size * _visualizer_zoom
			var rect = Rect2(draw_pos - size / 2, size)
			visualizer_control.draw_rect(rect, Color(0, 1, 0, 0.5))
			visualizer_control.draw_rect(rect, Color.GREEN, false, 2)
			label_text = "%.0f × %.0f" % [shape.size.x, shape.size.y]
			label_anchor = rect.position + Vector2(0, -6)
		elif shape is CapsuleShape2D:
			var height = shape.height * _visualizer_zoom
			var radius = shape.radius * _visualizer_zoom
			var rect   = Rect2(draw_pos - Vector2(radius, height / 2), Vector2(radius * 2, height))
			visualizer_control.draw_rect(rect, Color(0, 1, 0, 0.5))
			visualizer_control.draw_rect(rect, Color.GREEN, false, 2)
			label_text = "r = %.0f · h = %.0f" % [shape.radius, shape.height]
			label_anchor = rect.position + Vector2(0, -6)

		# Dimension label — drawn above the shape's bounding box
		if not label_text.is_empty():
			var font = ThemeDB.fallback_font
			if font:
				# Background pill for readability
				var fsize := 11
				var text_size = font.get_string_size(label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize)
				var bg_rect = Rect2(label_anchor - Vector2(4, text_size.y + 2),
									Vector2(text_size.x + 8, text_size.y + 4))
				visualizer_control.draw_rect(bg_rect, Color(0, 0, 0, 0.55), true)
				visualizer_control.draw_string(font, label_anchor - Vector2(0, 4),
					label_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, Color.GREEN)


# ========================================
# HELP DIALOG
# ========================================
func _show_formula_help() -> void:
	var help_text = "═══ FORMULA SYSTEM GUIDE ═══\n\n"
	help_text += "LINEAR (FLAT):\n"
	help_text += "  Formula: base + (level × per_level)\n"
	help_text += "  Example: 10 + (level × 5)  →  10, 15, 20, 25, 30...\n\n"
	help_text += "EXPONENTIAL (MULTIPLICATIVE):\n"
	help_text += "  Formula: base × (multiplier ^ level)\n"
	help_text += "  Example: 100 × (1.1 ^ level)  →  100, 110, 121, 133, 146...\n\n"
	help_text += "BREAKPOINTS (STEPPED):\n"
	help_text += "  Changes at specific levels.\n"
	help_text += "  Example: {1: 100, 5: 150, 10: 200}\n"
	help_text += "  Levels 1-4: 100 | Levels 5-9: 150 | Levels 10+: 200\n\n"
	help_text += "CUSTOM:\n"
	help_text += "  Write your own GDScript formula.\n"
	help_text += "  Variables: level, base_value\n"
	help_text += "  Example: base_value + (level * 10) + (level * level * 0.5)\n"
	_show_text_popup("Formula System Guide", help_text)


# Shared popup for Preview and Help. Lazy-built and re-used.
func _show_text_popup(title: String, body: String) -> void:
	if not is_instance_valid(_help_dialog):
		_help_dialog = AcceptDialog.new()
		_help_dialog.unresizable = false
		_help_dialog.min_size = Vector2i(640, 540)
		var scroll = ScrollContainer.new()
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size = Vector2(600, 480)
		_popup_body_label = Label.new()
		_popup_body_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_popup_body_label.add_theme_font_size_override("font_size", 12)
		_popup_body_label.add_theme_color_override("font_color", C_TEXT)
		scroll.add_child(_popup_body_label)
		_help_dialog.add_child(scroll)
		_style_popup_window(_help_dialog)
		add_child(_help_dialog)
	_help_dialog.title = title
	if is_instance_valid(_popup_body_label):
		_popup_body_label.text = body
	_help_dialog.popup_centered()


# Apply the dark theme to a Window-derived dialog (AcceptDialog, ConfirmationDialog).
func _style_popup_window(win: Window) -> void:
	if not is_instance_valid(win):
		return
	var panel_sb = StyleBoxFlat.new()
	panel_sb.bg_color = C_DARK
	panel_sb.border_color = Color(_current_accent, 0.35)
	panel_sb.set_border_width_all(1)
	panel_sb.set_corner_radius_all(6)
	panel_sb.content_margin_left = 14
	panel_sb.content_margin_right = 14
	panel_sb.content_margin_top = 14
	panel_sb.content_margin_bottom = 14
	win.add_theme_stylebox_override("panel", panel_sb)
	_accent_appliers.append(func(c: Color):
		panel_sb.border_color = Color(c, 0.35)
	)
