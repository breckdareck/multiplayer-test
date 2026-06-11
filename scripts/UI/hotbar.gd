extends Control
class_name Hotbar

const HOTBARSLOT = preload("res://scenes/UI/hotbar_slot.tscn")
const ABILITYDATA = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")

@onready var slots_container: HBoxContainer = %SlotsContainer
@onready var background: PanelContainer = $Background
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

# Total duration of each ability's last-started cooldown, so slots can fade
# the overlay proportionally. Remaining time itself is read from the
# AbilityComponent (the single source of truth) by each slot per frame.
var _cooldown_totals: Dictionary = {}

# ESO-style bar-swap flip (see play_weapon_swap).
var _swap_tween: Tween = null
var _pending_swap_config = null  # Dictionary while a flip is mid-flight, else null

const SWAP_FLIP_HALF_DURATION := 0.09

func _ready():
	# Resolve weapon-swap section widgets via the unique-name lookup. `%`
	# resolution only handles direct unique-name children, so the loadout
	# slots are accessed off the parent section by fixed child names.
	weapon_swap_section = get_node_or_null("%WeaponSwapSection") as HBoxContainer
	if is_instance_valid(weapon_swap_section):
		primary_weapon_slot = weapon_swap_section.get_node_or_null("PrimaryWeaponSlot") as HotbarWeaponSlot
		secondary_weapon_slot = weapon_swap_section.get_node_or_null("SecondaryWeaponSlot") as HotbarWeaponSlot

	create_hotbar_slots()

	# One-time: the weapon-slot click affordance. These slots are PERSISTENT
	# (this UI layer outlives the body), so connect once here — not in
	# bind_player, or every rebind would double-connect. _on_weapon_slot_click
	# guards on `player`. (ADR 0009 Stage B.)
	if is_instance_valid(primary_weapon_slot):
		primary_weapon_slot.click_to_swap_requested.connect(_on_weapon_slot_click)
	if is_instance_valid(secondary_weapon_slot):
		secondary_weapon_slot.click_to_swap_requested.connect(_on_weapon_slot_click)


## Binds the hotbar to the local player body — called by LocalPlayerUI on every
## spawn / map change. Component-signal connections live here (the body's
## components are freed + recreated per map change, so their connections are
## auto-cleaned — unlike the one-time persistent-node wiring in _ready).
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		return

	ability_component = player.ability_component
	equipment_component = player.equipment_component
	if not ability_component:
		push_error("Hotbar: Could not find AbilityComponent")

	if ability_component:
		ability_component.cooldown_started.connect(_on_cooldown_started)

	if equipment_component:
		equipment_component.on_equipment_changed.connect(_refresh_weapon_section)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)
		equipment_component.swap_cooldown_started.connect(_on_swap_cooldown_started)
		equipment_component.swap_denied.connect(_on_swap_denied)

	# Defer the first refresh by a frame — the equipment component's slots
	# may not be populated yet when bind fires (loaded asynchronously).
	call_deferred("_refresh_weapon_section")
	call_deferred("_refresh_active_highlight")


## Drops the binding (teardown). Old-body component connections die with the
## freed body; this clears refs.
func unbind_player() -> void:
	player = null
	ability_component = null
	equipment_component = null


func _process(_delta: float) -> void:
	# Hold-channel release watch (tap-or-hold): the moment the casting key is
	# no longer held, send the release intent — the server ends the channel
	# early (after its minimum hold).
	if _channel_hold_action != "" and not Input.is_action_pressed(_channel_hold_action):
		_channel_hold_action = ""
		PlayerManager.player_input.rpc_id(1, "channel_release")


func create_hotbar_slots():
	for i in range(slot_count):
		var slot = HOTBARSLOT.instantiate()
		slot.name = "HotbarSlot" + str(i)
		slot.slot_index = i
		slots_container.add_child(slot)
		hotbar_slots.append(slot)


## A hotbar slot's binding was edited by the player (drop / right-click clear).
## Forward the new layout to the AbilityComponent, which captures it into the
## active weapon's binding set and pushes it to the authoritative server copy
## (ADR 0009 Stage B). No-op for programmatic loads (those use the slot setters).
func on_binding_edited() -> void:
	if is_instance_valid(ability_component) and ability_component.has_method("client_hotbar_edited"):
		ability_component.client_hotbar_edited()


func get_slot_at_index(index: int) -> Node:
	if index >= 0 and index < hotbar_slots.size():
		return hotbar_slots[index]
	return null

## Hold-channel tracking: when a CHANNEL_HOLD ability (Sky Volley / Stormcall)
## is cast from a hotbar key, remember the action so letting go of the key
## sends the release intent — tap-or-hold risk/reward. "" = nothing tracked.
## A click-cast never holds a key, so it plays as a tap (the minimum hold).
## Watched in _process above.
var _channel_hold_action: String = ""


## Call this to activate a slot (e.g., when pressing its keybind)
func activate_slot(slot_index: int):
	var slot = get_slot_at_index(slot_index)
	if not slot:
		return
	if slot.assigned_ability:
		if player and player.ability_component.has_method("use_ability"):
			player.ability_component.use_ability(slot.assigned_ability.ability_id)
			# Track channels (both kinds): releasing this slot's key ends a
			# HOLD zone early or fires a WINDUP cast at its charged fraction.
			var behavior = slot.assigned_ability.active_behavior
			if behavior != null and behavior.channel_mode != 0:
				_channel_hold_action = "hotbar_" + str(slot_index + 1)
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
	# Record the total so slots can fade the overlay; slots read the live
	# remaining time straight from the AbilityComponent each frame.
	_cooldown_totals[ability_id] = duration


func get_cooldown_total(ability_id: String) -> float:
	return _cooldown_totals.get(ability_id, 0.0)

## Optional: Handle keybind inputs
func _input(event: InputEvent):
	if InputManager.is_locked():
		return
	if not is_instance_valid(player):
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
	#
	# While a swap flip is mid-flight the slots still show the OUTGOING weapon's
	# layout — the incoming config hasn't been applied yet (it lands at the flip
	# midpoint). Return the pending config so a snapshot taken during the flip
	# (rapid re-swap, slot edit) reflects what the bar is BECOMING, not a stale
	# frame of what it was.
	if _pending_swap_config != null:
		return _pending_swap_config.duplicate()

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
	# A direct load (save load / map change) supersedes any in-flight swap
	# flip — drop the pending config and snap the bar back to full width so
	# the flip's midpoint callback can't stomp this load. (When this call IS
	# the midpoint callback, _pending_swap_config was already nulled.)
	if _pending_swap_config != null:
		_pending_swap_config = null
		if _swap_tween and _swap_tween.is_valid():
			_swap_tween.kill()
		if is_instance_valid(background):
			background.scale.x = 1.0

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


## ESO-style bar-swap: flip the whole bar horizontally — squash scale.x to 0,
## apply the incoming weapon's bindings while edge-on (invisible), then expand
## back out showing the new bar. Called by AbilityComponent's
## _on_active_weapon_changed instead of a bare load_hotbar_config.
func play_weapon_swap(config: Dictionary) -> void:
	# A flip already mid-flight (rapid re-swap): finish its load instantly so
	# configs apply in order, then start the new flip from wherever scale is.
	if _swap_tween and _swap_tween.is_valid():
		_swap_tween.kill()
	_apply_pending_swap_config()

	_pending_swap_config = config.duplicate()
	if not is_instance_valid(background):
		_apply_pending_swap_config()
		return

	background.pivot_offset = background.size / 2.0
	_swap_tween = create_tween()
	_swap_tween.tween_property(background, "scale:x", 0.0, SWAP_FLIP_HALF_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_swap_tween.tween_callback(_apply_pending_swap_config)
	_swap_tween.tween_property(background, "scale:x", 1.0, SWAP_FLIP_HALF_DURATION) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _apply_pending_swap_config() -> void:
	if _pending_swap_config == null:
		return
	var cfg: Dictionary = _pending_swap_config
	_pending_swap_config = null
	load_hotbar_config(cfg)
