@tool
extends Resource
class_name ItemData

@export var item_id: String:
	set(value):
		if value.is_empty():
			item_id = generate_uuid()
		else:
			item_id = value
@export var name: String
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
			
@export var base_value: int = 1

var can_stack: bool
var max_stack_amount: int
var current_stack_amount: int = 1

var original_resource_path: String


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
