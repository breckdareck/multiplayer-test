extends Node

## Ability logic for Mage's Teleport.
## Blinks the player forward in their facing direction. Server-authoritative —
## the PlayerSynchronizer propagates the new position to all clients.

func execute(owner_node: Node, _ability: AbilityData, level_stats: AbilityLevelData):


	# Range: 200px base + 10px per level
	var teleport_range: float = 100.0
	var direction: int = 1 if owner_node.facing_direction >= 0 else -1

	owner_node.global_position += Vector2(direction * teleport_range, 0.0)
	owner_node.velocity = Vector2.ZERO

	print("%s teleported %.0fpx (Level %d)" % [owner_node.name, teleport_range, level_stats.level])
