class_name EquipmentComponent
extends Node

signal on_equipment_changed
## Emitted whenever the active weapon flips between primary and secondary
## (or whenever load restores it). Combat / sprite / UI listeners react to
## this to rebuild damage stats and visuals.
signal active_weapon_changed(active_weapon: String, active_item: ItemData)
## Emitted when the swap-on-cooldown gate starts. The hotbar paints a radial
## cooldown overlay across both weapon icons for this duration.
signal swap_cooldown_started(duration: float)
## Emitted when the swap is denied (e.g. empty secondary). The hotbar plays
## a "denied" UI ping and flashes the empty slot. No state change.
signal swap_denied(reason: String)

## Active-weapon enum (string-typed for save-file legibility).
const ACTIVE_PRIMARY: String = "primary"
const ACTIVE_SECONDARY: String = "secondary"

## Swap cooldown in seconds. Tunable.
const SWAP_COOLDOWN: float = 1.5

@export var head_slot: EquipmentSlot
@export var chest_slot: EquipmentSlot
@export var legs_slot: EquipmentSlot
@export var feet_slot: EquipmentSlot
@export var weapon_slot: EquipmentSlot
@export var secondary_weapon_slot: EquipmentSlot

var equipment: Dictionary = {}
# The component-owned data model: equipment key -> SlotData. This is the real
# storage; the EquipmentSlot UI nodes are views bound to these.
var slots_data: Dictionary = {}
var _changed_in_frame: bool = false
var _silent_mode: bool = false

## Tracks which weapon slot is currently active. PR 3 introduces a two-weapon
## loadout (primary + secondary); Tab cycles, the hotbar refreshes, the sprite
## swaps. `active_weapon` only ever holds ACTIVE_PRIMARY or ACTIVE_SECONDARY.
var active_weapon: String = ACTIVE_PRIMARY

## Server-side remaining swap cooldown (seconds). Clients do not read this —
## they paint their UI overlay from the swap_cooldown_started signal duration.
var _swap_cooldown_remaining: float = 0.0

func _ready():
	# Configure the slots with their specific types and set their container to this component.
	var armor_slots = {
		Constants.ArmorType.HEAD: head_slot,
		Constants.ArmorType.CHEST: chest_slot,
		Constants.ArmorType.LEGS: legs_slot,
		Constants.ArmorType.FEET: feet_slot,
	}

	for armor_type in armor_slots:
		var slot = armor_slots[armor_type]
		# The component owns a SlotData for every equipment key, even when the
		# matching UI slot is absent (e.g. a headless bot scene).
		var data := SlotData.new()
		data.container_kind = SlotData.CONTAINER_EQUIPMENT
		data.key = armor_type
		data.allowed_item_type = Constants.ItemType.EQUIPMENT
		data.allowed_equipment_type = Constants.EquipmentType.ARMOR
		data.allowed_armor_type = armor_type
		slots_data[armor_type] = data

		if is_instance_valid(slot):
			equipment[armor_type] = slot
			slot.set_inventory(self)
			slot.allowed_item_type = Constants.ItemType.EQUIPMENT
			slot.allowed_equipment_type = Constants.EquipmentType.ARMOR
			slot.allowed_armor_type = armor_type
			slot.bind_slot_data(data)

	var weapon_data := SlotData.new()
	weapon_data.container_kind = SlotData.CONTAINER_EQUIPMENT
	weapon_data.key = "WEAPON"
	weapon_data.allowed_item_type = Constants.ItemType.EQUIPMENT
	weapon_data.allowed_equipment_type = Constants.EquipmentType.WEAPON
	slots_data["WEAPON"] = weapon_data

	if weapon_slot:
		equipment["WEAPON"] = weapon_slot
		weapon_slot.set_inventory(self)
		weapon_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		weapon_slot.allowed_equipment_type = Constants.EquipmentType.WEAPON
		weapon_slot.bind_slot_data(weapon_data)

	# PR 3: secondary weapon slot. Same allow-rules as the primary weapon slot.
	# `slots_data["SECONDARY_WEAPON"]` is always present even when the UI slot
	# is missing (bot has no UI, and the equipment-window scene may not yet
	# expose the slot on a remote client mid-transition).
	var secondary_weapon_data := SlotData.new()
	secondary_weapon_data.container_kind = SlotData.CONTAINER_EQUIPMENT
	secondary_weapon_data.key = "SECONDARY_WEAPON"
	secondary_weapon_data.allowed_item_type = Constants.ItemType.EQUIPMENT
	secondary_weapon_data.allowed_equipment_type = Constants.EquipmentType.WEAPON
	slots_data["SECONDARY_WEAPON"] = secondary_weapon_data

	if secondary_weapon_slot:
		equipment["SECONDARY_WEAPON"] = secondary_weapon_slot
		secondary_weapon_slot.set_inventory(self)
		secondary_weapon_slot.allowed_item_type = Constants.ItemType.EQUIPMENT
		secondary_weapon_slot.allowed_equipment_type = Constants.EquipmentType.WEAPON
		secondary_weapon_slot.bind_slot_data(secondary_weapon_data)

	# When equipment changes on the server, persist the player's data
	# Logic moved to multiplayer_controller_v2.gd to handle both client and server


func _process(delta: float) -> void:
	# Server-only swap-cooldown tick. The client never reads this value — it
	# paints its UI overlay from the swap_cooldown_started signal duration.
	if not multiplayer.is_server():
		return
	if _swap_cooldown_remaining > 0.0:
		_swap_cooldown_remaining = maxf(0.0, _swap_cooldown_remaining - delta)


func set_silent_mode(enabled: bool) -> void:
	_silent_mode = enabled


# This function is called by the Slot's item setter whenever an item is changed.
# `_slot` is untyped — it may be a Slot view or a SlotData, both are ignored here.
func _update_item_tracking(_slot, _old_item: ItemData, _new_item: ItemData):
	if _changed_in_frame:
		return
	_changed_in_frame = true
	call_deferred("_emit_equipment_changed_deferred")


func _emit_equipment_changed_deferred():
	if _silent_mode:
		_changed_in_frame = false
		return

	on_equipment_changed.emit()
	_changed_in_frame = false

	# NOTE: the sword-combo "reset when neither slot holds a sword" rule used to
	# live here. It now rides the unified WeaponSignature notification — the
	# player root's `_on_equipment_changed_refresh_sprite` (connected to
	# on_equipment_changed, server-only) calls `_notify_signatures_weapon_state_changed`,
	# which routes to `SwordComboComponent.on_weapon_state_changed`. See
	# scripts/Components/weapon_signature.gd.


## Flags an equipment change so on_equipment_changed fires (deferred). Used by
## code that mutates a SlotData directly instead of through a Slot view setter.
func mark_changed() -> void:
	_update_item_tracking(null, null, null)


func get_slots() -> Array[EquipmentSlot]:
	var slots_array: Array[EquipmentSlot] = []
	if head_slot: slots_array.append(head_slot)
	if chest_slot: slots_array.append(chest_slot)
	if legs_slot: slots_array.append(legs_slot)
	if feet_slot: slots_array.append(feet_slot)
	if weapon_slot: slots_array.append(weapon_slot)
	if secondary_weapon_slot: slots_array.append(secondary_weapon_slot)
	return slots_array


# --- SlotData model accessors (UI-independent; safe on a headless bot) ---

func get_slot_data(key) -> SlotData:
	return slots_data.get(key)


func get_all_slot_data() -> Array:
	return slots_data.values()


## Equipment slots whose `bonus_stats` should fold into StatsComponent. The
## INACTIVE weapon's stats are deliberately excluded — only the currently
## wielded weapon contributes. Other equipment is always counted. Used by
## stats.gd in place of get_all_slot_data() so a stashed secondary's bonuses
## don't double up.
##
## NOTE: slots_data has mixed key types — String for the two weapon slots
## ("WEAPON" / "SECONDARY_WEAPON") and Constants.ArmorType ints for the four
## armor slots. The weapon-active checks must guard with `is String` so the
## == comparison doesn't error against int keys.
func get_stat_contributing_slot_data() -> Array:
	var out: Array = []
	for key in slots_data.keys():
		var sd: SlotData = slots_data[key]
		if sd == null:
			continue
		# Hide the inactive weapon slot from the stats pipeline.
		if key is String:
			if key == "WEAPON" and active_weapon != ACTIVE_PRIMARY:
				continue
			if key == "SECONDARY_WEAPON" and active_weapon != ACTIVE_SECONDARY:
				continue
		out.append(sd)
	return out


var weapon_slot_data: SlotData:
	get: return slots_data.get("WEAPON")
var secondary_weapon_slot_data: SlotData:
	get: return slots_data.get("SECONDARY_WEAPON")
var head_slot_data: SlotData:
	get: return slots_data.get(Constants.ArmorType.HEAD)
var chest_slot_data: SlotData:
	get: return slots_data.get(Constants.ArmorType.CHEST)
var legs_slot_data: SlotData:
	get: return slots_data.get(Constants.ArmorType.LEGS)
var feet_slot_data: SlotData:
	get: return slots_data.get(Constants.ArmorType.FEET)


## Returns the WeaponData currently in the ACTIVE weapon slot, or null when
## the active slot is empty / the item is not a weapon. Combat, sprite swap,
## and mastery-XP attribution all read through this.
var active_weapon_data: WeaponData:
	get:
		var sd: SlotData = _active_weapon_slot_data()
		if sd == null or sd.item == null:
			return null
		return sd.item as WeaponData


func _active_weapon_slot_data() -> SlotData:
	if active_weapon == ACTIVE_SECONDARY:
		return slots_data.get("SECONDARY_WEAPON")
	return slots_data.get("WEAPON")


## Refreshes the UI view bound to an equipment key, if one exists. A no-op on
## a headless bot scene (no equipment window).
func refresh_view(key) -> void:
	var view = equipment.get(key)
	if is_instance_valid(view):
		view.update_display()


# ===========================================================================
# Weapon Swap (PR 3)
# ===========================================================================

## Server-only attempt to flip the active weapon. Validates state, sets the
## cooldown, fires signals, and emits the auth result. Returns true on a
## successful swap, false on denial. On denial pings the initiator's UI.
func try_perform_swap_server(initiator_id: int) -> bool:
	if not multiplayer.is_server():
		return false

	if _swap_cooldown_remaining > 0.0:
		# Cooldown — silently deny. The UI overlay already shows the cooldown,
		# so don't spam a denied ping here.
		swap_denied.emit("cooldown")
		return false

	var secondary_sd: SlotData = slots_data.get("SECONDARY_WEAPON")
	if secondary_sd == null or secondary_sd.item == null:
		# Empty secondary — Tab is a no-op, but ping the initiator so they get
		# a "denied" feedback (sound + flash). No state change.
		_broadcast_swap_denied(initiator_id, "empty_secondary")
		return false

	# Apply the flip locally (server side) and broadcast the authoritative
	# state. Purely synchronous — no awaits, no sync-emit-await-hang risk.
	_apply_swap_state()
	_swap_cooldown_remaining = SWAP_COOLDOWN

	# Tell every peer about the swap and its cooldown so their UI matches the
	# server's truth. `call_local` is NOT set here because the server has
	# already applied the state above; we don't want to double-flip on the
	# host. Use call_remote and let clients re-run the apply locally.
	swap_applied_rpc.rpc(active_weapon, SWAP_COOLDOWN)

	return true


## Apply the swap locally. Called from the server's intent path and from the
## client-side RPC handler.
func _apply_swap_state() -> void:
	if active_weapon == ACTIVE_PRIMARY:
		active_weapon = ACTIVE_SECONDARY
	else:
		active_weapon = ACTIVE_PRIMARY
	active_weapon_changed.emit(active_weapon, active_weapon_data)
	swap_cooldown_started.emit(SWAP_COOLDOWN)
	# An active-weapon flip is functionally an equipment change — let stats /
	# combat re-derive their per-weapon values via the standard path.
	mark_changed()


func _broadcast_swap_denied(initiator_id: int, reason: String) -> void:
	# Server-side local emit + targeted client ping. Bots have no client; skip.
	swap_denied.emit(reason)
	if initiator_id > 0 and initiator_id != 1:
		swap_denied_rpc.rpc_id(initiator_id, reason)


## Server -> all peers. Authoritative result of a successful swap, including
## the new cooldown so the radial overlay can paint. `call_remote` so the
## server (which already ran _apply_swap_state) does not double-apply.
@rpc("authority", "call_remote", "reliable")
func swap_applied_rpc(new_active_weapon: String, cooldown_duration: float) -> void:
	if multiplayer.is_server():
		return
	# Set the active flag from the server's truth and emit locally so listeners
	# (sprite, hotbar, stats) refresh.
	active_weapon = new_active_weapon
	active_weapon_changed.emit(active_weapon, active_weapon_data)
	swap_cooldown_started.emit(cooldown_duration)
	mark_changed()


## Server -> initiator. Ping the player's UI on a denied swap. No state change.
@rpc("authority", "call_remote", "reliable")
func swap_denied_rpc(reason: String) -> void:
	if multiplayer.is_server():
		return
	swap_denied.emit(reason)


## Direct setter for save/load. Skips the cooldown and any RPC broadcast —
## the rest of the load pipeline syncs the client. Used by the player root's
## `_load_data` to restore the persisted `active_weapon`.
func set_active_weapon_silent(new_active_weapon: String) -> void:
	if new_active_weapon != ACTIVE_PRIMARY and new_active_weapon != ACTIVE_SECONDARY:
		return
	active_weapon = new_active_weapon
