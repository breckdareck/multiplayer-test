@tool
@abstract
class_name EquipmentData
extends ItemData

@export var equipment_type: Constants.EquipmentType

@export var bonus_stats: Dictionary[Constants.StatType, StatData] = { }

func _init():
	super()
