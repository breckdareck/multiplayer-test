extends Control
class_name Hotbar

const HOTBARSLOT = preload("res://scenes/UI/hotbar_slot.tscn")
const ABILITYDATA = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")

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

	if ability_component:
		ability_component.cooldown_started.connect(_on_cooldown_started)

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

## Call this to activate an ability from a slot (e.g., when pressing keybind)
func activate_slot(slot_index: int):
	var slot = get_slot_at_index(slot_index)
	if slot and slot.assigned_ability:
		print("Activating ability: %s" % slot.assigned_ability.ability_name)
		# Integrate with your ability system here
		if player and player.ability_component.has_method("use_ability"):
			player.ability_component.use_ability(slot.assigned_ability.ability_id)

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
	var config = {}
	for slot in hotbar_slots:
		if slot.assigned_ability:
			config[slot.get_index()] = slot.assigned_ability.ability_id
		else:
			config[slot.get_index()] = ""
	return config

## Load hotbar configuration (from save data)
func load_hotbar_config(config: Dictionary):
	if config.size() != hotbar_slots.size():
		print("Warning: Hotbar config size mismatch")
		return
	
	for i in range(config.size()):
		if config.get(str(i)) != "":
			var ability_id = config.get(str(i))
			# Find the ability data from the ability window
			for ability in ability_component._ability_levels.keys():
				if ability == ability_id:
					var ability_data = ResourceManager.get_ability_data(ability)
					hotbar_slots[i].assign_ability(ability_data)
					break
