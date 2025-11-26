class_name DroppedItem
extends CharacterBody2D

## The item data this represents
@export var item_data: ItemData
var stack_amount: int = 1
var _eligible_player_ids: Array[int] = [] # Players who are eligible to pick up this item
var is_public_pickup: bool = false

## Physics settings
@export var pop_force_y: float = -250.0 # Upward launch (negative is up)
@export var gravity: float = 900.0
@export var magnetize_delay: float = 1.2
@export var magnetize_speed: float = 280.0
@export var pickup_distance: float = 15.0
@export var ground_friction: float = 0.85
@export var min_settle_time: float = 0.5

@export var sprite: Sprite2D
@export var collision_shape: CollisionShape2D
@export var pickup_sfx: AudioStream

@onready var pickup_sound: AudioStreamPlayer2D = $PickupSound


## State
enum ItemState {POPPING, FALLING, SETTLED, COLLECTED}
var current_state: ItemState = ItemState.POPPING
var state_timer: float = 0.0
var ground_timer: float = 0.0
var is_pickup_ready: bool = false
var pulse_tween: Tween


func _ready() -> void:
	# Only run physics on server
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	velocity = Vector2(0, pop_force_y)
	
	print("DroppedItem spawned with velocity: ", velocity)
	
	# Setup collision to only interact with world (not players/enemies)
	collision_layer = 0 # Don't exist on any layer
	collision_mask = 1 # Only collide with world (layer 1)

func should_be_visible_to(peer_id: int) -> bool:
	"""Returns true if the peer should see this item (same map)"""
	# Find which map this item is on
	var item_map = null
	var parent = get_parent()
	while parent:
		if parent.is_in_group("map_base"):
			item_map = parent
			break
		parent = parent.get_parent()
	
	if not item_map:
		# Fallback: visible to all if we can't determine map
		return true
	
	# Find which map the peer's player is on
	var player_map = MapManager.get_player_map_node(peer_id)
	
	# Only visible if on same map
	return item_map == player_map


func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():
		return
	
	state_timer += delta
	
	match current_state:
		ItemState.POPPING:
			_handle_popping(delta)
		ItemState.SETTLED:
			_handle_settled()
		ItemState.COLLECTED:
			pass # Do nothing, waiting for cleanup


func _handle_popping(delta: float) -> void:
	# Apply gravity
	velocity.y += gravity * delta
	
	# Move and slide
	move_and_slide()
	
	# Apply friction when on ground
	if is_on_floor():
		velocity.x *= ground_friction
		
		# If we've been on ground for a bit and velocity is low, settle
		if state_timer > min_settle_time and abs(velocity.x) < 20 and abs(velocity.y) < 20:
			print("DroppedItem settling after ", state_timer, " seconds")
			current_state = ItemState.SETTLED
			is_pickup_ready = true
			state_timer = 0.0
			_start_pulse_tween()
	
	# After magnetize_delay, force transition to settled even if still moving
	if state_timer >= magnetize_delay:
		print("DroppedItem force settling after ", state_timer, " seconds")
		current_state = ItemState.SETTLED
		is_pickup_ready = true
		state_timer = 0.0
		_start_pulse_tween()


func _handle_settled() -> void:
	# Item is settled on the ground, check for pickup from any valid player
	# First check if we need to make the item public
	if not is_public_pickup:
		check_and_make_public_if_needed()
	
	if state_timer > 120 and not is_public_pickup:
		make_public()
	
	var nearby_player = _find_nearby_player()
	if nearby_player:
		# Check if the nearby player is trying to pick up
		if _is_player_trying_to_pickup(nearby_player):
			print("DroppedItem: Player %s picking up item" % nearby_player.username)
			_pickup_item(nearby_player)


func _find_nearby_player() -> MultiplayerPlayerV2:
	"""Find a nearby player who can pick up this item"""
	var all_players = get_tree().get_nodes_in_group("Players")
	
	for player_node in all_players:
		if not is_instance_valid(player_node):
			continue
		# Only consider players who are eligible to pick up
		if _can_player_pickup(player_node):
			var distance = global_position.distance_to(player_node.global_position)
			if distance <= pickup_distance:
				return player_node
	
	return null


func _can_player_pickup(player: MultiplayerPlayerV2) -> bool:
	"""Check if a specific player can pick up this item"""
	# If item is public, anyone can pick it up
	if is_public_pickup:
		return true
	
	# Check if player is in the target list
	if _eligible_player_ids.has(player.player_id):
		return true
	
	return false


func _is_player_trying_to_pickup(player: MultiplayerPlayerV2) -> bool:
	"""Check if a specific player is trying to pick up the item"""
	if not is_instance_valid(player):
		return false
	
	# Check if the player is pressing the pickup button
	if player.has_method("is_pressing_pickup"):
		return player.is_pressing_pickup()
	
	# Fallback: check for a specific input action
	# Use "Interact" or "Pickup" action - you may need to add this to your input map
	return Input.is_action_pressed("Interact") or Input.is_action_just_pressed("Interact")


func _pickup_item(picking_player: MultiplayerPlayerV2 = null) -> void:
	if current_state == ItemState.COLLECTED:
		return
	
	current_state = ItemState.COLLECTED
	
	# Use the picking player, which will be the one that triggered the pickup
	var player_to_give_item = picking_player
	
	# Add item to player's inventory
	if player_to_give_item and player_to_give_item.player_inventory:
		print("DroppedItem: Adding %dx %s to player %s inventory" % [stack_amount, item_data.name, player_to_give_item.username])
		if item_data.name == "Coin":
			player_to_give_item.player_inventory.monies_amount += stack_amount
		# For stackable items, add with the stack amount
		elif item_data.can_stack and stack_amount > 1:
			var new_item_instance = item_data.duplicate(true)
			new_item_instance.current_stack_amount = stack_amount
			player_to_give_item.player_inventory.add_item_instance(new_item_instance)
		else:
			player_to_give_item.player_inventory.add_item_instance(item_data.duplicate(true))

	# RPC to client to show log message
		show_pickup_log_rpc.rpc_id(player_to_give_item.player_id, item_data.name, stack_amount)
	
	# Play effects on all clients (including host)
	pickup_item_client.rpc()

@rpc("authority", "call_local", "reliable")
func pickup_item_client() -> void:
	# Visual effects for pickup
	pickup_sound.stream = pickup_sfx
	pickup_sound.play()
	
	# Animate pickup: popup -> magnetize to player -> fade out
	var pickup_tween = create_tween()
	
	# Phase 1: Quick popup (0.1s)
	pickup_tween.tween_property(self, "global_position", global_position + Vector2(0, -20), 0.1).set_ease(Tween.EASE_OUT)
	
	# Phase 3: Fade out slowly (0.3s)
	pickup_tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN).set_delay(0.1)
	
	pickup_sound.finished.connect(queue_free)
	

func setup(item: ItemData, amount: int, eligible_player_ids: Array[int]) -> void:
	item_data = item
	stack_amount = amount
	_eligible_player_ids = eligible_player_ids
	if _eligible_player_ids.is_empty():
		is_public_pickup = true
	
	print("DroppedItem setup: %s x%d for eligible players: %s" % [item_data.name if item_data else "NULL", amount, str(_eligible_player_ids)])
	
	# Set sprite to item's icon
	_update_sprite()
	
	# Start in popping state - item will settle on ground
	current_state = ItemState.POPPING
	is_pickup_ready = false


func _update_sprite() -> void:
	if item_data:
		var resource_item_data = ResourceManager.get_item_data(item_data.item_id)
		if resource_item_data and resource_item_data.icon:
			sprite.texture = resource_item_data.icon
		else:
			print("WARNING: DroppedItem has no icon for item_id: %s" % item_data.item_id)
	else:
		print("WARNING: DroppedItem has no item_data!")


func make_public() -> void:
	"""Make this item available for anyone to pick up"""
	is_public_pickup = true
	print("DroppedItem: Item is now public - anyone can pick it up")


func check_and_make_public_if_needed() -> void:
	"""Check if original target is still valid, if not make item public"""
	var has_valid_targets = false
	for player_id in _eligible_player_ids:
		var player_node = PlayerManager.get_player_node(player_id)
		if is_instance_valid(player_node):
			has_valid_targets = true
			break
	
	if not has_valid_targets:
		print("DroppedItem: No valid targets remaining, making item public")
		make_public()


func _start_pulse_tween() -> void:
	if pulse_tween and pulse_tween.is_valid():
		pulse_tween.kill()
		
	var base_scale = sprite.scale
	var pulse_scale = base_scale * 1.25 # Pulse 25% larger
	var duration = 1 # Time to pulse up and back down

	pulse_tween = create_tween()
	pulse_tween.set_loops()
	pulse_tween.set_trans(Tween.TRANS_SINE) # Gives a smooth "breathing" effect
	pulse_tween.set_ease(Tween.EASE_IN_OUT)

	# Pulse up
	pulse_tween.tween_property(sprite, "scale", pulse_scale, duration / 2.0)
	# Pulse back down
	pulse_tween.tween_property(sprite, "scale", base_scale, duration / 2.0)


@rpc("any_peer", "call_local", "reliable")
func show_pickup_log_rpc(item_name: String, amount: int):
	var text = "+%d %s" % [amount, item_name]
	LogManager.add_scrolling_log(text, Color.AQUAMARINE)


func sync_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not sprite:
		return
	
	print("DroppedItem: Sync State to peer: %d" % peer_id)
	if item_data:
		_set_state_rpc.rpc_id(peer_id, item_data.item_id)
	

@rpc("authority", "call_local", "reliable")
func _set_state_rpc(item_id: String) -> void:
	# Client side setup when receiving state
	if not item_data:
		item_data = ResourceManager.get_item_data(item_id)
	_update_sprite()
