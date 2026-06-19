@tool
class_name ItemDropResource
extends Resource

## AFFIX-based rolls (2026-06-08). Replaces the old single greedy stat-budget that
## dumped everything into 1-2 random stats (feast/famine, illegible rarity, uncapped
## crit stacking). A drop now boosts its DEFINING stat(s), then rolls a FIXED number
## of DISTINCT bonus affixes by rarity, each drawn from the item's pool (weighted
## toward its signature) with a per-stat, per-rarity capped magnitude.

## How many bonus affixes a drop rolls, by rarity (higher = more, legible value).
const AFFIX_COUNT := {
	Constants.ItemRarity.COMMON: 1,
	Constants.ItemRarity.UNCOMMON: 2,
	Constants.ItemRarity.RARE: 3,
	Constants.ItemRarity.EPIC: 4,
	Constants.ItemRarity.LEGENDARY: 5,
}

## Per-affix magnitude multiplier by rarity (a Legendary affix rolls bigger).
const RARITY_AFFIX_MULT := {
	Constants.ItemRarity.COMMON: 0.7,
	Constants.ItemRarity.UNCOMMON: 0.9,
	Constants.ItemRarity.RARE: 1.1,
	Constants.ItemRarity.EPIC: 1.35,
	Constants.ItemRarity.LEGENDARY: 1.7,
}

## One-affix roll range [min, max] PER ITEM LEVEL (before the rarity multiplier).
## Crit / evasion / accuracy roll SMALL (each point is worth far more than a point
## of an attribute); HP/MANA roll large. Tuned so a crit-focused legendary SET adds
## ~+15-25% crit (capped) instead of the old uncapped +100%.
const AFFIX_SCALE := {
	Constants.StatType.STRENGTH: [0.15, 0.35],
	Constants.StatType.DEXTERITY: [0.15, 0.35],
	Constants.StatType.INTELLIGENCE: [0.15, 0.35],
	Constants.StatType.LUCK: [0.15, 0.35],
	Constants.StatType.CONSTITUTION: [0.18, 0.40],
	Constants.StatType.HEALTH: [0.8, 1.6],
	Constants.StatType.MANA: [0.6, 1.2],
	Constants.StatType.HPREGEN: [0.05, 0.12],
	Constants.StatType.MPREGEN: [0.05, 0.12],
	Constants.StatType.DEFENSE: [0.2, 0.4],
	Constants.StatType.MAGICDEFENSE: [0.2, 0.4],
	Constants.StatType.CRITCHANCE: [0.03, 0.05],
	Constants.StatType.CRITDAMAGE: [0.05, 0.10],
	Constants.StatType.EVASIONCHANCE: [0.03, 0.05],
	Constants.StatType.ACCURACY: [0.05, 0.10],
	Constants.StatType.KNOCKBACKRESIST: [0.1, 0.25],
}
const DEFAULT_AFFIX_SCALE := [0.1, 0.25]

## Defining stat(s) (armor strong-defense, weapon attack) always roll at this
## multiple of a normal affix so a drop reliably improves its core role.
const DEFINING_AFFIX_MULT := 1.8

## The ATTRIBUTE half of an armor's defining pair (family primary: STR on plate,
## INT on robes, ...) rolls smaller than the defense half — at the full 1.8x a
## Legendary set's rolled primary (~+300) would dwarf the legendary weapon roll.
const DEFINING_ATTR_MULT := 1.2

## The four allocatable damage attributes — used to pick an armor family's
## primary for its defining pair and to choose the defining multiplier.
const ATTRIBUTE_STAT_TYPES := [
	Constants.StatType.STRENGTH, Constants.StatType.DEXTERITY,
	Constants.StatType.INTELLIGENCE, Constants.StatType.LUCK,
]

## Affix-selection weight = base stat value + this floor, so a set's SIGNATURE stats
## (high base) are favoured while every pooled stat keeps a real chance.
const AFFIX_WEIGHT_FLOOR := 25.0

## The item that can drop (reference by name for easy setup)
@export var item_name: String = ""

@export_group("Randomization")
@export var randomize_stats: bool = false

## Relative weights for each rarity tier (higher = more likely). Eased 2026-06-19 (was
## 100/30/10/3/1) so build-defining gear isn't a multi-hour drought: P(RARE+) 9.7%->14.3%,
## P(EPIC+) 2.8%->4.5%. Generated drop tables inherit this default (they don't override it).
@export var rarity_chances: Dictionary = {"COMMON": 100, "UNCOMMON": 32, "RARE": 15, "EPIC": 5, "LEGENDARY": 2}
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
## min_rarity (a Constants.ItemRarity int, -1 = no floor) raises a randomized equip
## drop's rarity to at least that tier — used by the kill-drop pity (bad-luck protection).
func get_item_data(min_rarity: int = -1) -> ItemData:
	if item_name.is_empty():
		return null
	
	var base_item = ResourceManager.get_item_by_name(item_name)
	if not base_item:
		return null
	
	var dropped_item = base_item.duplicate_with_path(true) as ItemData
	
	if randomize_stats and dropped_item is EquipmentData:
		_apply_random_stats(dropped_item as EquipmentData, min_rarity)

	return dropped_item


func _apply_random_stats(item: EquipmentData, min_rarity: int = -1) -> void:
	# 1. Rarity drives BOTH the affix count and the per-affix magnitude.
	var rarity = _choose_random_rarity()
	if min_rarity >= 0 and int(rarity) < min_rarity:
		rarity = min_rarity as Constants.ItemRarity   # pity floor (bad-luck protection)
	item.rarity = rarity
	var ilv: int = maxi(1, item.item_level)
	var rmult: float = float(RARITY_AFFIX_MULT.get(rarity, 1.0))

	# 2. DEFINING stats (armor: strong defense + family primary attribute,
	#    weapon: attack) — a guaranteed boost so a drop reliably improves the
	#    stats its wearer picked the piece for. Attribute halves roll at the
	#    smaller DEFINING_ATTR_MULT (see const note).
	var defining := _primary_roll_stats(item)
	for stat_type in defining:
		var dmult: float = DEFINING_ATTR_MULT if ATTRIBUTE_STAT_TYPES.has(stat_type) else DEFINING_AFFIX_MULT
		_add_rolled_stat(item, stat_type, _roll_affix_value(stat_type, ilv, rmult * dmult))

	# 3. N DISTINCT bonus affixes (by rarity) from the non-defining pool, weighted
	#    toward the item's signature stats (their base magnitude).
	var count: int = int(AFFIX_COUNT.get(rarity, 1))
	var pool: Array = []
	for s in possible_stats:
		if not defining.has(s):
			pool.append(s)
	for stat_type in _weighted_sample(item, pool, count):
		_add_rolled_stat(item, stat_type, _roll_affix_value(stat_type, ilv, rmult))


## One affix's value: randi_range over the stat's per-level [min,max] x item level x
## rarity multiplier (at least 1). Different stats have different value densities.
func _roll_affix_value(stat_type, ilv: int, mult: float) -> int:
	var rng: Array = AFFIX_SCALE.get(stat_type, DEFAULT_AFFIX_SCALE)
	var lo: int = maxi(1, roundi(float(rng[0]) * ilv * mult))
	var hi: int = maxi(lo, roundi(float(rng[1]) * ilv * mult))
	return randi_range(lo, hi)


## Picks `count` DISTINCT stats from `pool` weighted by (base value + floor), so a
## set's signature stats are favoured but every pooled stat keeps a real chance.
func _weighted_sample(item: EquipmentData, pool: Array, count: int) -> Array:
	var picks: Array = []
	var avail: Array = pool.duplicate()
	for _i in range(mini(count, avail.size())):
		var total: float = 0.0
		for s in avail:
			total += _affix_weight(item, s)
		var r: float = randf() * total
		var acc: float = 0.0
		var chosen = avail[0]
		for s in avail:
			acc += _affix_weight(item, s)
			if r <= acc:
				chosen = s
				break
		picks.append(chosen)
		avail.erase(chosen)
	return picks


func _affix_weight(item: EquipmentData, stat_type) -> float:
	var base: float = 0.0
	if item.bonus_stats.has(stat_type):
		base = float((item.bonus_stats[stat_type] as StatData).flat_bonus_value)
	return base + AFFIX_WEIGHT_FLOOR


## Adds `amount` to an item's flat bonus for `stat_type`, creating the StatData
## entry if the piece doesn't already carry that stat.
func _add_rolled_stat(item: EquipmentData, stat_type, amount: int) -> void:
	if not item.bonus_stats.has(stat_type):
		var sd := StatData.new()
		sd.stat_type = stat_type
		item.bonus_stats[stat_type] = sd
	(item.bonus_stats[stat_type] as StatData).flat_bonus_value += amount


## The stats that define a piece's core role and so get a guaranteed budget
## share: armor → its STRONG defense (larger base; tie → DEFENSE) + its family
## primary attribute (largest base among STR/DEX/INT/LUCK), derived from the
## piece itself so hand-authored gear needs no extra data; weapon → whichever
## attack stat it already scales on. Anything else returns empty (no
## reservation). The weak defense is deliberately NOT defining — it competes
## in the bonus-affix pool like any flavour stat (2026-06-11 archetype pass).
func _primary_roll_stats(item: EquipmentData) -> Array:
	if item is ArmorData:
		var out: Array = []
		var d := _base_stat_value(item, Constants.StatType.DEFENSE)
		var md := _base_stat_value(item, Constants.StatType.MAGICDEFENSE)
		out.append(Constants.StatType.MAGICDEFENSE if md > d else Constants.StatType.DEFENSE)
		var best_attr: int = -1
		var best_val: int = 0
		for s in ATTRIBUTE_STAT_TYPES:
			var v := _base_stat_value(item, s)
			if v > best_val:
				best_val = v
				best_attr = s
		if best_attr != -1:
			out.append(best_attr)
		return out
	if item is WeaponData:
		var out: Array = []
		if item.bonus_stats.has(Constants.StatType.WEAPONATTACK):
			out.append(Constants.StatType.WEAPONATTACK)
		if item.bonus_stats.has(Constants.StatType.MAGICATTACK):
			out.append(Constants.StatType.MAGICATTACK)
		return out
	return []


func _base_stat_value(item: EquipmentData, stat_type) -> int:
	if item.bonus_stats.has(stat_type):
		return int((item.bonus_stats[stat_type] as StatData).flat_bonus_value)
	return 0

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
