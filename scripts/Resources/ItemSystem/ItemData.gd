@tool
extends Resource
class_name ItemData

const BASE_VALUE_CURVE = preload("uid://d1qhydj4bri7d")

@export var item_id: String:
	set(value):
		if value.is_empty():
			item_id = generate_uuid()
		else:
			item_id = value
@export var name: String
@export var rarity: Constants.ItemRarity = Constants.ItemRarity.COMMON
@export var icon: Texture2D
@export var description: String
@export var item_type: Constants.ItemType:
	set(it):
		item_type = it
		if it == Constants.ItemType.EQUIPMENT:
			can_stack = false
			max_stack_amount = 0
		else:
			can_stack = true
			max_stack_amount = 99
		notify_property_list_changed()
@export var item_level: int = 0
@export var custom_item_value: int = 0

var base_value: int:
	get:
		if item_level >= 0:
			return round(BASE_VALUE_CURVE.sample(item_level))
		else:
			return custom_item_value

var can_stack: bool
var max_stack_amount: int
var current_stack_amount: int = 1

var original_resource_path: String
var instance_id: String


func _get_property_list():
	if OS.has_feature("editor"):
		var ret =[]
		if item_type != Constants.ItemType.EQUIPMENT:
			ret.append({
				"name": &"can_stack",
				"type": TYPE_BOOL,
				"usage": PROPERTY_USAGE_DEFAULT,
				})
			ret.append({
				"name": &"max_stack_amount",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT,
				})
			ret.append({
				"name": &"current_stack_amount",
				"type": TYPE_INT,
				"usage": PROPERTY_USAGE_DEFAULT,
				})
		return ret
	return []


func generate_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32))
	]


func _init():
	instance_id = generate_uuid()
	# Only generate a UUID if one doesn't already exist.
	if item_id.is_empty():
		item_id = generate_uuid()


func get_resource_path() -> String:
	if not resource_path.is_empty():
		return resource_path
	return original_resource_path


# Custom duplicate method that preserves resource path information
func duplicate_with_path(subresources: bool = false) -> ItemData:
	var duplicated = super.duplicate(subresources) as ItemData
	# Store the original resource path in our custom property (not the built-in resource_path)
	duplicated.original_resource_path = get_resource_path()
	return duplicated


func to_dictionary() -> Dictionary:
	var res_path = get_resource_path()
	if res_path.is_empty() and not name.is_empty():
		var item_from_manager = ResourceManager.get_item_by_name(name)
		if item_from_manager:
			res_path = item_from_manager.get_resource_path()

	var icon_path := ""
	if icon:
		icon_path = icon.resource_path
	
	if icon_path.is_empty() and not res_path.is_empty():
		var original_res = load(res_path)
		if original_res and original_res.icon:
			icon_path = original_res.icon.resource_path

	var dict = {
		"item_id": item_id,
		"name": name,
		"rarity": rarity,
		"icon_path": icon_path,
		"description": description,
		"item_type": item_type,
		"item_level": item_level,
		"custom_item_value": custom_item_value,
		"can_stack": can_stack,
		"max_stack_amount": max_stack_amount,
		"current_stack_amount": current_stack_amount,
		"original_resource_path": res_path,
	}
	
	return dict


static func from_dictionary(dict: Dictionary) -> ItemData:
	var item_type_enum = dict.get("item_type", Constants.ItemType.ANY)
	var item_instance: ItemData
	if item_type_enum == Constants.ItemType.EQUIPMENT:
		item_instance = EquipmentData.from_dictionary(dict)
		if item_instance == null: # Handle error from EquipmentData.from_dictionary
			return null
	elif item_type_enum == Constants.ItemType.CONSUMABLE:
		item_instance = ConsumableData.from_dictionary(dict)
		if item_instance == null:
			return null
	else:
		item_instance = ItemData.new()
		# Populate ItemData properties for non-equipment items
		item_instance.item_id = dict.get("item_id", ItemData.new().generate_uuid())
		item_instance.name = dict.get("name", "")
		item_instance.rarity = dict.get("rarity", Constants.ItemRarity.COMMON)
		var icon_path = dict.get("icon_path", "")
		if not icon_path.is_empty():
			item_instance.icon = load(icon_path)
		
		item_instance.description = dict.get("description", "")
		item_instance.item_type = item_type_enum
		item_instance.item_level = dict.get("item_level", 0)
		item_instance.custom_item_value = dict.get("custom_item_value", 0)
		item_instance.can_stack = dict.get("can_stack", false)
		item_instance.max_stack_amount = dict.get("max_stack_amount", 0)
		item_instance.current_stack_amount = dict.get("current_stack_amount", 1)
		item_instance.original_resource_path = dict.get("original_resource_path", "")
	return item_instance
