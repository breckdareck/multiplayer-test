extends Node

## PR 5 follow-up — Brandish is the sword combo BUILDER alongside basic
## attacks. Each landed hit grants 1 combo point (capped by
## SwordComboComponent.COMBO_CAP). A 2-hit Brandish across 3 targets at high
## mastery can build a full combo from empty in a single cast — making
## Brandish the "ramp" play pattern that complements the basic-attack
## drip-feed.
##
## The on_hit hook is invoked by CombatComponent._execute_hit for every
## landed hit (post-miss-check, pre-knockback). Misses do NOT fire on_hit,
## so a whiff Brandish doesn't waste-build combo.
##
## We follow AL_Slash's pattern: trust the cast (ability gating already
## checked required_weapon_types at cast time) and just operate the combo
## component. Mid-cast Tab-swap is not a real exploit — combo is capped at
## 3, and SwordComboComponent.add_combo_point is no-op past the cap.

func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	# Server-only — combo is authoritative on the server, mirrored to the
	# owning client via SwordComboComponent.sync_combo_to_client.
	if not _owner_node.multiplayer.is_server():
		return

	var combo_comp = _owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp):
		return

	# Base 1 combo per hit; PR 6 "Doubletap" upgrade (combo_per_hit_bonus)
	# adds more. Capped internally by SwordComboComponent.COMBO_CAP.
	var per_hit: int = 1
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null:
		per_hit += int(ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "combo_per_hit_bonus"))
	for i in range(maxi(1, per_hit)):
		combo_comp.add_combo_point()
