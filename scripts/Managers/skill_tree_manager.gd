# SkillTreeManager.gd - Autoload singleton.
#
# Loads every SkillTreeData resource from res://resources/SkillTrees/ and
# provides lookup by class. The actual unlock logic lives in the per-player
# SkillTreeComponent (server-authoritative); this manager is just the data
# registry, mirroring how ResourceManager exposes abilities/classes.
extends Node

## Loaded trees keyed by class type.
var _trees: Dictionary[Constants.ClassType, SkillTreeData] = {}


func _ready() -> void:
	_load_skill_trees()


func _load_skill_trees() -> void:
	var folder: String = "res://resources/SkillTrees/"
	var items := ResourceLoader.list_directory(folder)
	for item_name in items:
		var full_path: String = folder + item_name
		if not (full_path.ends_with(".tres") or full_path.ends_with(".res")):
			continue
		var resource = ResourceLoader.load(full_path)
		if resource is SkillTreeData:
			_trees[resource.class_type] = resource
			#print("SkillTreeManager: Loaded tree '%s' for class %d" % [resource.tree_name, resource.class_type])


## Returns the skill tree for a class, or null if none is defined.
func get_tree_for_class(class_type: Constants.ClassType) -> SkillTreeData:
	return _trees.get(class_type)


## Returns true if the given class has a skill tree defined.
func has_tree_for_class(class_type: Constants.ClassType) -> bool:
	return _trees.has(class_type)
