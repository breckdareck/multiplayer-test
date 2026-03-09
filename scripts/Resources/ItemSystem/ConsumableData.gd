@tool
class_name ConsumableData
extends ItemData

@export_group("Consumable Effect")
## The script that runs when this item is used.
@export var effect_script: Script
## A dictionary of properties to pass to the effect script.
## Example: {"heal_amount": 50, "buff_duration": 10.0}
@export var effect_properties: Dictionary

func _init():
	super()
	item_type = Constants.ItemType.CONSUMABLE

func to_dictionary() -> Dictionary:
	var dict = super.to_dictionary()
	if effect_script:
		dict["effect_script_path"] = effect_script.resource_path
	dict["effect_properties"] = effect_properties
	return dict


func get_save_data() -> Dictionary:
	var dict = super.get_save_data()
	if effect_script:
		dict["effect_script_path"] = effect_script.resource_path
	dict["effect_properties"] = effect_properties
	return dict

static func from_dictionary(dict: Dictionary) -> ItemData:
	var item_instance = ConsumableData.new()

	# Populate base ItemData properties
	item_instance.item_id = dict.get("item_id", item_instance.generate_uuid())
	item_instance.instance_id = dict.get("instance_id", item_instance.generate_uuid())
	item_instance.name = dict.get("name", "")
	item_instance.rarity = dict.get("rarity", Constants.ItemRarity.COMMON)
	var icon_path = dict.get("icon_path", "")
	if not icon_path.is_empty():
		item_instance.icon = load(icon_path)
	item_instance.description = dict.get("description", "")
	item_instance.item_type = dict.get("item_type", Constants.ItemType.CONSUMABLE)
	item_instance.item_level = dict.get("item_level", 0)
	item_instance.custom_item_value = dict.get("custom_item_value", 0)
	item_instance.can_stack = dict.get("can_stack", true)
	item_instance.max_stack_amount = dict.get("max_stack_amount", 99)
	item_instance.current_stack_amount = dict.get("current_stack_amount", 1)
	item_instance.original_resource_path = dict.get("original_resource_path", "")

	# Populate ConsumableData properties
	var script_path = dict.get("effect_script_path", "")
	if not script_path.is_empty():
		item_instance.effect_script = load(script_path)
	item_instance.effect_properties = dict.get("effect_properties", {})

	# Fallback: if effect data wasn't in save data, recover from original .tres resource
	if not item_instance.effect_script and not item_instance.original_resource_path.is_empty():
		var original = load(item_instance.original_resource_path)
		if original is ConsumableData:
			item_instance.effect_script = original.effect_script
			if item_instance.effect_properties.is_empty():
				item_instance.effect_properties = original.effect_properties

	return item_instance
