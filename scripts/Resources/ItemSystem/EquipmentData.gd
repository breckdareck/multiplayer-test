@tool
@abstract
class_name EquipmentData
extends ItemData

@export var equipment_type: Constants.EquipmentType

@export var bonus_stats: Dictionary = { }

func _init():
	super()
	bonus_stats.clear()
	for stat in Constants.StatType:
		if !bonus_stats.has(stat):
			bonus_stats[Constants.StatType.get(stat)] = StatData.new(Constants.StatType.get(stat), 0)
