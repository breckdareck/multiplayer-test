extends Control
class_name Hotbar

const HotbarSlot = preload("res://scenes/UI/hotbar_slot.tscn")
const AbilityData = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")

@onready var slots_container: HBoxContainer = %SlotsContainer

var hotbar_slots: Array[Node] = []
var slot_count: int = 8
var player: MultiplayerPlayerV2
var ability_component: AbilityComponent

func _ready():
	# Get reference to player (adjust based on your scene structure)
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
	elif get_parent() is MultiplayerPlayerV2:
		player = get_parent() as MultiplayerPlayerV2
	
	# Get ability component
	if player:
		ability_component = player.ability_component
	
	if not ability_component:
		push_error("Hotbar: Could not find AbilityComponent")
	
	create_hotbar_slots()

func create_hotbar_slots():
	for i in range(slot_count):
		var slot = HotbarSlot.instantiate()
		slot.slot_index = i
		slot.ability_dropped.connect(_on_ability_dropped)
		slot.ability_removed.connect(_on_ability_removed)
		slots_container.add_child(slot)
		hotbar_slots.append(slot)

func _on_ability_dropped(slot_index: int, ability_data: AbilityData):
	print("Ability '%s' dropped into hotbar slot %d" % [ability_data.ability_name, slot_index])
	
	# Store the ability assignment on the player
	if player and player.has_method("set_hotbar_ability"):
		player.set_hotbar_ability(slot_index, ability_data)
	
	# Optional: Add visual/audio feedback
	# play_drop_sound()
	# show_feedback_animation(slot_index)

func _on_ability_removed(slot_index: int):
	print("Ability removed from hotbar slot %d" % slot_index)
	
	# Clear the ability from the player's hotbar
	if player and player.has_method("clear_hotbar_ability"):
		player.clear_hotbar_ability(slot_index)
	
	# Optional: Add visual/audio feedback
	# play_remove_sound()

func get_slot_at_index(index: int) -> Node:
	if index >= 0 and index < hotbar_slots.size():
		return hotbar_slots[index]
	return null

## Call this to activate an ability from a slot (e.g., when pressing keybind)
func activate_slot(slot_index: int):
	var slot = get_slot_at_index(slot_index)
	if slot and slot.assigned_ability:
		print("Activating ability: %s" % slot.assigned_ability.ability_name)
		# Integrate with your ability system here
		if player and player.ability_component.has_method("use_ability"):
			player.ability_component.use_ability(slot.assigned_ability.ability_id)

## Optional: Handle keybind inputs
func _input(event: InputEvent):
	if event is InputEventKey and event.pressed and not event.echo:
		# Check for number keys 1-8
		for i in range(slot_count):
			if event.keycode == KEY_1 + i:
				activate_slot(i)
				break

## Save hotbar configuration (useful for persistence)
func save_hotbar_config() -> Array:
	var config = []
	for slot in hotbar_slots:
		if slot.assigned_ability:
			config.append(slot.assigned_ability.ability_id)
		else:
			config.append("")
	return config

## Load hotbar configuration (from save data)
func load_hotbar_config(config: Array, ability_window: AbilityWindow):
	if config.size() != hotbar_slots.size():
		print("Warning: Hotbar config size mismatch")
		return
	
	for i in range(config.size()):
		if config[i] != "":
			var ability_id = config[i]
			# Find the ability data from the ability window
			for ability_data in ability_window.player_abilities.keys():
				if ability_data.ability_id == ability_id:
					hotbar_slots[i].assign_ability(ability_data)
					break
