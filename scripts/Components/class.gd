class_name ClassComponent
extends Node

signal class_changed(new_class: String)

enum ClassType {SWORDSMAN, ARCHER, MAGE}

@export var current_class: ClassType = ClassType.SWORDSMAN

@export_category("Class Bonuses")
@export var class_bonuses: Dictionary = {
	ClassType.SWORDSMAN: {"strength_bonus": 5, "vitality_bonus": 3},
	ClassType.ARCHER: {"dexterity_bonus": 8, "strength_bonus": 2},
	ClassType.MAGE: {"intelligence_bonus": 10, "vitality_bonus": 1}
}

@export_category("Class Skills")
@export var class_skills: Dictionary = {
	ClassType.SWORDSMAN: ["slash", "charge", "shield_bash"],
	ClassType.ARCHER: ["quick_shot", "multi_shot", "evasion"],
	ClassType.MAGE: ["fireball", "ice_shield", "teleport"]
}

var _stats_component: StatsComponent

func _ready() -> void:
	_stats_component = get_parent().get_node_or_null("Stats")
	if not multiplayer.is_server():
		return
		
	if _stats_component:
		class_changed.connect(_on_class_changed)
		# Initial stats calculation with current class
		_on_class_changed(get_class_name())

func get_class_name() -> String:
	match current_class:
		ClassType.SWORDSMAN:
			return "swordsman"
		ClassType.ARCHER:
			return "archer"
		ClassType.MAGE:
			return "mage"
		_:
			return "unknown"

func get_class_bonuses() -> Dictionary:
	return class_bonuses.get(current_class, {})

func get_available_skills() -> Array:
	return class_skills.get(current_class, [])

func get_class_summary() -> Dictionary:
	return {
		"class_name": get_class_name(),
		"class_type": current_class,
		"bonuses": get_class_bonuses(),
		"skills": get_available_skills()
	}

func change_class(new_class: ClassType) -> void:
	if new_class != current_class:
		print("ClassComponent: Changing class from %s to %s" % [get_class_name(), ClassType.keys()[new_class]])
		current_class = new_class
		class_changed.emit(get_class_name())

@rpc("authority", "call_local", "reliable")
func change_class_rpc(new_class: int) -> void:
	change_class(new_class)

func _on_class_changed(new_class: String) -> void:
	# Update stats with class bonuses
	if _stats_component:
		print("ClassComponent: Class changed to %s, recalculating stats..." % new_class)
		_stats_component._recalculate_stats()
	else:
		push_warning("ClassComponent: No Stats component found for stats recalculation")
