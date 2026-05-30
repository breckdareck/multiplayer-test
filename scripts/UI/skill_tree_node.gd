extends Button

## One node button in the SkillTreeCanvas. Carries its ability + current level so
## it can be dragged onto the hotbar, mirroring the old AbilitySlot drag contract
## (returns {"ability_data": ...}; gated to non-passive, learned abilities). No
## class_name — resolved by preload to avoid global-class-cache staleness.

var ability_data: AbilityData
var current_level: int = 0


func _get_drag_data(_at_position: Vector2):
	if not ability_data:
		return null
	# Passives aren't castable, and unlearned abilities can't go on the hotbar.
	if ability_data.ability_type == Constants.AbilityType.PASSIVE:
		return null
	if current_level <= 0:
		return null

	var preview := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.2, 0.2, 0.3, 0.8)
	ps.border_color = Color(0.8, 0.8, 0.2, 1.0)
	ps.set_border_width_all(2)
	preview.add_theme_stylebox_override("panel", ps)
	var icon := TextureRect.new()
	icon.texture = ability_data.ability_icon
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	preview.add_child(icon)
	set_drag_preview(preview)

	return {"ability_data": ability_data}
