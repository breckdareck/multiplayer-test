@tool
class_name ItemDropResource
extends Resource

## Base stat budgets at item level 1. Scaled up by the item's level via
## BUDGET_GROWTH_PER_LEVEL so higher-level gear rolls more total stats.
## Raised 2026-06-02 (~2x) so dropped gear is a felt upgrade over the roll-less
## starter set — the old Common budget (1-3 split across ~4 stats) left armor
## with ~0 extra DEFENSE, so loot never improved defense in the early game.
const RARITY_BUDGETS = {
	Constants.ItemRarity.COMMON: {"min": 3, "max": 6},
	Constants.ItemRarity.UNCOMMON: {"min": 6, "max": 10},
	Constants.ItemRarity.RARE: {"min": 10, "max": 16},
	Constants.ItemRarity.EPIC: {"min": 16, "max": 24},
	Constants.ItemRarity.LEGENDARY: {"min": 24, "max": 36},
}

## Each item level above 1 grows the stat budget multiplicatively. At 0.035 a
## level-50 item rolls ~2.7x and a level-90 item ~4.1x the base budget, while
## the rarity tiers stay proportional to one another.
const BUDGET_GROWTH_PER_LEVEL := 0.035

## Fraction of every roll reserved for the gear's DEFINING stats (armor →
## DEFENSE/MAGICDEFENSE, weapon → its attack stat), split evenly among them
## before the rest scatters across the full pool. Guarantees a drop improves its
## core role instead of dumping all points into incidental theme stats — the
## fix for "armor drops never raise my defense". (Added 2026-06-02.)
const PRIMARY_BUDGET_SHARE := 0.6

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

func _set(property: StringName, _value) -> bool:
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
	##print(">> Rarity chosen by function: %s" % Constants.ItemRarity.find_key(chosen_rarity))
	item.rarity = chosen_rarity
	##print(">> Rarity assigned to item: %s" % Constants.ItemRarity.find_key(item.rarity))
	
	# 2. Determine Stat Budget based on Rarity, scaled by the item's level
	var budget_range = RARITY_BUDGETS.get(chosen_rarity, {"min": 1, "max": 1})
	var level_scale = _get_level_budget_scale(item.item_level)
	var scaled_min = maxi(1, roundi(budget_range.min * level_scale))
	var scaled_max = maxi(scaled_min, roundi(budget_range.max * level_scale))
	var stat_budget = randi_range(scaled_min, scaled_max)
	
	# 3. Allocate Stats
	var remaining_budget = stat_budget

	# 3a. Reserve a share for the gear's DEFINING stats (armor: DEF/MDEF; weapon:
	# its attack stat), split EVENLY among them so a dropped piece reliably
	# improves its core role. Without this the old greedy shuffle let an
	# incidental theme stat eat the whole (small) budget, so armor drops almost
	# never raised defense.
	var primary := _primary_roll_stats(item)
	if not primary.is_empty():
		var primary_budget: int = mini(remaining_budget, roundi(stat_budget * PRIMARY_BUDGET_SHARE))
		var per: int = primary_budget / primary.size()
		var extra: int = primary_budget % primary.size()
		for i in primary.size():
			var amt: int = per + (1 if i < extra else 0)
			if amt > 0:
				_add_rolled_stat(item, primary[i], amt)
				remaining_budget -= amt

	# 3b. Scatter the remainder across the full pool (greedy, for stat variety).
	var pool: Array = possible_stats.duplicate()
	pool.shuffle()
	for stat_type in pool:
		if remaining_budget <= 0:
			break
		# Assign a random amount for this stat, at least 1
		var amount_to_assign = randi_range(1, remaining_budget)
		_add_rolled_stat(item, stat_type, amount_to_assign)
		remaining_budget -= amount_to_assign


## Adds `amount` to an item's flat bonus for `stat_type`, creating the StatData
## entry if the piece doesn't already carry that stat.
func _add_rolled_stat(item: EquipmentData, stat_type, amount: int) -> void:
	if not item.bonus_stats.has(stat_type):
		var sd := StatData.new()
		sd.stat_type = stat_type
		item.bonus_stats[stat_type] = sd
	(item.bonus_stats[stat_type] as StatData).flat_bonus_value += amount


## The stats that define a piece's core role and so get a guaranteed budget
## share: armor → DEFENSE + MAGICDEFENSE; weapon → whichever attack stat it
## already scales on. Anything else returns empty (no reservation).
func _primary_roll_stats(item: EquipmentData) -> Array:
	if item is ArmorData:
		return [Constants.StatType.DEFENSE, Constants.StatType.MAGICDEFENSE]
	if item is WeaponData:
		var out: Array = []
		if item.bonus_stats.has(Constants.StatType.WEAPONATTACK):
			out.append(Constants.StatType.WEAPONATTACK)
		if item.bonus_stats.has(Constants.StatType.MAGICATTACK):
			out.append(Constants.StatType.MAGICATTACK)
		return out
	return []

## Multiplier applied to the base rarity budget based on the item's level.
## Level 1 (or lower / unset) leaves the budget unchanged.
func _get_level_budget_scale(item_level: int) -> float:
	if item_level <= 1:
		return 1.0
	return 1.0 + (item_level - 1) * BUDGET_GROWTH_PER_LEVEL


func _choose_random_rarity() -> Constants.ItemRarity:
	##print("--- Choosing Random Rarity ---")
	
	# Filter chances to only include valid rarity keys from the enum
	var valid_chances: Dictionary = {}
	for rarity_name in Constants.ItemRarity.keys():
		# Check for key (case-insensitive) in the exported dictionary
		for key in rarity_chances:
			if str(key).to_upper() == rarity_name:
				valid_chances[rarity_name] = rarity_chances[key]
				break # Move to next enum key

	##print("Rarity Chances (validated): ", valid_chances)

	var total_weight = 0
	for rarity_key in valid_chances:
		total_weight += valid_chances[rarity_key]

	##print("Total Weight: ", total_weight)

	if total_weight <= 0:
		push_warning("ItemDropResource has no valid rarity weights defined.")
		return Constants.ItemRarity.COMMON

	var random_weight = randi_range(1, total_weight)
	##print("Random Weight Chosen: ", random_weight)
	var current_weight = 0
	
	for rarity_key in valid_chances:
		current_weight += valid_chances[rarity_key]
		##print("Checking rarity: %s, Current Weight: %d" % [rarity_key, current_weight])
		if random_weight <= current_weight:
			# We know the key is valid now, so find_key won't fail
			var rarity_val = Constants.ItemRarity[rarity_key]
			##print("Selected Rarity: %s (Value: %d)" % [rarity_key, rarity_val])
			##print("------------------------------")
			return rarity_val
			
	##print("Loop finished without selection, falling back to COMMON.")
	##print("------------------------------")
	return Constants.ItemRarity.COMMON


## Call this anytime to print the current rarity percentages for quick reference.
func _print_rarity_percentages() -> void:
	var total_weight := 0.0
	for key in rarity_chances:
		total_weight += float(rarity_chances[key])
	
	if total_weight <= 0:
		#print("⚠ Total weight is zero — no valid chances defined.")
		return
	
	##print("\n=== Rarity Percentages ===")
	for rarity_name in Constants.ItemRarity.keys():
		var _weight = rarity_chances.get(rarity_name, 0)
		#print("%s: %.2f%%" % [rarity_name.to_upper(), (float(_weight) / total_weight) * 100.0])
	#print("Total: %.2f%%\n" % total_weight)

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
