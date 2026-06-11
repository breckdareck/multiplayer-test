extends Node

## Ability logic for Cripple (Rogue's Disorder).
## The hitbox deals damage via the standard combat system; the Disorder
## debuff (defense + attack down) is applied automatically by combat.gd via
## applies_target_debuff. This script adds the HAMSTRING: every landed hit
## also slows the target 30% for 2.5s through the shared AL_SlowOnHit helper,
## which registers the CHILL status tag (ADR 0013) — making Cripple the
## dagger's chill enabler (feeds Dead Aim partners and Thermal Shock combos).

const SLOW_PCT: float = 0.30
const SLOW_DURATION: float = 2.5


func execute(_owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData):
	pass


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	preload("res://scripts/Abilities/AL_SlowOnHit.gd").apply_slow(_target, SLOW_PCT, SLOW_DURATION)
