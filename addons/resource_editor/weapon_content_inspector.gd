@tool
class_name WeaponContentInspector
extends EditorInspectorPlugin

## Enhances Godot's NATIVE Inspector for the weapon-content resource types, so
## per-resource editing rides the real editor (themed, undo/redo, FileSystem dock)
## instead of a parallel custom dock. Custom EditorProperty widgets are injected
## only where they add value; everything else stays native.
##
## Migration target — see the rewrite plan. Stage 1: effect_key on
## AbilityUpgradeData. Later stages add the upgrades-tree property, the formula
## curve, and the hitbox / VFX visualizers.

func _can_handle(object) -> bool:
	return (object is AbilityUpgradeData
		or object is AbilityData
		or object is ActiveBehaviorData
		or object is AbilityScalingFormula
		or object is VfxEffectData)


## Inline visualizers at the top of the relevant sub-inspector.
func _parse_begin(object) -> void:
	if object is ActiveBehaviorData:
		var hb := HitboxPreviewControl.new()
		hb.set_behavior(object)
		add_custom_control(hb)
	elif object is AbilityScalingFormula:
		var fc := FormulaCurveControl.new()
		fc.set_formula(object)
		add_custom_control(fc)
	elif object is VfxEffectData:
		var vp := VfxPreviewControl.new()
		vp.set_vfx(object)
		add_custom_control(vp)


func _parse_property(object, _type, name, _hint_type, _hint_string, _usage, _wide) -> bool:
	if object is AbilityUpgradeData and name == "effect_key":
		add_property_editor(name, EffectKeyProperty.new())
		return true  # suppress the default text field
	if object is AbilityData and name == "upgrades":
		add_property_editor(name, UpgradesProperty.new())
		return true  # replace the native array editor with the tier-row widget
	return false
