@tool
class_name SkillTreeNodeData
extends Resource

## A single node in a class skill tree.
##
## A node references an existing ability (by its ability_name, which is stable
## and the same identifier ResourceManager / AbilityComponent already use) and
## lists the requirements that must be satisfied before it can be unlocked.
##
## Unlocking a node grants the referenced ability through the AbilityComponent
## (learns it, or levels it once if already known). Trees are pure data — no
## ability is redefined here, the node only points at one.


## Stable identifier for this node within its tree. Used by save data and by
## other nodes' prerequisite lists. Keep it short and unique per tree
## (e.g. "power_strike", "brandish").
@export var node_id: String = ""

## Human-readable label shown in the UI. Falls back to the ability name.
@export var display_name: String = ""

## The ability this node grants. Matched against AbilityData.ability_name via
## ResourceManager.get_ability_data(). Leave empty only for a pure layout node.
@export var ability_name: String = ""

## Skill points required to unlock this node.
@export var skill_point_cost: int = 1

## Minimum character level required to unlock this node. 0 = no requirement.
@export var required_level: int = 0

## node_ids of prerequisite nodes in the SAME tree. All listed nodes must be
## unlocked before this node becomes eligible.
@export var prerequisite_node_ids: PackedStringArray = PackedStringArray()

## Grid position used purely for laying the node out in the tree UI.
## x = column, y = row. Connections are drawn from prerequisites to this node.
@export var ui_position: Vector2i = Vector2i.ZERO

## Optional override description shown in the UI. Falls back to the ability's
## own description when empty.
@export_multiline var description: String = ""


func get_display_name() -> String:
	if not display_name.is_empty():
		return display_name
	return ability_name
