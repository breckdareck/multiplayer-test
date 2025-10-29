class_name DroppedItem
extends CharacterBody2D

## The item data this represents
var item_data: ItemData
var stack_amount: int = 1
var target_player: MultiplayerPlayerV2
var target_players: Array[MultiplayerPlayerV2] = []
var is_public_pickup: bool = false

## Physics settings
@export var pop_force_y: float = -250.0  # Upward launch (negative is up)
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
enum ItemState { POPPING, FALLING, SETTLED, COLLECTED }
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
	collision_layer = 0  # Don't exist on any layer
	collision_mask = 1   # Only collide with world (layer 1)


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
			pass  # Do nothing, waiting for cleanup


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
	if not is_pickup_ready:
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
	
	for player in all_players:
		if not is_instance_valid(player):
			continue
		
		var distance = global_position.distance_to(player.global_position)
		if distance <= pickup_distance:
			# Check if this player is allowed to pick up the item
			if _can_player_pickup(player):
				return player
	
	return null


func _can_player_pickup(player: MultiplayerPlayerV2) -> bool:
	"""Check if a specific player can pick up this item"""
	# If item is public, anyone can pick it up
	if is_public_pickup:
		return true
	
	# Check if player is in the target list
	if player in target_players:
		return true
	
	# Check if player is the original target
	if player == target_player:
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
	
	# Use the picking player, or fall back to target player
	var player_to_give_item = picking_player if picking_player else target_player
	
	# Add item to player's inventory
	if player_to_give_item and player_to_give_item.player_inventory:
		print("DroppedItem: Adding %dx %s to player %s inventory" % [stack_amount, item_data.name, player_to_give_item.username])
		if item_data.name == "Coin":
			player_to_give_item.player_inventory.monies_amount += stack_amount
		# For stackable items, add with the stack amount
		elif item_data.can_stack and stack_amount > 1:
			for i in range(stack_amount):
				player_to_give_item.player_inventory.add_item(item_data.item_id)
		else:
			player_to_give_item.player_inventory.add_item(item_data.item_id)
	
	pickup_sound.stream = pickup_sfx
	
	pickup_sound.play()
	
	# Animate pickup: popup -> magnetize to player -> fade out
	var pickup_tween = create_tween()
	
	# Phase 1: Quick popup (0.1s)
	pickup_tween.tween_property(self, "global_position", global_position + Vector2(0, -20), 0.1).set_ease(Tween.EASE_OUT)
	
	# Phase 2: Magnetize quickly to player (0.2s)
	if player_to_give_item:
		var target_pos = player_to_give_item.global_position + Vector2(0, -20)  # Aim slightly above player
		pickup_tween.tween_property(self, "global_position", target_pos, 0.2).set_ease(Tween.EASE_IN)
	
	# Phase 3: Fade out slowly (0.3s) - runs in parallel with end of magnetize
	pickup_tween.parallel().tween_property(sprite, "modulate:a", 0.0, 0.3).set_ease(Tween.EASE_IN).set_delay(0.1)
	
	await pickup_sound.finished
	pickup_tween.finished.connect(queue_free)


func setup(item: ItemData, amount: int, player: MultiplayerPlayerV2) -> void:
	item_data = item
	stack_amount = amount
	target_player = player
	target_players = [player]  # Start with just the original player
	if target_player == null:
		is_public_pickup = true
	
	print("DroppedItem setup: %s x%d for player %s" % [item_data.name if item_data else "NULL", amount, player.username if player else "NULL"])
	
	# Set sprite to item's icon
	if item_data and item_data.icon:
		sprite.texture = item_data.icon
		# Scale the sprite to a reasonable size (adjust as needed)
		#sprite.scale = Vector2(0.5, 0.5)
	else:
		print("WARNING: DroppedItem has no icon!")
	
	# Start in popping state - item will settle on ground
	current_state = ItemState.POPPING
	is_pickup_ready = false


func add_party_member(player: MultiplayerPlayerV2) -> void:
	"""Add a party member to the list of players who can pick up this item"""
	if player not in target_players:
		target_players.append(player)
		print("DroppedItem: Added party member %s to pickup list" % player.username)


func make_public() -> void:
	"""Make this item available for anyone to pick up"""
	is_public_pickup = true
	print("DroppedItem: Item is now public - anyone can pick it up")


func check_and_make_public_if_needed() -> void:
	"""Check if original target is still valid, if not make item public"""
	if not is_instance_valid(target_player):
		print("DroppedItem: Original target is invalid, making item public")
		make_public()
		return
	
	# Check if any target players are still valid
	var has_valid_targets = false
	for player in target_players:
		if is_instance_valid(player):
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


func sync_state_to_peer(peer_id: int) -> void:
	if not multiplayer.is_server() or not sprite:
		return
	
	print("DroppedItem: Sync State to peer: %d" % peer_id)
	_set_state_rpc.rpc_id(peer_id, item_data.item_id)
	
	
@rpc("authority", "call_local", "reliable")
func _set_state_rpc(item_id: String) -> void:
	sprite.texture = ResourceManager.get_item_data(item_id).icon
