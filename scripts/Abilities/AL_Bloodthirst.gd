extends Node

## Bloodthirst — passive heal-on-enemy-kill. Each kill restores
## (1 + level) percent of the wielder's Max HP. Class-neutral per
## [[project_passives_class_neutral]] — applies whenever the character
## scores a kill, regardless of which weapon was active.
##
## Invoked by CombatComponent's kill pathway via
## AbilityComponent.dispatch_passive_event_on_kill, which iterates all
## learned passive abilities and calls on_kill on those whose
## active_behavior.logic_script defines the method.

## PR 14 (2026-05-31): heal % now reads from A_Bloodthirst.tres's
## damage_percent_formula directly, so future .tres tunings auto-propagate
## without touching this script. The hardcoded BASE/PER_LEVEL constants
## had drifted: PR 9 doubled .tres per_level (0.3 → 0.6) when max_level
## halved (10 → 5), but this script's PER_LEVEL_HEAL_PCT stayed 0.3 —
## Bloodthirst silently undertuned at L5 (1.7% instead of intended 2.9%).
## Reading from the formula makes that whole class of bug impossible.
##
## With the current .tres formula (base 0.5, per_level 0.6, max_level 5):
##   L1:   0.5% Max HP per kill
##   L3:   1.7% Max HP per kill
##   L5:   2.9% Max HP per kill


func on_kill(_owner_node: Node, _target: Node, _ability_level: int, _ability_id: String = "") -> void:
	if not _owner_node.multiplayer.is_server():
		return

	var health_comp = _owner_node.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp):
		return
	if health_comp.is_dead:
		return

	# Read per-level heal % from the .tres formula (single source of truth).
	# Fallback to a small fixed value if the ability data can't be resolved.
	var heal_pct: float = 0.5
	if _ability_id != "":
		var ability: AbilityData = ResourceManager.get_ability_data(_ability_id)
		if ability and ability.damage_percent_formula:
			heal_pct = ability.damage_percent_formula.calculate(_ability_level)

	# PR 6 upgrades: "heal_pct_bonus" (+flat % per kill) and "vampiric_basic"
	# is handled elsewhere; here we only add the per-kill heal bonus.
	var ability_comp = _owner_node.get("ability_component")
	if _ability_id != "" and ability_comp and ability_comp.has_method("get_ability_upgrade_magnitude"):
		heal_pct += ability_comp.get_ability_upgrade_magnitude(_ability_id, "heal_pct_bonus")
	var heal_amount: int = maxi(1, roundi(float(health_comp.max_health) * heal_pct / 100.0))
	health_comp.heal_damage(heal_amount, _owner_node)
