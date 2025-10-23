@tool
class_name ItemDropResource
extends Resource

## The item that can drop (reference by name for easy setup)
@export var item_name: String = ""

## Chance to drop (0.0 to 1.0, where 1.0 = 100%)
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.5

## Minimum amount to drop (for stackable items)
@export var min_amount: int = 1

## Maximum amount to drop (for stackable items)
@export var max_amount: int = 1

## Returns true if this drop should occur based on drop_chance
func should_drop() -> bool:
	return randf() <= drop_chance

## Returns a random amount between min and max
func get_drop_amount() -> int:
	if min_amount == max_amount:
		return min_amount
	return randi_range(min_amount, max_amount)

## Gets the ItemData from ResourceManager
func get_item_data() -> ItemData:
	if item_name.is_empty():
		return null
	return ResourceManager.get_item_by_name(item_name)
