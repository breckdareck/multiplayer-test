class_name DroppedItem
extends CharacterBody2D

## The item data this represents
var item_data: ItemData
var stack_amount: int = 1
var target_player: MultiplayerPlayerV2

## Physics settings
@export var pop_force_y: float = -250.0  # Upward launch (negative is up)
@export var random_horizontal_range: float = 80.0  # Random left/right variance
@export var gravity: float = 900.0
@export var magnetize_delay: float = 1.2
@export var magnetize_speed: float = 280.0
@export var pickup_distance: float = 15.0
@export var ground_friction: float = 0.85
@export var min_settle_time: float = 1.2

@export var sprite: Sprite2D
@export var collision_shape: CollisionShape2D

## State
enum ItemState { POPPING, FALLING, MAGNETIZING, COLLECTED }
var current_state: ItemState = ItemState.POPPING
var state_timer: float = 0.0
var ground_timer: float = 0.0


func _ready() -> void:
	# Only run physics on server
	if not multiplayer.is_server():
		set_physics_process(false)
		return
	
	# Apply initial pop force with random horizontal component
	var horizontal_force = randf_range(-random_horizontal_range, random_horizontal_range)
	velocity = Vector2(horizontal_force, pop_force_y)
	
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
		ItemState.MAGNETIZING:
			_handle_magnetizing(delta)
		ItemState.COLLECTED:
			pass  # Do nothing, waiting for cleanup


func _handle_popping(delta: float) -> void:
	# Apply gravity
	velocity.y += gravity * delta
	
	# Move and slide
	var collision = move_and_slide()
	
	# Apply friction when on ground
	if is_on_floor():
		velocity.x *= ground_friction
		
		# If we've been on ground for a bit and velocity is low, start magnetizing
		if state_timer > min_settle_time and abs(velocity.x) < 20 and abs(velocity.y) < 20:
			print("DroppedItem transitioning to magnetize after ", state_timer, " seconds")
			current_state = ItemState.MAGNETIZING
			state_timer = 0.0
	
	# After magnetize_delay, force transition to magnetizing even if still moving
	if state_timer >= magnetize_delay:
		print("DroppedItem force transitioning to magnetize after ", state_timer, " seconds")
		current_state = ItemState.MAGNETIZING
		state_timer = 0.0


func _handle_magnetizing(delta: float) -> void:
	if not is_instance_valid(target_player):
		print("DroppedItem: Target player invalid, destroying")
		queue_free()
		return
	
	# Move towards player - ignore physics, fly directly
	var direction_to_player = (target_player.global_position - global_position).normalized()
	var distance = global_position.distance_to(target_player.global_position)
	
	# Accelerate as we get closer for a nice effect
	var speed_multiplier = clamp(distance / 100.0, 0.5, 2.0)
	velocity = direction_to_player * magnetize_speed * speed_multiplier
	
	# Move directly, don't use move_and_slide (we want to fly through walls to player)
	position += velocity * delta
	
	# Check distance to player for pickup
	if distance <= pickup_distance:
		print("DroppedItem: Picking up item")
		_pickup_item()


func _pickup_item() -> void:
	if current_state == ItemState.COLLECTED:
		return
	
	current_state = ItemState.COLLECTED
	
	# Add item to player's inventory
	if target_player and target_player.inventory_component:
		print("DroppedItem: Adding %dx %s to player inventory" % [stack_amount, item_data.name])
		if item_data.name == "Coin":
			target_player.inventory_component.monies_amount += stack_amount
		# For stackable items, add with the stack amount
		elif item_data.can_stack and stack_amount > 1:
			for i in range(stack_amount):
				target_player.inventory_component.add_item(item_data.item_id)
		else:
			target_player.inventory_component.add_item(item_data.item_id)
	
	# Clean up
	queue_free()


func setup(item: ItemData, amount: int, player: MultiplayerPlayerV2) -> void:
	item_data = item
	stack_amount = amount
	target_player = player
	
	print("DroppedItem setup: %s x%d for player %s" % [item_data.name if item_data else "NULL", amount, player.username if player else "NULL"])
	
	# Set sprite to item's icon
	if item_data and item_data.icon:
		sprite.texture = item_data.icon
		# Scale the sprite to a reasonable size (adjust as needed)
		#sprite.scale = Vector2(0.5, 0.5)
	else:
		print("WARNING: DroppedItem has no icon!")
