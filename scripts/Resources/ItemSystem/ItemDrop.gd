@tool
class_name ItemDropResource
extends Resource

const RARITY_BUDGETS = {
	Constants.ItemRarity.COMMON: {"min": 1, "max": 3},
	Constants.ItemRarity.UNCOMMON: {"min": 3, "max": 6},
	Constants.ItemRarity.RARE: {"min": 6, "max": 10},
	Constants.ItemRarity.EPIC: {"min": 10, "max": 15},
	Constants.ItemRarity.LEGENDARY: {"min": 15, "max": 22},
}

## The item that can drop (reference by name for easy setup)
@export var item_name: String = ""

@export_group("Randomization")
@export var randomize_stats: bool = false

## Relative weights for each rarity tier (higher = more likely)
@export var rarity_chances: Dictionary = {"COMMON": 100, "UNCOMMON": 30, "RARE": 10, "EPIC": 3, "LEGENDARY": 1}
@export var possible_stats: Array[Constants.StatType]

@export_group("Drop Settings")

## Chance to drop (0.0 to 1.0, where 1.0 = 100%)
@export_range(0.0, 1.0, 0.01) var drop_chance: float = 0.5

## Minimum amount to drop (for stackable items)
@export var min_amount: int = 1

## Maximum amount to drop (for stackable items)
@export var max_amount: int = 1

func _get_property_list() -> Array[Dictionary]:
	var properties: Array[Dictionary] = []

	var breakdown = "Chances are relative. Current breakdown:\n"
	var percentages = get_rarity_percentages()
	for rarity_name in percentages:
		breakdown += "%s: %.1f%%\n" % [rarity_name, percentages[rarity_name]]

	properties.append({
		"name": "rarity_breakdown",
		"type": TYPE_STRING,
		"usage": PROPERTY_USAGE_EDITOR,
		"hint": PROPERTY_HINT_MULTILINE_TEXT,
	})

	return properties

func _get(property: StringName):
	if property == &"rarity_breakdown":
		var text = ""
		var percentages = get_rarity_percentages()
		for rarity_name in percentages:
			text += "%s: %.1f%%\n" % [rarity_name, percentages[rarity_name]]
		return text.strip_edges()
	return null

func _set(property: StringName, value) -> bool:
	if property == &"rarity_breakdown":
		notify_property_list_changed()
		return true
	return false


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
	
	var dropped_item = base_item.duplicate_with_path(true) as ItemData
	
	if randomize_stats and dropped_item is EquipmentData:
		_apply_random_stats(dropped_item as EquipmentData)
		
	return dropped_item


func _apply_random_stats(item: EquipmentData) -> void:
	# 1. Determine Rarity
	var chosen_rarity = _choose_random_rarity()
	print(">> Rarity chosen by function: %s" % Constants.ItemRarity.find_key(chosen_rarity))
	item.rarity = chosen_rarity
	print(">> Rarity assigned to item: %s" % Constants.ItemRarity.find_key(item.rarity))
	
	# 2. Determine Stat Budget based on Rarity
	var budget_range = RARITY_BUDGETS.get(chosen_rarity, {"min": 1, "max": 1})
	var stat_budget = randi_range(budget_range.min, budget_range.max)
	
	# 3. Allocate Stats
	var remaining_budget = stat_budget
	
	# Shuffle possible_stats to ensure random distribution order
	possible_stats.shuffle()
	
	for stat_type in possible_stats:
		if remaining_budget <= 0:
			break
		
		# Assign a random amount for this stat, at least 1
		var amount_to_assign = randi_range(1, remaining_budget)
		
		# Ensure a StatData object exists for this type in the item's bonus_stats
		if not item.bonus_stats.has(stat_type):
			item.bonus_stats[stat_type] = StatData.new()
			(item.bonus_stats[stat_type] as StatData).stat_type = stat_type

		var stat_data_instance: StatData = item.bonus_stats[stat_type]
		stat_data_instance.flat_bonus_value += amount_to_assign
		remaining_budget -= amount_to_assign

func _choose_random_rarity() -> Constants.ItemRarity:
	print("--- Choosing Random Rarity ---")
	
	# Filter chances to only include valid rarity keys from the enum
	var valid_chances: Dictionary = {}
	for rarity_name in Constants.ItemRarity.keys():
		# Check for key (case-insensitive) in the exported dictionary
		for key in rarity_chances:
			if str(key).to_upper() == rarity_name:
				valid_chances[rarity_name] = rarity_chances[key]
				break # Move to next enum key

	print("Rarity Chances (validated): ", valid_chances)

	var total_weight = 0
	for rarity_key in valid_chances:
		total_weight += valid_chances[rarity_key]

	print("Total Weight: ", total_weight)

	if total_weight <= 0:
		push_warning("ItemDropResource has no valid rarity weights defined.")
		return Constants.ItemRarity.COMMON

	var random_weight = randi_range(1, total_weight)
	print("Random Weight Chosen: ", random_weight)
	var current_weight = 0
	
	for rarity_key in valid_chances:
		current_weight += valid_chances[rarity_key]
		print("Checking rarity: %s, Current Weight: %d" % [rarity_key, current_weight])
		if random_weight <= current_weight:
			# We know the key is valid now, so find_key won't fail
			var rarity_val = Constants.ItemRarity[rarity_key]
			print("Selected Rarity: %s (Value: %d)" % [rarity_key, rarity_val])
			print("------------------------------")
			return rarity_val
			
	print("Loop finished without selection, falling back to COMMON.")
	print("------------------------------")
	return Constants.ItemRarity.COMMON


## Call this anytime to print the current rarity percentages for quick reference.
func _print_rarity_percentages() -> void:
	var total_weight := 0.0
	for key in rarity_chances:
		total_weight += float(rarity_chances[key])
	
	if total_weight <= 0:
		print("⚠ Total weight is zero — no valid chances defined.")
		return
	
	print("\n=== Rarity Percentages ===")
	for rarity_name in Constants.ItemRarity.keys():
		var weight = rarity_chances.get(rarity_name, 0)
		var percentage := (float(weight) / total_weight) * 100.0
		print("%s: %.2f%%" % [rarity_name.to_upper(), percentage])
	print("Total: %.2f%%\n" % total_weight)

## Returns a dictionary of rarity -> percentage for programmatic use.
func get_rarity_percentages() -> Dictionary:
	var result := {}
	var total_weight := 0.0
	for key in rarity_chances:
		total_weight += float(rarity_chances[key])
	
	if total_weight <= 0:
		return result
	
	for rarity_name in Constants.ItemRarity.keys():
		var weight = rarity_chances.get(rarity_name, 0)
		result[rarity_name] = (float(weight) / total_weight) * 100.0
	
	return result
