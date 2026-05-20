class_name SlotData
extends RefCounted

## Pure data model for a single inventory or equipment slot.
##
## This holds the slot's item and its acceptance rules with NO ties to the UI
## or the scene tree. InventoryComponent / EquipmentComponent own arrays/dicts
## of SlotData; the `Slot` UI node is a view that binds to one of these.
##
## Server, headless builds, and bots can therefore carry a complete inventory
## with zero UI nodes instantiated.

## Which container owns this slot.
const CONTAINER_INVENTORY := 0
const CONTAINER_EQUIPMENT := 1

## The item currently in this slot, or null when empty.
var item: ItemData = null

## Owning container kind (CONTAINER_INVENTORY / CONTAINER_EQUIPMENT).
var container_kind: int = CONTAINER_INVENTORY

## Address key within the owning container: an int index for inventory slots,
## or the equipment key (ArmorType int / "WEAPON") for equipment slots.
var key = 0

## Inventory slot index (== key for inventory slots; -1 for equipment slots).
## Set by the component on creation.
var index: int = -1

## Acceptance rules. `allowed_item_type` defaults to ANY (no restriction).
## The equipment-type fields default to -1, a sentinel meaning "no restriction"
## (matches the previous EquipmentSlot exports).
var allowed_item_type: Constants.ItemType = Constants.ItemType.ANY
var allowed_equipment_type: Constants.EquipmentType = -1
var allowed_armor_type: Constants.ArmorType = -1
var allowed_weapon_type: Constants.WeaponType = -1


## Whether this slot may hold the given item. A null item (clearing the slot)
## is always accepted.
func can_accept_item(item_to_check: ItemData) -> bool:
	if not item_to_check:
		return true

	# Item-type gate — also guarantees the equipment-type checks below only
	# run for items that actually carry those properties.
	if allowed_item_type != Constants.ItemType.ANY and item_to_check.item_type != allowed_item_type:
		return false

	if allowed_equipment_type != -1 and item_to_check.equipment_type != allowed_equipment_type:
		return false

	if allowed_armor_type != -1 and item_to_check.armor_type != allowed_armor_type:
		return false

	if allowed_weapon_type != -1 and item_to_check.weapon_type != allowed_weapon_type:
		return false

	return true


## Whether `item_to_add` can stack onto the item already in this slot.
func can_add_to_stack(item_to_add: ItemData) -> bool:
	if item == null or item_to_add == null:
		return false
	return item.name == item_to_add.name \
		and item.can_stack \
		and item.current_stack_amount < item.max_stack_amount


## Adds up to `amount` to this slot's stack. Returns how many were actually added.
func add_to_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0
	var space_left: int = item.max_stack_amount - item.current_stack_amount
	var amount_to_add: int = min(amount, space_left)
	item.current_stack_amount += amount_to_add
	return amount_to_add


## Removes up to `amount` from this slot's stack. Returns how many were removed.
func remove_from_stack(amount: int = 1) -> int:
	if not item or not item.can_stack:
		return 0
	var amount_to_remove: int = min(amount, item.current_stack_amount)
	item.current_stack_amount -= amount_to_remove
	return amount_to_remove


func is_stack_full() -> bool:
	return item != null and item.can_stack and item.current_stack_amount >= item.max_stack_amount


func get_remaining_space() -> int:
	if not item or not item.can_stack:
		return 0
	return item.max_stack_amount - item.current_stack_amount
