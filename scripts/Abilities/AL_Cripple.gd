extends Node

## Ability logic for Rogue's Disorder.
## The hitbox deals damage via the standard combat system.
## The debuff is applied automatically by combat.gd via applies_target_debuff.
## This script exists for any additional on-cast effects.

func execute(owner_node: Node, _ability: AbilityData, level_stats: AbilityLevelData):
	#print("%s used Disorder (Level %d)" % [owner_node.name, level_stats.level])
