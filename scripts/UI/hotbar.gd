extends Control
class_name Hotbar

const HOTBARSLOT = preload("res://scenes/UI/hotbar_slot.tscn")
const ABILITYDATA = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")

@onready var slots_container: HBoxContainer = %SlotsContainer
# The two weapon-loadout widgets live under the WeaponSwapSection. Resolved
# in _ready() (after @onready binds slots_container) so we can use a single
# get_node call against the swap section parent.
var weapon_swap_section: HBoxContainer = null
var primary_weapon_slot: HotbarWeaponSlot = null
var secondary_weapon_slot: HotbarWeaponSlot = null

var hotbar_slots: Array[Node] = []
var slot_count: int = 5
var player: MultiplayerPlayerV2
var ability_component: AbilityComponent
var equipment_component: EquipmentComponent
var _flash_remaining: float = 0.0

const HOTBAR_FLASH_DURATION := 0.1
const HOTBAR_FLASH_COLOR := Color(1.3, 1.3, 0.7, 1.0)

func _ready():
	# Resolve weapon-swap section widgets via the unique-name lookup. `%`
	# resolution only handles direct unique-name children, so the loadout
	# slots are accessed off the parent section by fixed child names.
	weapon_swap_section = get_node_or_null("%WeaponSwapSection") as HBoxContainer
	if is_instance_valid(weapon_swap_section):
		primary_weapon_slot = weapon_swap_section.get_node_or_null("PrimaryWeaponSlot") as HotbarWeaponSlot
		secondary_weapon_slot = weapon_swap_section.get_node_or_null("SecondaryWeaponSlot") as HotbarWeaponSlot

	# Get reference to player (adjust based on your scene structure)
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
	elif get_parent() is MultiplayerPlayerV2:
		player = get_parent() as MultiplayerPlayerV2

	# Get ability component
	if player:
		ability_component = player.ability_component
		equipment_component = player.equipment_component

	if not ability_component:
		push_error("Hotbar: Could not find AbilityComponent")

	create_hotbar_slots()

	if ability_component:
		ability_component.cooldown_started.connect(_on_cooldown_started)

	# PR 3: wire the weapon-swap section. The widgets exist on every client
	# that has the hotbar scene; bots free their UI subtree so this never runs
	# for them.
	if is_instance_valid(primary_weapon_slot):
		primary_weapon_slot.click_to_swap_requested.connect(_on_weapon_slot_click)
	if is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.click_to_swap_requested.connect(_on_weapon_slot_click)

	if equipment_component:
		equipment_component.on_equipment_changed.connect(_refresh_weapon_section)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)
		equipment_component.swap_cooldown_started.connect(_on_swap_cooldown_started)
		equipment_component.swap_denied.connect(_on_swap_denied)

	# Defer the first refresh by a frame — the equipment component's slots
	# may not be populated yet when _ready fires (loaded asynchronously).
	call_deferred("_refresh_weapon_section")
	call_deferred("_refresh_active_highlight")


func _process(delta: float) -> void:
	if _flash_remaining > 0.0:
		_flash_remaining = maxf(0.0, _flash_remaining - delta)
		if _flash_remaining <= 0.0:
			modulate = Color.WHITE


func create_hotbar_slots():
	for i in range(slot_count):
		var slot = HOTBARSLOT.instantiate()
		slot.name = "HotbarSlot" + str(i)
		slot.slot_index = i
		slots_container.add_child(slot)
		hotbar_slots.append(slot)


func get_slot_at_index(index: int) -> Node:
	if index >= 0 and index < hotbar_slots.size():
		return hotbar_slots[index]
	return null

## Call this to activate a slot (e.g., when pressing its keybind)
func activate_slot(slot_index: int):
	var slot = get_slot_at_index(slot_index)
	if not slot:
		return
	if slot.assigned_ability:
		if player and player.ability_component.has_method("use_ability"):
			player.ability_component.use_ability(slot.assigned_ability.ability_id)
	elif slot.assigned_consumable:
		_use_consumable(slot.assigned_consumable)

## Finds an inventory slot holding this consumable and asks the server to use it.
func _use_consumable(consumable: ConsumableData) -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return
	var inv := player.inventory_component
	for i in range(inv.slots.size()):
		var inv_slot = inv.slots[i]
		if inv_slot.item != null and inv_slot.item.item_id == consumable.item_id:
			inv.request_use_item.rpc_id(1, i)
			return

func _on_cooldown_started(ability_id: String, duration: float) -> void:
	for slot in hotbar_slots:
		slot.start_cooldown(ability_id, duration)

## Optional: Handle keybind inputs
func _input(event: InputEvent):
	if InputManager.is_locked():
		return
	if multiplayer.get_unique_id() == player.player_id:
		for i in range(slot_count):
			var action_name = "hotbar_" + str(i + 1)
			if event.is_action_pressed(action_name) and not event.is_echo():
				activate_slot(i)
				break

## Save hotbar configuration (useful for persistence)
func save_hotbar_config() -> Dictionary:
	# Keys are stringified to match load_hotbar_config (which uses str(i)) so the
	# in-memory carry-over on map changes lines up — backend JSON would coerce
	# them anyway, masking the mismatch on initial join.
	var config = {}
	for slot in hotbar_slots:
		var key := str(slot.get_index())
		if slot.assigned_ability:
			config[key] = slot.assigned_ability.ability_id
		elif slot.assigned_consumable:
			config[key] = slot.assigned_consumable.item_id
		else:
			config[key] = ""
	return config

## Load hotbar configuration (from save data)
func load_hotbar_config(config: Dictionary):
	# PR 3: a per-weapon binding may legitimately be empty (e.g. the secondary
	# loadout right after equipping a new weapon for the first time). Treat
	# an empty config as "clear all slots" rather than bailing — otherwise
	# the previous weapon's bindings would leak through after a swap.
	if config.is_empty():
		for slot in hotbar_slots:
			slot._clear_slot()
		return

	if config.size() != hotbar_slots.size():
		# Size mismatch — clear and apply what's present.
		for slot in hotbar_slots:
			slot._clear_slot()

	for i in range(hotbar_slots.size()):
		var entry_id: String = config.get(str(i), "")
		if entry_id == "":
			hotbar_slots[i]._clear_slot()
			continue
		# Hotbar entries store either a learned ability's id or a consumable's
		# item_id — ability and item ids occupy distinct id spaces.
		# Apply via the slot's internal setters rather than the public assign_*
		# helpers: those helpers broadcast a node-addressed RPC, and during
		# server-side load on a map change the slot's path hasn't resolved on
		# remote peers yet (per-map SubViewport hierarchy), so the broadcast
		# logs "Node not found". The host's UI is the same node as the server
		# instance, so the local setter is all that's needed here.
		if ability_component and ability_component._ability_levels.has(entry_id):
			hotbar_slots[i]._set_ability(ResourceManager.get_ability_data(entry_id))
		else:
			var item_data = ResourceManager.get_item_data(entry_id)
			if item_data is ConsumableData:
				hotbar_slots[i]._set_consumable(item_data)


# ============================================================================
# Weapon-swap section (PR 3)
# ============================================================================

func _refresh_weapon_section() -> void:
	if not is_instance_valid(equipment_component):
		return

	var primary_sd := equipment_component.weapon_slot_data
	var secondary_sd := equipment_component.secondary_weapon_slot_data

	if is_instance_valid(primary_weapon_slot):
		primary_weapon_slot.set_weapon_item(primary_sd.item if primary_sd else null)
	if is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.set_weapon_item(secondary_sd.item if secondary_sd else null)

	_refresh_active_highlight()


func _refresh_active_highlight() -> void:
	if not is_instance_valid(equipment_component):
		return
	var primary_active: bool = equipment_component.active_weapon == EquipmentComponent.ACTIVE_PRIMARY
	if is_instance_valid(primary_weapon_slot):
		primary_weapon_slot.set_active(primary_active)
	if is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.set_active(not primary_active)


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	_refresh_active_highlight()


func _on_swap_cooldown_started(duration: float) -> void:
	if is_instance_valid(primary_weapon_slot):
		primary_weapon_slot.start_swap_cooldown(duration)
	if is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.start_swap_cooldown(duration)


func _on_swap_denied(reason: String) -> void:
	if reason == "empty_secondary" and is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.flash_denied()
	# Other denial reasons (cooldown etc.) currently no-op visually — the
	# existing radial overlay already communicates the cooldown.


## Click-to-swap entry from the inactive weapon icon. Routes the same RPC
## the Tab keybind uses.
func _on_weapon_slot_click(_slot_kind: String) -> void:
	if not is_instance_valid(player):
		return
	# Local player only — clicks on a remote player's hotbar slot widgets
	# don't happen in practice (the hotbar UI is hidden for remote players),
	# but guard anyway.
	if multiplayer.get_unique_id() != player.player_id:
		return
	PlayerManager.player_input.rpc_id(1, "weapon_swap")


## Brief tint flash drawing the eye to the changed bindings on swap. Called
## by AbilityComponent._on_active_weapon_changed when the live bindings have
## been swapped in.
func flash_swap_indicator() -> void:
	_flash_remaining = HOTBAR_FLASH_DURATION
	modulate = HOTBAR_FLASH_COLOR
