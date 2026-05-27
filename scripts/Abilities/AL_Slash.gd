extends Node

## PR 5 — Sword discipline signature: Slash is the v1 combo CONSUMER.
##
## On cast: spend ALL current combo points (0-3) and apply a damage multiplier
## of +25% per point spent (so 3 combo = +75% on top of base Slash damage).
## With 0 combo, the ability still casts normally (no penalty, no bonus).
##
## Other sword abilities (Power Strike, Brandish, HP Boost, Power Guard,
## Maple Warrior) stay UNCHANGED — they don't consume combo, they don't
## build combo. Combo points are exclusively the basic-attack ↔ Slash loop.
##
## How the damage scaling integrates:
## 1. _trigger_ability_state_change runs first → attack_state.enter() →
##    combat_component.process_ability_hit configures the hitbox and starts
##    the cast-time timer.
## 2. THEN this execute method runs (still synchronous, server-side).
## 3. We stash the multiplier on combat_component.pending_ability_damage_multiplier
##    and spend the combo. The multiplier sticks for one ability cast and is
##    cleared in CombatComponent.end_ability_attack().
## 4. The hitbox timeout fires later → _execute_hit → calculate_ability_damage
##    applies the staged multiplier.

func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	# Server-only: combo state and damage scaling are authoritative. The client
	# mirror gets the spent count via combo_changed → sync_combo_to_client.
	if not _owner_node.multiplayer.is_server():
		return

	# Resolve the combo component via the typed accessor. Defensive — if for
	# some reason the player root predates PR 5 (e.g. test scenes that don't
	# carry the SwordComboComponent), silently no-op and let Slash cast normally.
	if not is_instance_valid(_owner_node):
		return
	var combo_comp = _owner_node.get("sword_combo_component")
	if combo_comp == null or not is_instance_valid(combo_comp):
		return

	# Resolve the combat component the same way — it's where the damage
	# multiplier gets staged. If it's missing the spend is still safe (combo
	# clears), but we won't amplify the damage; that's a graceful degradation
	# instead of a hard error.
	var combat_comp = _owner_node.get("combat_component")
	if combat_comp == null or not is_instance_valid(combat_comp):
		# Spend anyway so the combo doesn't get stuck full.
		combo_comp.spend_combo()
		return

	var current_count: int = int(combo_comp.get_combo_count())
	# 0 combo → multiplier 1.0 (no bonus). 3 combo → 1.75 (+75%). Tunable
	# via SwordComboComponent.COMBO_DAMAGE_PER_POINT.
	var multiplier: float = 1.0 + float(current_count) * SwordComboComponent.COMBO_DAMAGE_PER_POINT

	# Stage the multiplier — CombatComponent.calculate_ability_damage reads it
	# on the next damage roll, and CombatComponent.end_ability_attack resets
	# it back to 1.0 so it never bleeds into the next cast.
	combat_comp.pending_ability_damage_multiplier = multiplier

	# Spend AFTER staging the multiplier so the count we used for scaling is
	# the one we just consumed.
	combo_comp.spend_combo()
