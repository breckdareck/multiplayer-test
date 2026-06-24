extends RefCounted

## Map-scope filtering for the GLOBAL "Enemies" / "Players" groups.
##
## The "Enemies" group spans EVERY resident map (CLAUDE.md "Global groups"), and
## maps share world coordinates (each loads at its own origin), so a proximity
## test alone — distance(origin, enemy) <= radius — silently matches an enemy
## standing at the same LOCAL position on a DIFFERENT map. That leaks mark
## spreads, bleed/burn riders, and chain/AoE hits across maps (e.g. a bot's fire
## wave igniting enemies on the map a player is standing on).
##
## Resolve the actor's map ONCE, then drop every candidate that isn't under it.
## Centralized here so a new proximity ability can't re-introduce the leak by
## copy-pasting an unfiltered loop. Mirrors combat._is_on_same_map's semantics.

## The map scene_instance that contains `node`, or null if none does (the node
## was just freed, or sits outside any active map). Resolve once per cast, then
## reuse for every candidate in the loop.
static func map_of(node: Node) -> Node:
	if not is_instance_valid(node):
		return null
	for map_id in MapManager.active_maps.keys():
		var inst = MapManager.active_maps[map_id].get("scene_instance")
		if is_instance_valid(inst) and inst.is_ancestor_of(node):
			return inst
	return null

## True if `other` lives under `map_node`. A null `map_node` (unresolved map)
## falls back to TRUE — matching combat._is_on_same_map: never silently swallow a
## legitimate same-map effect just because the map lookup failed.
static func contains(map_node: Node, other: Node) -> bool:
	if map_node == null:
		return true
	return is_instance_valid(other) and map_node.is_ancestor_of(other)
