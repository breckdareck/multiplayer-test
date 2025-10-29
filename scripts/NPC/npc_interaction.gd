class_name NPCInteraction
extends Node2D

## ------------------------------------------------------------------
## CONFIGURATION
## ------------------------------------------------------------------

@export var shop_window_scene: Panel
@export var merchant_inventory: MerchantInventory
@export var merchant_id: String = ""
@export var prompt_label: Label = null

@export var clickable_overlay: TextureButton  # Drag the overlay here

## ------------------------------------------------------------------
## INTERNAL
## ------------------------------------------------------------------

var _shop_instance: Panel = null

## ------------------------------------------------------------------
## GODOT CALLBACKS
## ------------------------------------------------------------------

func _ready() -> void:
	# Validate
	if not shop_window_scene:
		push_error("NPCInteraction: shop_window_scene missing!")
	if not merchant_inventory:
		push_error("NPCInteraction: merchant_inventory missing!")
	if not clickable_overlay:
		push_error("NPCInteraction: clickable_overlay (TextureButton) missing!")
		return
	
	# Connect the button - use gui_input to detect right-click properly
	clickable_overlay.gui_input.connect(_on_gui_input)
	
	# Optional: show prompt on hover
	clickable_overlay.mouse_entered.connect(_on_mouse_entered)
	clickable_overlay.mouse_exited.connect(_on_mouse_exited)
	
	# Hide prompt by default
	if prompt_label:
		prompt_label.visible = false

func _on_gui_input(event: InputEvent) -> void:
	# Handle right-click properly
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_open_shop(multiplayer.get_unique_id())
			# Accept the event so it doesn't propagate
			get_viewport().set_input_as_handled()

func _on_mouse_entered() -> void:
	if prompt_label:
		prompt_label.visible = true

func _on_mouse_exited() -> void:
	if prompt_label:
		prompt_label.visible = false

## ------------------------------------------------------------------
## SHOP LOGIC
## ------------------------------------------------------------------

func _open_shop(player_id: int) -> void:
	if _shop_instance and _shop_instance.visible:
		return  # Already open
	
	var player_inv: PlayerInventory = _get_local_player_inventory(player_id)
	if not player_inv:
		push_warning("NPCInteraction: Could not find local PlayerInventory for player %d" % player_id)
		return
	
	_shop_instance = shop_window_scene
	
	_shop_instance.open_shop(
		player_inv,
		merchant_inventory,
		merchant_id if merchant_id else name
	)

func _get_local_player_inventory(player_id: int) -> PlayerInventory:
	var players = get_tree().get_nodes_in_group("Players")
	for p in players:
		# Make sure we're getting the local player (the one controlled by this client)
		if p.player_id == player_id:
			return p.player_inventory as PlayerInventory
	return null
