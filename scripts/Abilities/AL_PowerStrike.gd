extends Node

## PR 5 follow-up — Power Strike is the sword combo SINGLE-TARGET finisher,
## complementing Slash (the AOE finisher). Same combo-spend mechanic as
## Slash; the difference is the per-point multiplier:
##
##   Slash:        +50% per combo point (SwordComboComponent.COMBO_DAMAGE_PER_POINT)
##   Power Strike: +100% per combo point (this script's constant)
##
## At 3 combo: Slash deals 2.5× damage on up to 6 targets; Power Strike deals
## 4.0× damage on 1 target. Players who specialize into single-target burst
## (boss play, PvP) pick Power Strike; players who clear packs pick Slash.
##
## Power Strike already requires Slash 5 as a prereq (see prerequisite_abilities
## in A_Power_Strike.tres), so the spec-into-burst path is naturally gated
## behind learning the combo system first.

## Per-combo-point damage multiplier. Local constant rather than the shared
## SwordComboComponent.COMBO_DAMAGE_PER_POINT because Power Strike is a
## stronger finisher — it trades AOE for a bigger combo payoff per point.
const POWERSTRIKE_DAMAGE_PER_POINT: float = 1.0


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	# Server-only: combo state and damage scaling are authoritative.
	if not _owner_node.multiplayer.is_server():
		return

	if not is_instance_valid(_owner_node):
		return

	var combo_comp = _owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp):
		return

	var combat_comp = _owner_node.get("combat_component")
	if combat_comp == null or not is_instance_valid(combat_comp):
		combo_comp.spend_combo()
		return

	var current_count: int = int(combo_comp.get_combo_count())
	# 0 combo → 1.0× (no bonus). 3 combo → 4.0× (+300%).
	var multiplier: float = 1.0 + float(current_count) * POWERSTRIKE_DAMAGE_PER_POINT

	# Stage on combat_comp.pending_ability_damage_multiplier — read by
	# CombatComponent.calculate_ability_damage and cleared on
	# CombatComponent.end_ability_attack so it never bleeds across casts.
	combat_comp.pending_ability_damage_multiplier = multiplier

	# Spend AFTER staging so the scaling reads the count we just used.
	combo_comp.spend_combo()
