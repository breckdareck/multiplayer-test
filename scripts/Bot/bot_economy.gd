extends RefCounted
## Bot economy: inventory queries, selling junk to merchants, and restocking
## potions. Owned by a BotBrain — run_maintenance() is ticked on the brain's
## shop timer. Exposes needs_restock / needs_sell (which the brain's think loop
## reads to route the bot to a town merchant) and has_inventory_space() for the
## brain's loot logic.

const SELL_FULLNESS_THRESHOLD: float = 0.85
const POTION_STOCK_TARGET: int = 20
const POTION_RESTOCK_THRESHOLD: int = 0

var brain                       ## The owning BotBrain node.
var needs_restock: bool = false
## Set when the bag is full and no merchant is on this map — routes to town to sell.
var needs_sell: bool = false
## Potion buy prices learned at a merchant (effect_key -> price). Lets the
## affordability gate use the real price on maps with no merchant to query.
var _merchant_pot_cache: Dictionary = {}


func _init(owner_brain) -> void:
	brain = owner_brain


## Periodic inventory upkeep: sell junk, buy potions, and update the
## needs_restock / needs_sell flags the think loop acts on.
func run_maintenance() -> void:
	var player = brain.player
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return
	if not is_instance_valid(player.player_inventory):
		return

	var merchant := _find_merchant()

	var health_count := _count_consumable("heal_amount")
	var mana_count := _count_consumable("regain_amount")
	var needs_health_pots: bool = health_count <= POTION_RESTOCK_THRESHOLD
	var needs_mana_pots: bool = mana_count <= POTION_RESTOCK_THRESHOLD \
		and is_instance_valid(player.mana_component) and player.mana_component.max_mana > 0

	var gold: int = player.player_inventory.monies_amount
	var can_afford_health := _can_afford_potion("heal_amount", gold)
	var can_afford_mana := _can_afford_potion("regain_amount", gold)

	# Out of potions and too broke to buy them: if the bot is carrying items
	# worth selling, liquidate them for the gold instead of going without.
	var broke_for_potions: bool = (needs_health_pots and not can_afford_health) \
		or (needs_mana_pots and not can_afford_mana)
	var liquidate: bool = broke_for_potions and not _collect_items_to_sell(true).is_empty()

	var bag_full := _inventory_is_full()
	_sell_unwanted_items(merchant, bag_full or liquidate)
	_buy_potions(merchant)

	# Route to a town merchant when the bag needs offloading, or when the bot
	# must sell to afford potions.
	needs_sell = merchant == null and (bag_full or liquidate)
	# Flag a restock run only if the bot can pay for it — it has the gold now,
	# or the liquidation sale will cover it. A broke bot with nothing to sell
	# skips the trip and keeps fighting to earn gold instead.
	var want_health: bool = needs_health_pots and (can_afford_health or liquidate)
	var want_mana: bool = needs_mana_pots and (can_afford_mana or liquidate)
	needs_restock = merchant == null and (want_health or want_mana)


func _find_merchant() -> MerchantInventory:
	var map_node = brain._get_map_node()
	if not is_instance_valid(map_node):
		return null
	for child in map_node.get_children():
		var merchant := child.get_node_or_null("MerchantInventory") as MerchantInventory
		if merchant:
			return merchant
	return null


## Items the bot should offload to a merchant: junk equipment (unusable, or no
## better than what it already has) and materials. With `force` the per-tab
## fullness gates are ignored — used when the bot must raise gold for potions.
func _collect_items_to_sell(force: bool) -> Array[ItemData]:
	var player = brain.player
	var items_to_sell: Array[ItemData] = []
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return items_to_sell

	var tab_counts := _count_slots_by_tab()
	var sell_equip: bool = force \
		or tab_counts.equip_used >= int(tab_counts.equip_total * SELL_FULLNESS_THRESHOLD)
	var sell_material: bool = force \
		or tab_counts.material_used >= int(tab_counts.material_total * SELL_FULLNESS_THRESHOLD)

	if not sell_equip and not sell_material:
		return items_to_sell

	var class_type: Constants.ClassType = Constants.ClassType.BEGINNER
	if is_instance_valid(player.class_component):
		class_type = player.class_component.current_class

	var equipped_scores: Dictionary = {}
	if is_instance_valid(player.equipment_component):
		for eq_slot in [player.equipment_component.weapon_slot_data, player.equipment_component.head_slot_data,
				player.equipment_component.chest_slot_data, player.equipment_component.legs_slot_data,
				player.equipment_component.feet_slot_data]:
			if eq_slot and eq_slot.item:
				var slot_key := _get_equip_slot_key(eq_slot.item)
				var score := BotEquipmentLogic.score_item(eq_slot.item, class_type)
				if not equipped_scores.has(slot_key) or score > equipped_scores[slot_key]:
					equipped_scores[slot_key] = score

	var best_inventory_scores: Dictionary = {}
	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not EquipmentData:
			continue
		var slot_key := _get_equip_slot_key(slot.item)
		var score := BotEquipmentLogic.score_item(slot.item, class_type)
		if not best_inventory_scores.has(slot_key) or score > best_inventory_scores[slot_key]:
			best_inventory_scores[slot_key] = score

	for slot in player.inventory_component.get_slots():
		if not slot.item:
			continue

		if slot.item is ConsumableData:
			continue

		if slot.item is EquipmentData:
			if not sell_equip:
				continue
			var item := slot.item as EquipmentData
			var item_score := BotEquipmentLogic.score_item(item, class_type)

			if item is WeaponData and not BotEquipmentLogic.can_equip_weapon(item as WeaponData, class_type):
				items_to_sell.append(item)
				continue

			var slot_key := _get_equip_slot_key(item)
			var threshold: float = equipped_scores.get(slot_key, -1.0)

			if item_score <= threshold:
				items_to_sell.append(item)
			elif item_score < best_inventory_scores.get(slot_key, 0.0):
				items_to_sell.append(item)
		elif sell_material:
			items_to_sell.append(slot.item)

	return items_to_sell


## Sells the bot's unwanted items to a merchant. `force` ignores the bag-
## fullness gates so a broke bot can liquidate gear/materials for potion money.
func _sell_unwanted_items(merchant: MerchantInventory, force: bool) -> void:
	# Selling requires a merchant — a bot never offloads gear out in the field.
	if not merchant:
		return
	var player = brain.player
	for item in _collect_items_to_sell(force):
		var sell_price: int = merchant.get_sell_price(item.item_id)
		player.player_inventory.monies_amount += sell_price
		brain._metrics.gold_from_sales += sell_price
		player.inventory_component.remove_item(item, "sold")


func _count_slots_by_tab() -> Dictionary:
	var player = brain.player
	var result := {
		"equip_used": 0, "equip_total": 0,
		"consumable_used": 0, "consumable_total": 0,
		"material_used": 0, "material_total": 0,
	}
	for slot in player.inventory_component.get_slots():
		match slot.allowed_item_type:
			Constants.ItemType.EQUIPMENT:
				result.equip_total += 1
				if slot.item:
					result.equip_used += 1
			Constants.ItemType.CONSUMABLE:
				result.consumable_total += 1
				if slot.item:
					result.consumable_used += 1
			Constants.ItemType.MATERIAL:
				result.material_total += 1
				if slot.item:
					result.material_used += 1
			Constants.ItemType.ANY:
				if slot.item:
					if slot.item is EquipmentData:
						result.equip_used += 1
					elif slot.item is ConsumableData:
						result.consumable_used += 1
					else:
						result.material_used += 1
				result.equip_total += 1
	return result


## True when the equipment or material tab has crossed the sell threshold —
## the same fullness gate _sell_unwanted_items uses to decide it's time to sell.
func _inventory_is_full() -> bool:
	var tab_counts := _count_slots_by_tab()
	var equip_full: bool = tab_counts.equip_used >= int(tab_counts.equip_total * SELL_FULLNESS_THRESHOLD)
	var material_full: bool = tab_counts.material_used >= int(tab_counts.material_total * SELL_FULLNESS_THRESHOLD)
	return equip_full or material_full


func _buy_potions(merchant: MerchantInventory) -> void:
	if not merchant:
		return
	# Buy only what this merchant actually stocks — never an arbitrary potion
	# pulled from the global item table.
	var stock: Array = merchant.get_stock_data(brain.bot_id)
	_buy_potion_type(merchant, stock, "heal_amount")
	_buy_potion_type(merchant, stock, "regain_amount")


## Buys, up to POTION_STOCK_TARGET, the best-sized potion of the given effect
## type from the merchant's own base stock: the largest heal/regain that does
## not exceed the bot's max stat (or, if every option exceeds it, the smallest).
## Caches the price so the affordability gate can use it on merchant-less maps.
func _buy_potion_type(merchant: MerchantInventory, stock: Array, effect_key: String) -> void:
	var player = brain.player
	var cap := _potion_effect_cap(effect_key)

	var pot_id := ""
	var pot_name := ""
	var pot_price := 0
	var best_score := 0.0
	for entry in stock:
		if entry.get("is_buyback", false):
			continue
		var item = ResourceManager.get_item_data(entry.get("item_id", ""))
		if item is not ConsumableData:
			continue
		var consumable := item as ConsumableData
		if not consumable.effect_properties.has(effect_key):
			continue
		# Score: a potion that fits (<= cap) ranks by heal size, biggest first;
		# one that overshoots ranks below every fitting potion, smallest first.
		var amount := float(consumable.effect_properties.get(effect_key, 0))
		var score := amount if amount <= cap else -amount
		if pot_id.is_empty() or score > best_score:
			pot_id = entry.get("item_id", "")
			pot_name = entry.get("name", "")
			pot_price = entry.get("price", 0)
			best_score = score
	if pot_id.is_empty():
		return  # this merchant does not sell that potion type

	_merchant_pot_cache[effect_key] = pot_price

	var count := _count_consumable(effect_key)
	while count < POTION_STOCK_TARGET:
		if pot_price <= 0 or player.player_inventory.monies_amount < pot_price:
			break
		if not merchant.can_player_buy_from_stock(brain.bot_id, pot_name):
			break
		if player.inventory_component.get_empty_slots().is_empty():
			break
		player.player_inventory.monies_amount -= pot_price
		player.inventory_component.server_add_item(pot_id)
		merchant.record_player_purchase(brain.bot_id, pot_name)
		count += 1


## The max stat a potion of this effect type refills — used to size potion
## choice so the bot doesn't buy heals that overshoot its pool.
func _potion_effect_cap(effect_key: String) -> int:
	var player = brain.player
	match effect_key:
		"heal_amount":
			return player.health_component.max_health if is_instance_valid(player.health_component) else 0
		"regain_amount":
			return player.mana_component.max_mana if is_instance_valid(player.mana_component) else 0
	return 0


## Whether the bot can afford a potion of the given effect type, using the price
## learned at a merchant. Before the bot has ever reached one, assume yes so it
## still makes the discovery trip — it spawns in town, so this gap is brief.
func _can_afford_potion(effect_key: String, gold: int) -> bool:
	if not _merchant_pot_cache.has(effect_key):
		return true
	return gold >= _merchant_pot_cache[effect_key]


func _count_consumable(effect_key: String) -> int:
	var player = brain.player
	var count := 0
	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not ConsumableData:
			continue
		var consumable := slot.item as ConsumableData
		if consumable.effect_properties.has(effect_key):
			count += slot.item.current_stack_amount
	return count


## True when the bag has a free slot a piece of loot could go into.
func has_inventory_space() -> bool:
	var player = brain.player
	for slot in player.inventory_component.get_slots():
		if slot.item == null and slot.allowed_item_type in [Constants.ItemType.ANY, Constants.ItemType.EQUIPMENT]:
			return true
	return false


func _get_equip_slot_key(item: ItemData) -> String:
	if item is WeaponData:
		return "weapon"
	if item is ArmorData:
		var armor := item as ArmorData
		match armor.armor_type:
			Constants.ArmorType.HEAD: return "head"
			Constants.ArmorType.CHEST: return "chest"
			Constants.ArmorType.LEGS: return "legs"
			Constants.ArmorType.FEET: return "feet"
	return "unknown"
