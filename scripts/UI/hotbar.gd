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

# PR 5: Sword combo indicator — three pips visible only while the active
# discipline is SWORD. Filled vs empty stylebox swap reflects the combo
# count. Resolved through the unique-name lookup against the WeaponSwapSection.
var combo_indicator: VBoxContainer = null
var combo_pips: Array[Panel] = []
var _combo_pip_style_empty: StyleBox = null
var _combo_pip_style_filled: StyleBox = null
var sword_combo_component: SwordComboComponent = null
## PR 5 polish: track the previous combo count so _on_combo_changed can tell
## a gain (animate the newly-filled pip with a pulse) apart from a consume
## (flash all pips quickly to telegraph the spend) apart from decay (just
## refresh, no animation — decay shouldn't startle the player).
var _last_combo_count: int = 0

var hotbar_slots: Array[Node] = []
var slot_count: int = 8
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

	# PR 5: combo indicator lives under the weapon-swap section. Cache pip
	# refs + the empty/filled styleboxes once so the per-frame refresh is
	# just a stylebox swap, not a tree lookup. Unique-name (%) lookup
	# resolves it cleanly regardless of whether the section is moved later.
	combo_indicator = get_node_or_null("%ComboIndicator") as VBoxContainer
	if is_instance_valid(combo_indicator):
		var pip0: Panel = combo_indicator.get_node_or_null("Pip0") as Panel
		var pip1: Panel = combo_indicator.get_node_or_null("Pip1") as Panel
		var pip2: Panel = combo_indicator.get_node_or_null("Pip2") as Panel
		if pip0 and pip1 and pip2:
			combo_pips = [pip0, pip1, pip2]
			# Both pips start with the empty stylebox per the tscn; the filled
			# stylebox is fetched off whichever pip we duplicate from. To keep
			# the two stylebox references independent (so toggling one pip
			# doesn't recolor every other), look up via the sub_resource on
			# disk. The scene serializes them in the file as
			# StyleBoxFlat_pip_empty / StyleBoxFlat_pip_filled — they're inline
			# subresources, so we grab the empty one off Pip0 and synthesize
			# the filled one from a duplicate, since exporting the sub_resource
			# from gdscript is awkward.
			_combo_pip_style_empty = pip0.get_theme_stylebox("panel")
			# Filled style: read off the scene resource. Because the empty and
			# filled styleboxes are declared inline in the tscn and we cannot
			# directly reach a non-applied subresource, build the filled style
			# in code so the visual rule is owned in one place.
			_combo_pip_style_filled = _build_filled_pip_style()

	# Get reference to player (adjust based on your scene structure)
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
	elif get_parent() is MultiplayerPlayerV2:
		player = get_parent() as MultiplayerPlayerV2

	# Get ability component
	if player:
		ability_component = player.ability_component
		equipment_component = player.equipment_component
		sword_combo_component = player.sword_combo_component

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

	# PR 5: subscribe to combo updates. The component fires combo_changed on
	# every build/spend/decay/reset on both server and client (via
	# sync_combo_to_client RPC), so a single connection works for both.
	if is_instance_valid(sword_combo_component):
		sword_combo_component.combo_changed.connect(_on_combo_changed)

	# Defer the first refresh by a frame — the equipment component's slots
	# may not be populated yet when _ready fires (loaded asynchronously).
	call_deferred("_refresh_weapon_section")
	call_deferred("_refresh_active_highlight")
	call_deferred("_refresh_combo_indicator")


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
	# PR 5: an equipment change (item swap, weapon dragged in/out) may flip
	# the active discipline — refresh combo visibility to match.
	_refresh_combo_indicator()


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
	# PR 5: Tab-swapping flips which discipline is active. Hide the pips when
	# swapping away from Sword; show them again when swapping back. The combo
	# count itself persists across the swap per the locked design.
	_refresh_combo_indicator()


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


# ============================================================================
# Combo indicator (PR 5 — Sword signature)
# ============================================================================

## Builds the filled-pip stylebox at runtime. Kept here (not in the tscn) so
## the empty/filled visual contract lives in one place — the tscn declares
## the empty style on each pip, and this builds the matching filled variant.
func _build_filled_pip_style() -> StyleBox:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(1.0, 0.65, 0.15, 1.0)
	style.border_color = Color(1.0, 0.85, 0.4, 1.0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


## Signal handler — runs on every combo_changed (build/spend/decay/reset).
## Delegates the visual fill to _refresh_combo_indicator and additionally
## triggers a one-shot animation distinguishing build vs spend so the
## player gets clear feedback on the mechanic.
func _on_combo_changed(new_count: int) -> void:
	var was: int = _last_combo_count
	_last_combo_count = new_count
	_refresh_combo_indicator()
	if not is_instance_valid(combo_indicator) or not combo_indicator.visible:
		return
	if new_count > was:
		# Build — pulse the newly-filled pip(s). If multiple landed in one
		# tick (defensive), pulse each. Usually just one.
		for i in range(was, min(new_count, combo_pips.size())):
			_pulse_pip(combo_pips[i])
	elif new_count < was and was > 0:
		# Spend / consume — quick all-pip flash so the player sees the cost
		# pay off. Skip if was==0 (decay/reset from empty, nothing to spend).
		_flash_all_pips()


## PR 5 polish: scale-tween a single pip 1.0 → 1.4 → 1.0 over ~0.2s. Reads
## as a "satisfying click" when combo lands. Tween auto-frees on completion.
func _pulse_pip(pip: Panel) -> void:
	if not is_instance_valid(pip):
		return
	pip.pivot_offset = pip.size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(pip, "scale", Vector2(1.4, 1.4), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(pip, "scale", Vector2(1.0, 1.0), 0.1).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


## PR 5 polish: quick brightness flash across all pips on combo consume.
## Modulates the ComboIndicator (not individual pips) so the label tints
## along with the pips, reinforcing "the whole stack just paid off."
func _flash_all_pips() -> void:
	if not is_instance_valid(combo_indicator):
		return
	var tween: Tween = create_tween()
	tween.tween_property(combo_indicator, "modulate", Color(1.6, 1.4, 0.8, 1.0), 0.06)
	tween.tween_property(combo_indicator, "modulate", Color.WHITE, 0.12)


## Visibility + per-pip fill update for the combo indicator. Hidden iff the
## active discipline is not SWORD (matches the locked design "only visible
## when wielding a sword"). When visible, paints the first N pips with the
## filled stylebox and the rest with the empty stylebox.
func _refresh_combo_indicator() -> void:
	if not is_instance_valid(combo_indicator):
		return

	# Hide for any non-Sword discipline. Falls open (hidden) when the player
	# root or its equipment component isn't ready yet, which is the safe
	# default — a stale visible indicator on a Bow loadout would be confusing.
	var show_indicator: bool = false
	if is_instance_valid(player) and player.has_method("get_active_discipline"):
		show_indicator = player.get_active_discipline() == Constants.ClassType.SWORD
	combo_indicator.visible = show_indicator
	if not show_indicator:
		return

	var count: int = 0
	if is_instance_valid(sword_combo_component):
		count = sword_combo_component.get_combo_count()

	for i in range(combo_pips.size()):
		var pip: Panel = combo_pips[i]
		if not is_instance_valid(pip):
			continue
		# Use a guard to avoid restyling pips that are already in the right
		# state — saves a theme_override write per frame on a non-change.
		var should_fill: bool = i < count
		var style_to_apply: StyleBox = _combo_pip_style_filled if should_fill else _combo_pip_style_empty
		if pip.get_theme_stylebox("panel") == style_to_apply:
			continue
		pip.add_theme_stylebox_override("panel", style_to_apply)
