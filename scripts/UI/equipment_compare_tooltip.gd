class_name EquipmentCompareTooltip
extends RefCounted

## Builds the "hovered vs. currently equipped" tooltip shown when the cursor
## sits on an equipment item in the inventory. Returns a Control suitable for
## `_make_custom_tooltip` to hand back to Godot.

const PANEL_STYLEBOX: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

const COLOR_UPGRADE := Color(0.45, 0.85, 0.45)
const COLOR_DOWNGRADE := Color(0.85, 0.45, 0.45)
const COLOR_HEADER := Color(0.65, 0.65, 0.7)
const COLOR_BODY := Color(0.92, 0.92, 0.92)


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
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(220, 0)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	panel.add_child(vbox)

	# Section header ("Hovered" / "Currently Equipped").
	if not header.is_empty():
		var hdr := Label.new()
		hdr.text = header
		hdr.add_theme_color_override("font_color", COLOR_HEADER)
		hdr.add_theme_font_size_override("font_size", 12)
		vbox.add_child(hdr)

	# Item name (rarity-coloured).
	var name_lbl := Label.new()
	name_lbl.text = item.name
	if rarity_color != null:
		name_lbl.add_theme_color_override("font_color", rarity_color)
	vbox.add_child(name_lbl)

	# Description.
	if item.description and not item.description.is_empty():
		var desc := Label.new()
		desc.text = item.description
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(210, 0)
		desc.add_theme_color_override("font_color", COLOR_BODY)
		vbox.add_child(desc)

	# Equipment type lines (weapon type + speed; armor type).
	for line in _type_lines(item):
		var lbl := Label.new()
		lbl.text = line
		lbl.add_theme_color_override("font_color", COLOR_BODY)
		vbox.add_child(lbl)

	# Bonus stats with diffs against compare_to (if provided).
	var stats_bbcode := _stats_bbcode(item, compare_to)
	if not stats_bbcode.is_empty():
		var rt := RichTextLabel.new()
		rt.bbcode_enabled = true
		rt.fit_content = true
		rt.scroll_active = false
		rt.custom_minimum_size = Vector2(210, 0)
		rt.text = stats_bbcode
		vbox.add_child(rt)

	return panel


static func _type_lines(item: ItemData) -> Array[String]:
	var lines: Array[String] = []
	if item.item_type != Constants.ItemType.EQUIPMENT:
		return lines
	if item.equipment_type == Constants.EquipmentType.WEAPON:
		lines.append("Type: " + str(Constants.WeaponType.keys()[item.weapon_type]).capitalize())
		if "attack_speed" in item:
			lines.append("Attack Speed: " + str(item.attack_speed).to_upper())
	elif item.equipment_type == Constants.EquipmentType.ARMOR:
		lines.append("Type: " + str(Constants.ArmorType.keys()[item.armor_type]).capitalize())
	return lines


static func _stats_bbcode(item: ItemData, compare_to: ItemData) -> String:
	var item_stats: Dictionary = item.bonus_stats if "bonus_stats" in item and item.bonus_stats else {}
	var cmp_stats: Dictionary = {}
	if compare_to != null and "bonus_stats" in compare_to and compare_to.bonus_stats:
		cmp_stats = compare_to.bonus_stats

	if item_stats.is_empty() and cmp_stats.is_empty():
		return ""

	# Union of stat types so missing-on-one-side shows up as a delta.
	var all_types := {}
	for k in item_stats: all_types[k] = true
	for k in cmp_stats: all_types[k] = true

	var lines: Array[String] = []
	for stat_type in all_types:
		var stat_name := str(Constants.StatType.keys()[stat_type]).to_upper()
		var mine := 0
		var theirs := 0
		if stat_type in item_stats:
			mine = item_stats[stat_type].flat_bonus_value
		if stat_type in cmp_stats:
			theirs = cmp_stats[stat_type].flat_bonus_value
		if mine == 0 and theirs == 0:
			continue

		if compare_to == null:
			lines.append("%s: +%d" % [stat_name, mine])
		else:
			var diff := mine - theirs
			var diff_text := ""
			if diff > 0:
				diff_text = "  [color=#%s](+%d)[/color]" % [COLOR_UPGRADE.to_html(false), diff]
			elif diff < 0:
				diff_text = "  [color=#%s](%d)[/color]" % [COLOR_DOWNGRADE.to_html(false), diff]
			lines.append("%s: +%d%s" % [stat_name, mine, diff_text])

	return "\n".join(lines)
