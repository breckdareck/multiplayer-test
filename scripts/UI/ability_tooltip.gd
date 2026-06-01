class_name AbilityTooltip
extends RefCounted

## Builds the hover tooltip for an ability (hotbar slot, skill-tree slot). The
## text comes from AbilityData.get_tooltip_text(), which may contain hand-authored
## BBCode ([color=...]) plus the values the description formatter expands
## ($[damage_percent], $[value:KEY], ...). Godot's DEFAULT tooltip is a plain
## Label and would render those tags literally ("[color=#7ec2ff]+250 Defense..."),
## so slots route through _make_custom_tooltip() and hand back this control, which
## renders the text in a BBCode-enabled RichTextLabel skinned like the game's
## other tooltips (see TooltipTheme / EquipmentCompareTooltip).

const PANEL_STYLEBOX: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

const PANEL_WIDTH := 300
const PADDING_H := 14
const PADDING_V := 12


## Returns a tooltip Control for `text`, or null when there's nothing to show.
## `border_color` (a Color, or null for the default) tints the panel border —
## used to mark consumable rarity, matching the inventory tooltip convention.
static func build(text: String, border_color = null) -> Control:
	if text.strip_edges().is_empty():
		return null

	var panel := PanelContainer.new()
	var style := PANEL_STYLEBOX.duplicate() as StyleBoxFlat
	if border_color != null:
		style.border_color = border_color
		style.set_border_width_all(8)
	style.content_margin_left = PADDING_H
	style.content_margin_right = PADDING_H
	style.content_margin_top = PADDING_V
	style.content_margin_bottom = PADDING_V
	panel.add_theme_stylebox_override("panel", style)

	var rtl := RichTextLabel.new()
	rtl.bbcode_enabled = true
	rtl.fit_content = true
	rtl.scroll_active = false
	rtl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Fixed width so long description lines autowrap inside the panel instead of
	# stretching the tooltip across the screen; fit_content sizes the height.
	rtl.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	rtl.text = text
	panel.add_child(rtl)

	return panel
