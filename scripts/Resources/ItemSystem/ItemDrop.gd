@tool
class_name ItemDropResource
extends Resource

## The item that can drop (reference by name for easy setup)
@export var item_name: String = ""

@export_group("Randomization")
@export var randomize_stats: bool = false
## Chances are relative. E.g., {COMMON:100, UNCOMMON:30, RARE:10} means ~71% Common, ~21% Uncommon, ~7% Rare.
@export var rarity_chances: Dictionary = {&"COMMON": 100, &"UNCOMMON": 30, &"RARE": 10, &"EPIC": 3, &"LEGENDARY": 1}
@export var stat_budget_min: int = 1
@export var stat_budget_max: int = 5
@export var possible_stats: Array[Constants.StatType]

@export_group("Drop Settings")

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
	
	var base_item = ResourceManager.get_item_by_name(item_name)
	if not base_item:
		return null
	
	var dropped_item = base_item.duplicate_with_path() as ItemData
	
	if randomize_stats and dropped_item is EquipmentData:
		_apply_random_stats(dropped_item as EquipmentData)
		
	return dropped_item


func _apply_random_stats(item: EquipmentData) -> void:
	# 1. Determine Rarity
	var chosen_rarity = _choose_random_rarity()
	item.rarity = chosen_rarity
	
	# 2. Determine Stat Budget
	var stat_budget = randi_range(stat_budget_min, stat_budget_max)
	
	# 3. Allocate Stats
	var allocated_stats: Dictionary = {}
	var remaining_budget = stat_budget
	
	# Shuffle possible_stats to ensure random distribution order
	possible_stats.shuffle()
	
	for stat_type in possible_stats:
		if remaining_budget <= 0:
			break
		
		# Assign a random amount for this stat, at least 1
		var amount_to_assign = randi_range(1, remaining_budget)
		
		# For simplicity, let's just assign a flat value.
		# More complex logic could involve rarity multipliers, stat curves, etc.
		if not allocated_stats.has(stat_type):
			allocated_stats[stat_type] = StatData.new()
			(allocated_stats[stat_type] as StatData).stat_type = stat_type
		
		(allocated_stats[stat_type] as StatData).base_value += amount_to_assign
		remaining_budget -= amount_to_assign
	
	item.bonus_stats = allocated_stats


func _choose_random_rarity() -> Constants.ItemRarity:
	var total_weight = 0
	for rarity_str in rarity_chances.keys():
		total_weight += rarity_chances[rarity_str]
	
	var random_weight = randi_range(1, total_weight)
	var current_weight = 0
	
	for rarity_str in rarity_chances.keys():
		current_weight += rarity_chances[rarity_str]
		if random_weight <= current_weight:
			return Constants.ItemRarity.find_key(rarity_str)
			
	return Constants.ItemRarity.COMMON # Fallback
