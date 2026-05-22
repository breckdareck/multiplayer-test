class_name TooltipTheme
extends RefCounted

## Shared styling for the game's tooltips. Mirrors the inventory Slot tooltip
## look so abilities, hotbar slots, and buff icons all get the same skinned
## panel instead of Godot's default flat tooltip.

const PANEL_STYLEBOX: StyleBoxFlat = preload("uid://dm8jxifs8rqrm")

## Rarity → border color, matching scripts/UI/slot.gd.
const RARITY_COLORS := {
	0: Color.DARK_GRAY, # Common
	1: Color.WHITE,    # Uncommon
	2: Color.ORANGE,   # Rare
	3: Color.PURPLE,   # Epic
	4: Color.GOLD,     # Legendary
}


## Applies the skinned TooltipPanel stylebox to `control`. The control's own
## `panel` stylebox (used by PanelContainer subclasses for their visuals) is
## preserved so its border/background do not change.
static func apply_to(control: Control) -> void:
	var theme := Theme.new()
	var default_panel := control.get_theme_stylebox("panel", "PanelContainer")
	if default_panel:
		theme.set_stylebox("panel", "PanelContainer", default_panel)
		theme.set_stylebox("panel", "", default_panel)
	theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX)
	control.theme = theme


## Recolours the tooltip border (e.g. by item rarity or to mark a debuff). Pass
## `null` to revert to the default styling. Requires `apply_to` to have already
## been called on this control.
static func set_border_color(control: Control, color) -> void:
	if not control.theme:
		apply_to(control)
	if color == null:
		control.theme.set_stylebox("panel", "TooltipPanel", PANEL_STYLEBOX)
		return
	var dup := PANEL_STYLEBOX.duplicate() as StyleBoxFlat
	dup.border_color = color
	dup.set_border_width_all(8)
	control.theme.set_stylebox("panel", "TooltipPanel", dup)


## Returns the rarity color for an item, or `null` if the item has no rarity.
static func rarity_color_for(item):
	if item == null:
		return null
	var rarity := -1
	if item.has_method("get_rarity"):
		rarity = item.get_rarity()
	elif "rarity" in item and typeof(item.rarity) == TYPE_INT:
		rarity = item.rarity
	return RARITY_COLORS.get(rarity, null)
