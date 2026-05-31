class_name EquipmentCompareTooltip
extends RefCounted

## Builds the "hovered vs. currently equipped" tooltip shown when the cursor
## sits on an equipment item in the inventory. Returns a Control suitable for
## `_make_custom_tooltip` to hand back to Godot.

const PANEL_STYLEBOX: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

const COLOR_UPGRADE := Color(0.45, 0.85, 0.45)
const COLOR_DOWNGRADE := Color(0.85, 0.45, 0.45)
const COLOR_COMPARE_HEADER := Color(0.6, 0.6, 0.68)
const COLOR_SUBTITLE := Color(0.62, 0.62, 0.7)
const COLOR_STAT_LABEL := Color(0.78, 0.78, 0.82)
const COLOR_STAT_VALUE := Color(1, 1, 1)
const COLOR_DESCRIPTION := Color(0.68, 0.68, 0.75)
const COLOR_SEPARATOR := Color(0.32, 0.32, 0.38)

const PANEL_MIN_WIDTH := 260
const PADDING_H := 14
const PADDING_V := 12
const ICON_SIZE := 40
const NAME_ROW_SEPARATION := 8
# Name label width is fixed so the panel stays at PANEL_MIN_WIDTH regardless
# of the item name — long names autowrap within this column instead of
# pushing the tooltip wider. = panel_inner − icon − separation.
const NAME_LABEL_WIDTH := PANEL_MIN_WIDTH - PADDING_H * 2 - ICON_SIZE - NAME_ROW_SEPARATION

# Title-cased stat names. The raw enum keys (`MAGICDEFENSE`, `HPREGEN`) read
# badly in a tooltip — this maps them to display-friendly text.
const STAT_NAMES := {
	Constants.StatType.STRENGTH: "Strength",
	Constants.StatType.INTELLIGENCE: "Intelligence",
	Constants.StatType.DEXTERITY: "Dexterity",
	Constants.StatType.LUCK: "Luck",
	Constants.StatType.HEALTH: "Health",
	Constants.StatType.MANA: "Mana",
	Constants.StatType.HPREGEN: "HP Regen",
	Constants.StatType.MPREGEN: "MP Regen",
	Constants.StatType.DEFENSE: "Defense",
	Constants.StatType.MAGICDEFENSE: "Magic Defense",
	Constants.StatType.CRITCHANCE: "Crit Chance",
	Constants.StatType.CRITDAMAGE: "Crit Damage",
	Constants.StatType.WEAPONATTACK: "Weapon Attack",
	Constants.StatType.MAGICATTACK: "Magic Attack",
	Constants.StatType.KNOCKBACKRESIST: "Knockback Resist",
	Constants.StatType.CONSTITUTION: "Constitution",
	Constants.StatType.ACCURACY: "Accuracy",
	Constants.StatType.EVASIONCHANCE: "Evasion",
}


## Returns a tooltip Control. If `equipped` is null (or matches `hovered`) only
## the hovered panel is shown. Returns null if `hovered` is not equipment.
static func build(hovered: ItemData, equipped: ItemData) -> Control:
	if hovered == null:
		return null
	if hovered.item_type != Constants.ItemType.EQUIPMENT:
		return null

	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 8)

	var show_compare := equipped != null and equipped != hovered

	if show_compare:
		root.add_child(_build_panel(equipped, null, "Currently Equipped"))

	var header_right := "Hovered" if show_compare else ""
	root.add_child(_build_panel(hovered, equipped if show_compare else null, header_right))

	return root


static func _build_panel(item: ItemData, compare_to: ItemData, header: String) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := PANEL_STYLEBOX.duplicate() as StyleBoxFlat
	var rarity_color = TooltipTheme.rarity_color_for(item)
	if rarity_color != null:
		style.border_color = rarity_color
		style.set_border_width_all(8)
	style.content_margin_left = PADDING_H
	style.content_margin_right = PADDING_H
	style.content_margin_top = PADDING_V
	style.content_margin_bottom = PADDING_V
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(PANEL_MIN_WIDTH, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	panel.add_child(vbox)

	# "Currently Equipped" / "Hovered" — only shown in compare mode.
	if not header.is_empty():
		var hdr := Label.new()
		hdr.text = header.to_upper()
		hdr.add_theme_color_override("font_color", COLOR_COMPARE_HEADER)
		hdr.add_theme_font_size_override("font_size", 12)
		hdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		vbox.add_child(hdr)

	# Item name (left, fixed width, wraps) + icon (right, fixed size). The
	# name's custom_minimum_size.x locks the column width — combined with the
	# icon's fixed width, the HBox total = panel inner width, so the panel
	# stays at PANEL_MIN_WIDTH regardless of name length. Long names autowrap
	# inside the fixed column instead of pushing the panel wider.
	# (autowrap + SIZE_EXPAND_FILL together is the broken combo to avoid — see
	# project_autowrap_label_in_hbox_pathology.md.)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", NAME_ROW_SEPARATION)

	var name_lbl := Label.new()
	name_lbl.text = item.name
	name_lbl.add_theme_font_size_override("font_size", 20)
	name_lbl.custom_minimum_size = Vector2(NAME_LABEL_WIDTH, 0)
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if rarity_color != null:
		name_lbl.add_theme_color_override("font_color", rarity_color)
	name_row.add_child(name_lbl)

	var icon_tex := _resolve_icon(item)
	if icon_tex != null:
		var icon := TextureRect.new()
		icon.texture = icon_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.size_flags_horizontal = Control.SIZE_SHRINK_END
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		# Pixel-art icons need NEAREST filtering or they blur at the rendered size.
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		name_row.add_child(icon)

	vbox.add_child(name_row)

	# Subtitle — slot / weapon type. No "Type:" prefix; the placement is enough.
	var subtitle := _subtitle_text(item)
	if not subtitle.is_empty():
		var sub_lbl := Label.new()
		sub_lbl.text = subtitle
		sub_lbl.add_theme_color_override("font_color", COLOR_SUBTITLE)
		vbox.add_child(sub_lbl)

	# Stats block, divider above when there's a header to separate from.
	var has_stats := false
	var stat_rows: Array[HBoxContainer] = _stat_rows(item, compare_to)
	if not stat_rows.is_empty():
		vbox.add_child(_separator())
		for row in stat_rows:
			vbox.add_child(row)
		has_stats = true

	# Flavor description at the bottom, dimmed and separated from stats.
	if item.description and not item.description.is_empty():
		if has_stats or not subtitle.is_empty():
			vbox.add_child(_separator())
		var desc := Label.new()
		desc.text = item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		# Force width so autowrap actually wraps inside the panel.
		desc.custom_minimum_size = Vector2(PANEL_MIN_WIDTH - PADDING_H * 2, 0)
		desc.add_theme_color_override("font_color", COLOR_DESCRIPTION)
		vbox.add_child(desc)

	return panel


## Mirrors slot.gd's canonical-vs-instance icon resolution: slim-saved items
## may have a null instance icon, in which case fall back to the canonical
## resource's icon. Returns null only if both are missing.
static func _resolve_icon(item: ItemData) -> Texture2D:
	if item == null:
		return null
	var canonical = ResourceManager.get_item_data(item.item_id)
	if canonical and canonical.icon:
		return canonical.icon
	return item.icon


static func _subtitle_text(item: ItemData) -> String:
	if item.item_type != Constants.ItemType.EQUIPMENT:
		return ""
	if item.equipment_type == Constants.EquipmentType.WEAPON:
		var weapon_name := str(Constants.WeaponType.keys()[item.weapon_type]).capitalize()
		if "attack_speed" in item:
			return "%s  —  %s" % [weapon_name, str(item.attack_speed).capitalize()]
		return weapon_name
	elif item.equipment_type == Constants.EquipmentType.ARMOR:
		return str(Constants.ArmorType.keys()[item.armor_type]).capitalize() + " Armor"
	return ""


static func _separator() -> HSeparator:
	var sep := HSeparator.new()
	var sep_style := StyleBoxFlat.new()
	sep_style.bg_color = COLOR_SEPARATOR
	sep_style.content_margin_top = 1
	sep_style.content_margin_bottom = 1
	sep.add_theme_stylebox_override("separator", sep_style)
	return sep


static func _stat_rows(item: ItemData, compare_to: ItemData) -> Array[HBoxContainer]:
	var rows: Array[HBoxContainer] = []
	var item_stats: Dictionary = item.bonus_stats if "bonus_stats" in item and item.bonus_stats else {}
	var cmp_stats: Dictionary = {}
	if compare_to != null and "bonus_stats" in compare_to and compare_to.bonus_stats:
		cmp_stats = compare_to.bonus_stats

	if item_stats.is_empty() and cmp_stats.is_empty():
		return rows

	# Union of stat types — sorted by enum order so the same item always lists
	# stats in the same order across hovers.
	var all_types := {}
	for k in item_stats: all_types[k] = true
	for k in cmp_stats: all_types[k] = true
	var sorted_types := all_types.keys()
	sorted_types.sort()

	for stat_type in sorted_types:
		var mine := 0
		var theirs := 0
		if stat_type in item_stats:
			mine = item_stats[stat_type].flat_bonus_value
		if stat_type in cmp_stats:
			theirs = cmp_stats[stat_type].flat_bonus_value
		if mine == 0 and theirs == 0:
			continue
		rows.append(_stat_row(stat_type, mine, theirs, compare_to != null))
	return rows


static func _stat_row(stat_type: int, mine: int, theirs: int, comparing: bool) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_lbl := Label.new()
	name_lbl.text = STAT_NAMES.get(
		stat_type,
		str(Constants.StatType.keys()[stat_type]).capitalize()
	)
	name_lbl.add_theme_color_override("font_color", COLOR_STAT_LABEL)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.text = "%+d" % mine
	value_lbl.add_theme_color_override("font_color", COLOR_STAT_VALUE)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value_lbl)

	if comparing:
		var diff := mine - theirs
		if diff != 0:
			var diff_lbl := Label.new()
			diff_lbl.text = "(%+d)" % diff
			diff_lbl.add_theme_color_override(
				"font_color",
				COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
			)
			row.add_child(diff_lbl)

	return row
