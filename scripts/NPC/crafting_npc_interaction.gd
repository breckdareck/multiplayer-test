## crafting_npc_interaction.gd
## A world NPC (blacksmith) the player right-clicks to open the crafting UI.
## Mirrors NPCInteraction (the merchant): a clickable overlay opens a window
## that is a child of this NPC's CanvasLayer, shared by the local client.
class_name CraftingNPCInteraction
extends Node2D

@export var crafting_window_scene: Panel
@export var crafting_station: CraftingStation
@export var prompt_label: Label = null
@export var clickable_overlay: TextureButton


func _ready() -> void:
	if not crafting_window_scene:
		push_error("CraftingNPCInteraction: crafting_window_scene missing!")
	if not crafting_station:
		push_error("CraftingNPCInteraction: crafting_station missing!")
	if not clickable_overlay:
		push_error("CraftingNPCInteraction: clickable_overlay (TextureButton) missing!")
		return

	clickable_overlay.gui_input.connect(_on_gui_input)
	clickable_overlay.mouse_entered.connect(_on_mouse_entered)
	clickable_overlay.mouse_exited.connect(_on_mouse_exited)

	if prompt_label:
		prompt_label.visible = false


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_crafting(multiplayer.get_unique_id())
			get_viewport().set_input_as_handled()


func _on_mouse_entered() -> void:
	if prompt_label:
		prompt_label.visible = true


func _on_mouse_exited() -> void:
	if prompt_label:
		prompt_label.visible = false


func _open_crafting(player_id: int) -> void:
	if crafting_window_scene and crafting_window_scene.visible:
		return  # Already open

	var player_inv: PlayerInventory = _get_local_player_inventory(player_id)
	if not player_inv:
		push_warning("CraftingNPCInteraction: Could not find local PlayerInventory for player %d" % player_id)
		return

	crafting_window_scene.open_crafting(player_inv, crafting_station)


func _get_local_player_inventory(player_id: int) -> PlayerInventory:
	var players = get_tree().get_nodes_in_group("Players")
	for p in players:
		if p.player_id == player_id:
			return p.player_inventory as PlayerInventory
	return null
