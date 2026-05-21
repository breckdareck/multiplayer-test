@tool
class_name SkillTreeData
extends Resource

## A complete skill tree for a single class.
##
## Stored as a .tres file in resources/SkillTrees/ and auto-loaded by
## SkillTreeManager. Each tree is a graph of SkillTreeNodeData entries; the
## edges are defined by each node's prerequisite_node_ids.


## The class this tree belongs to. One tree per class.
@export var class_type: Constants.ClassType = Constants.ClassType.SWORDSMAN

## Display name shown at the top of the skill tree window.
@export var tree_name: String = ""

## All nodes in this tree.
@export var nodes: Array[SkillTreeNodeData] = []


## Returns the node with the given id, or null if not found.
func get_node_by_id(node_id: String) -> SkillTreeNodeData:
	for node in nodes:
		if node and node.node_id == node_id:
			return node
	return null


## Returns true if a node with the given id exists in this tree.
func has_node(node_id: String) -> bool:
	return get_node_by_id(node_id) != null
