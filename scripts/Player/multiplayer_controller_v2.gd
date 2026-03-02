class_name MultiplayerPlayerV2
extends CharacterBody2D

const SPEED: float = 130.0
const JUMP_VELOCITY: float = -300.0
const SERVER_ID: int = 1

@export var player_id := 1:
	set(id):
		player_id = id
		var input_sync = get_node_or_null("%InputSynchronizer")
		if input_sync:
			input_sync.set_multiplayer_authority(id)

@export_category("Collision")
@export var platform_layer: int = 3

@export_category("Components")
@export var health_component: HealthComponent
@export var mana_component: ManaComponent
@export var combat_component: CombatComponent
@export var level_component: LevelingComponent
@export var stats_component: StatsComponent
@export var class_component: ClassComponent
@export var player_inventory: PlayerInventory
@export var inventory_component: InventoryComponent
@export var equipment_component: EquipmentComponent
@export var ability_component: AbilityComponent
@export var buff_component: BuffComponent
@export var debug_component: MyDebugComponent

@export_category("UI")
@export var player_HUD: Control
@export var player_name_label: RichTextLabel
@export var stats_window: StatsWindow
@export var inventory_window: InventoryWindow


var username: String = ""
var _current_party_id: int = -1

var direction: int = 0 # The current input direction from the synchronizer
var facing_direction: int = 1 # The last non-zero direction, for facing
var input_down: bool = false # The current down input from the synchronizer

var do_attack: bool = false
var do_jump: bool = false
var do_drop: bool = false
var do_pickup: bool = false
var do_portal_interact: bool = false
var current_portal: Portal = null

var _sprite_base_offset_x: float
var _is_being_cleaned_up: bool = false
var _is_loading_data: bool = false

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine = $StateMachine
@onready var coyote_timer: Timer = $CoyoteTimer
@onready var drop_timer: Timer = $DropTimer
@onready var respawn_timer: Timer = $RespawnTimer
@onready var basic_attack_hitbox: CollisionShape2D = $Hitbox/BasicAttackHitbox
@onready var projectile_spawn_location: Marker2D = $ProjectileSpawnLocation
const GAME_MENU_SCENE = preload("res://scenes/UI/game_menu.tscn")

@onready var game_menu: GameMenu
@onready var input_synchronizer: MultiplayerSynchronizer = $InputSynchronizer


#=============================================================================
# GODOT LIFECYCLE METHODS
#=============================================================================

func _ready() -> void:
	if multiplayer.get_unique_id() == player_id:
		ChatManager.register_local_player(self)
		# Request the sprite states of all other players from the server.
		stats_window.update_stats_window()
		request_all_sprite_states.rpc_id(SERVER_ID)

	# Server-specific setup
	if multiplayer.is_server():
		# Handle sprite change on initial spawn
		await get_tree().process_frame
		_handle_sprite_change_on_server()
		
	# Setup signals for both client and server (for data saving)
	_setup_signals()

	# Client-specific setup
	if not OS.has_feature("dedicated_server"):
		_setup_client_visuals()

	# Initialize components
	if is_instance_valid(debug_component):
		debug_component.set_health_component(health_component)
		debug_component.set_player(self)

	# Auto-save is now handled by SaveManager (server-side, for all players).

	state_machine.init(self, animated_sprite)
	
	# Setup visibility filter if multiplayer
	if multiplayer.has_multiplayer_peer():
		call_deferred("_setup_visibility_filter")


func _process(delta: float) -> void:
	if _is_being_cleaned_up:
		return

	if get_tree().get_multiplayer().has_multiplayer_peer() and multiplayer.is_server():
		state_machine.process_frame(delta)
	

func _physics_process(delta: float) -> void:
	if _is_being_cleaned_up:
		return

	# Server-authoritative physics processing
	if get_tree().get_multiplayer().has_multiplayer_peer() and multiplayer.is_server():
		_update_input_from_synchronizer()
		state_machine.process_physics(delta)

	# Visual updates run on all peers (clients and server)
	_update_sprite_facing_direction()

	# Process portal interaction
	if do_portal_interact:
		do_portal_interact = false # Reset the flag immediately
		if is_instance_valid(current_portal):
			current_portal.interact(player_id)


func set_current_portal(portal_node: Portal):
	current_portal = portal_node

func clear_current_portal():
	current_portal = null


func _unhandled_input(event: InputEvent) -> void:
	if _is_being_cleaned_up:
		return

	# Only local player handles UI input
	if multiplayer.get_unique_id() == player_id:
		# Ignore echo events for menu toggle
		if event is InputEventKey and event.is_echo():
			return

		if is_instance_valid(game_menu):
			# Always pass input to game_menu so it can open/close itself
			game_menu._unhandled_input(event)
			if game_menu.visible: # If game menu is now visible (or was already visible and handled an event)
				return # Consume input so it doesn't affect player movement
	
	if multiplayer.is_server():
		state_machine.process_input(event)


func _exit_tree():
	cleanup_before_removal()

#=============================================================================
# PUBLIC METHODS
#=============================================================================

func apply_knockback(knockback: Vector2) -> void:
	if _is_being_cleaned_up:
		return

	# Simple knockback: directly set velocity. You may want to blend or add for smoother effect.
	velocity.x = knockback.x
	velocity.y = knockback.y


# Experience/Leveling
func gain_experience(amount: int) -> void:
	if _is_being_cleaned_up:
		return

	if level_component and level_component.has_method("add_exp"):
		level_component.add_exp(amount)


func can_drop_through_platform() -> bool:
	if _is_being_cleaned_up:
		return false

	# Check if the floor is a droppable platform.
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision.get_angle(up_direction) < floor_max_angle + 0.01:
			var collider_rid: RID = collision.get_collider_rid()
			var collider_layer_mask: int = PhysicsServer2D.body_get_collision_layer(collider_rid)
			if collider_layer_mask & (1 << (platform_layer - 1)):
				return true
			break # We found the floor, no need to check other collisions.
	return false


func drop_through_platform() -> void:
	if _is_being_cleaned_up:
		return

	set_collision_mask_value(platform_layer, false)
	drop_timer.start()


func cleanup_before_removal():
	print("MPController: Cleaning up MultiplayerPlayer: ", player_id)
	_is_being_cleaned_up = true

	# Stop all processing
	set_process(false)
	set_physics_process(false)

	# Disconnect all signals to prevent callbacks during cleanup
	if health_component and health_component.died.is_connected(_on_player_died):
		health_component.died.disconnect(_on_player_died)

	# Stop timers
	if is_instance_valid(drop_timer):
		drop_timer.stop()
	if is_instance_valid(coyote_timer):
		coyote_timer.stop()
	if has_node("RespawnTimer"):
		$RespawnTimer.stop()

	
#=============================================================================
# PRIVATE HELPER METHODS
#=============================================================================

func _setup_signals() -> void:
	# Connect component signals to handle game logic and data saving.
	# These should run on both Client (to trigger RPC save) and Server (to save directly).
	if level_component:
		level_component.experience_changed.connect(func(_c, _e): _data_changed("stats"))
		level_component.leveled_up.connect(func(_l): _data_changed("all")) # Level up might affect everything (points, stats)
		if multiplayer.is_server():
			level_component.leveled_up.connect(_handle_sprite_change_on_server.unbind(1))
	
	if health_component:
		health_component.health_changed.connect(func(_c, _m): _data_changed("stats"))
		
	if ability_component:
		ability_component.ability_leveled_up.connect(func(_a, _l): _data_changed("abilities"))
		ability_component.ability_points_changed.connect(func(_p): _data_changed("abilities"))
		ability_component.ability_learned.connect(func(_a): _data_changed("abilities"))

	if inventory_component:
		inventory_component.inventory_saved.connect(func(_inv): _data_changed("inventory"))
		
	if buff_component:
		buff_component.buff_applied.connect(func(_b, _d): _data_changed("buffs"))
		buff_component.buff_removed.connect(func(_b): _data_changed("buffs"))
		buff_component.buff_refreshed.connect(func(_b, _d): _data_changed("buffs"))

	if equipment_component:
		equipment_component.on_equipment_changed.connect(func(): _data_changed("equipment"))

		
	# Server-only logic
	if multiplayer.is_server():
		if is_instance_valid(drop_timer):
			drop_timer.timeout.connect(_on_drop_timer_timeout)

		if is_instance_valid(respawn_timer):
			respawn_timer.timeout.connect(respawn)


func _setup_client_visuals() -> void:
	var camera: Camera2D = $Camera2D

	if multiplayer.get_unique_id() == player_id:
		camera.make_current()
		if is_instance_valid(debug_component):
			debug_component.debug_panel.show()
		if is_instance_valid(player_HUD):
			player_HUD.show()
			# Show mobile controls on Android
			if OS.get_name() == "Android":
				var mobile_controls = player_HUD.get_child(1)
				if is_instance_valid(mobile_controls):
					mobile_controls.show()
			
			# Instantiate and add GameMenu
			game_menu = GAME_MENU_SCENE.instantiate()
			player_HUD.add_child(game_menu)
	else:
		camera.enabled = false

	# Store sprite offset for correct flipping.
	_sprite_base_offset_x = abs(animated_sprite.offset.x)


func _setup_visibility_filter():
	"""Setup visibility filter for this player's synchronizer"""
	if not is_instance_valid(input_synchronizer):
		push_warning("Player %d: InputSynchronizer not found for visibility filter" % player_id)
		return
	
	# Add visibility filter to control which peers can see this player
	input_synchronizer.add_visibility_filter(_check_visibility_by_map)
	print("Player %d: Added visibility filter to InputSynchronizer" % player_id)


func _check_visibility_by_map(peer_id: int) -> bool:
	"""Visibility filter callback - only visible to players on same map"""
	if not multiplayer.is_server():
		return true # Clients don't filter, server handles it
	
	# Safety check: if we're being cleaned up, allow visibility
	if _is_being_cleaned_up:
		return false
	
	# Get this player's map - handle case where player might not be tracked yet
	var my_map = MapManager.get_player_map(player_id)
	if my_map.is_empty():
		return false # Not on any map yet
	
	# Server always sees everyone
	if peer_id == 1:
		return true
	
	# Get other player's map - handle case where they might not exist
	var their_map = MapManager.get_player_map(peer_id)
	if their_map.is_empty():
		return false # They're not on any map yet or have disconnected
	
	# Only visible if on same map
	return my_map == their_map


func _update_input_from_synchronizer() -> void:
	# Do not process input if the player is dead.
	if is_instance_valid(health_component) and health_component.is_dead:
		direction = 0
		input_down = false
		return

	var input_sync: Node = get_node_or_null("%InputSynchronizer")
	if is_instance_valid(input_sync):
		direction = input_sync.input_direction
		input_down = input_sync.input_down
	else:
		# Fallback if the synchronizer is not found.
		direction = 0
		input_down = false


func is_pressing_pickup() -> bool:
	return do_pickup

func _update_sprite_facing_direction() -> void:
	if state_machine.current_state and state_machine.current_state.allow_flip:
		animated_sprite.flip_h = facing_direction < 0

		var offset_sign: float = -1.0 if facing_direction < 0 else 1.0
		animated_sprite.offset.x = _sprite_base_offset_x * offset_sign


func _change_sprite() -> void:
	if player_id != multiplayer.get_unique_id():
		return

	if multiplayer.is_server():
		_handle_sprite_change_on_server() # Host client can call directly.
	else:
		request_sprite_change.rpc_id(SERVER_ID) # Remote clients must ask server.

		
func _handle_sprite_change_on_server() -> void:
	if not is_instance_valid(class_component) or not is_instance_valid(level_component):
		return

	var class_type: int = class_component.current_class
	var current_level: int = level_component.level

	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, current_level)
	if sprite_frames:
		change_sprite_rpc.rpc(class_component.get_class_name(), current_level)

func change_to_map(new_map_id: String, spawn_point_name: String = ""):
	if not multiplayer.is_server():
		# Client requests map change from server
		# Send our local data to ensure the server has the absolute latest state before the swap
		var data_string: String = JSON.stringify(get_save_data())
		request_map_change_rpc.rpc_id(1, new_map_id, spawn_point_name, data_string)
	else:
		# Server can change directly, but MUST save first
		_data_changed()
		MapManager.request_map_change(player_id, new_map_id, spawn_point_name)


func set_current_party_id(id: int):
	_current_party_id = id

## DEPRECATED wrapper — kept so player_manager.gd (and any other caller using
## the old underscore-prefixed name) continues to work until it is updated.
func _get_save_data(update_type: String = "all") -> Dictionary:
	return get_save_data(update_type)

## Public so SaveManager can call it when the debounce timer fires.
func get_save_data(update_type: String = "all") -> Dictionary:
	var data: Dictionary = {
		'username': username
	}
	
	# Always include basic stats if "all" or "stats"
	if update_type == "all" or update_type == "stats":
		data.merge(_get_stats_data())
	
	if update_type == "all" or update_type == "inventory":
		if is_instance_valid(player_inventory):
			data['inventory'] = player_inventory.save_player_inventory()
	
	if update_type == "all" or update_type == "abilities":
		if is_instance_valid(ability_component):
			data['abilities'] = ability_component.save_abilities()
		
	if update_type == "all" or update_type == "buffs":
		if is_instance_valid(buff_component):
			data['buffs'] = buff_component.save_buffs()
		
	return data


func _get_stats_data() -> Dictionary:
	return {
		'max_health': health_component.max_health if is_instance_valid(health_component) else 100,
		'current_health': health_component.current_health if is_instance_valid(health_component) else 100,
		'level': level_component.level if is_instance_valid(level_component) else 1,
		'experience': level_component.experience if is_instance_valid(level_component) else 0,
		'party_id': _current_party_id,
		'last_map': MapManager.get_player_map(player_id) if multiplayer.is_server() else MapManager.current_map_id,
		'character_type': class_component.current_class if is_instance_valid(class_component) else 0
	}


func _load_data(data: Dictionary) -> void:
	if _is_being_cleaned_up:
		return
	
	_is_loading_data = true
	
	print("Loading data for ", data.get("username", "Unknown"))
	
	if is_instance_valid(stats_component):
		stats_component.set_loading_mode(true)
		stats_component.set_block_signals(true)
		
	if is_instance_valid(ability_component):
		ability_component.set_loading_mode(true)
		ability_component.disconnect_level_signals()

	if is_instance_valid(level_component):
		level_component.set_block_signals(true)
		level_component.level = data.get("level", 1)
		level_component.experience = data.get("experience", 0)
		
	if is_instance_valid(inventory_component):
		var inventory_data = data.get("inventory", {})
		if not inventory_data.is_empty():
			inventory_component.load_inventory(inventory_data)
			
	if is_instance_valid(health_component):
		health_component.set_loading_mode(true)
		health_component.max_health = data.get("max_health", health_component.max_health)
		health_component.current_health = data.get("current_health", health_component.max_health)

	if is_instance_valid(ability_component):
		var ability_data = data.get("abilities", {})
		if not ability_data.is_empty():
			ability_component.load_abilities(ability_data)
			
	if is_instance_valid(level_component):
		level_component.set_block_signals(false)
		level_component.leveled_up.emit(level_component.level)
		level_component.experience_changed.emit(level_component.experience, level_component.get_exp_to_next_level())

	if is_instance_valid(stats_component):
		stats_component.set_block_signals(false)
		stats_component.stats_changed.emit()
	
	if is_instance_valid(ability_component):
		ability_component.reconnect_level_signals()
		ability_component.set_loading_mode(false)

	if is_instance_valid(health_component):
		health_component.set_loading_mode(false)
		health_component.health_changed.emit(health_component.current_health, health_component.max_health)
		
	if is_instance_valid(buff_component):
		var buff_data = data.get("buffs", {})
		if not buff_data.is_empty():
			buff_component.load_buffs(buff_data)
		
	_is_loading_data = false


#=============================================================================
# SIGNAL HANDLERS
#=============================================================================

func _on_player_died(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return
	respawn_timer.start()


func _on_drop_timer_timeout() -> void:
	if _is_being_cleaned_up:
		return
	set_collision_mask_value(platform_layer, true)

func get_current_health() -> int:
	return health_component.current_health if is_instance_valid(health_component) else 0

func get_max_health() -> int:
	return health_component.max_health if is_instance_valid(health_component) else 0

func _data_changed(update_type: String = "all") -> void:
	if _is_being_cleaned_up or _is_loading_data:
		return
	if not multiplayer.is_server():
		# Client: tell the server about the change via lightweight RPC
		_notify_server_data_changed.rpc_id(SERVER_ID, update_type)
		return
	# Server: queue a debounced save through SaveManager
	if username and SaveManager:
		SaveManager.queue_save(username, update_type, self)


func _on_peer_connected(peer_id: int) -> void:
	if not multiplayer.is_server() or peer_id == player_id:
		return

	# Wait a frame to ensure the new peer is ready.
	await get_tree().process_frame

	print("Sending sprite data for player %d to new peer %d" % [player_id, peer_id])
	if is_instance_valid(class_component) and is_instance_valid(level_component):
		var _class_name: String = class_component.get_class_name()
		var current_level: int = level_component.level
		change_sprite_rpc.rpc_id(peer_id, _class_name, current_level)


#=============================================================================
# RPC (REMOTE PROCEDURE CALL) METHODS
#=============================================================================

# [SERVER-ONLY] Respawns the player at a designated point.
@rpc("any_peer", "call_local", "reliable")
func respawn() -> void:
	if not multiplayer.is_server() or _is_being_cleaned_up:
		return

	# The server authoritatively sets the respawn position and resets state.
	position = MultiplayerManager.respawn_point
	do_attack = false
	do_jump = false
	do_drop = false
	if is_instance_valid(health_component):
		health_component.respawn()


# [CLIENT -> SERVER] Lightweight RPC so clients can notify the server that
# data changed without serialising the full payload. The server collects the
# actual data lazily through SaveManager when the debounce window closes.
@rpc("any_peer", "call_remote", "reliable")
func _notify_server_data_changed(update_type: String) -> void:
	if not multiplayer.is_server():
		return
	if username and SaveManager:
		SaveManager.queue_save(username, update_type, self)


# [CLIENT -> SERVER] DEPRECATED — kept for backwards compatibility.
# New code should use _notify_server_data_changed instead.
@rpc("any_peer", "call_local", "reliable")
func save_on_server(data_string: String) -> void:
	if not multiplayer.is_server():
		return

	# Legacy path: parse the data and forward to PlayerManager directly.
	var parsed_data: Dictionary = JSON.parse_string(data_string)
	if parsed_data.is_empty():
		push_error("Failed to parse JSON for saving.")
		return

	var user_name: String = parsed_data.get("username", "")
	if user_name.is_empty(): return

	# Delegate saving through SaveManager (debounced, queued)
	if SaveManager:
		SaveManager.queue_save(user_name, "all", self)


# [CLIENT -> SERVER] Asks the server to initiate a sprite change for this player.
@rpc("any_peer", "call_local", "reliable")
func request_sprite_change() -> void:
	if not multiplayer.is_server():
		return
	_handle_sprite_change_on_server()


# [SERVER -> CLIENTS] Broadcasts the sprite change to all clients.
@rpc("authority", "call_local", "reliable")
func change_sprite_rpc(_class_name: String, level: int) -> void:
	var class_type: int = ResourceManager.get_class_type_from_string(_class_name)
	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, level)
	print("Sprite Frames:" + sprite_frames.resource_path)
	if sprite_frames:
		animated_sprite.sprite_frames = sprite_frames
		animated_sprite.play("idle")
	else:
		push_warning("Could not find sprite for %s level %d" % [_class_name, level])


# [CLIENT -> SERVER] Client requests to change their class.
@rpc("any_peer", "call_local", "reliable")
func change_class_request(new_class: int) -> void:
	if not multiplayer.is_server():
		return
	print("Change Class Request")
	if is_instance_valid(class_component):
		class_component.change_class_rpc.rpc(new_class)
		_handle_sprite_change_on_server()


# [CLIENT -> SERVER] A new client requests the sprite states of all existing players.
@rpc("any_peer", "call_local", "reliable")
func request_all_sprite_states() -> void:
	if not multiplayer.is_server():
		return
	
	var requester_id: int = multiplayer.get_remote_sender_id()
	print("Player %d requesting all sprite states" % requester_id)
	
	# Get the map this player is on
	var requester_map = MapManager.get_player_map(requester_id)
	if requester_map.is_empty():
		push_warning("Player %d not assigned to a map yet" % requester_id)
		return
	
	# Only sync sprites of players on the SAME map
	var players_on_map = MapManager.get_players_on_map(requester_map)
	
	for other_player_id in players_on_map:
		if other_player_id == requester_id:
			continue # Skip self
		
		var other_player = PlayerManager.get_player_node(other_player_id)
		if other_player and other_player is MultiplayerPlayerV2:
			print("  Syncing sprite for player %d to requester %d" % [other_player_id, requester_id])
			other_player._on_peer_connected(requester_id)


# [ALL PEERS] Sets the username for this player instance across all clients.
@rpc("any_peer", "call_local", "reliable")
func set_username(uname: String) -> void:
	username = uname
	if is_instance_valid(player_name_label):
		player_name_label.text = username
		
		
@rpc("any_peer", "call_local", "reliable")
func request_map_change_rpc(new_map_id: String, spawn_point_name: String = "", client_data_string: String = ""):
	"""Server receives map change request"""
	if not multiplayer.is_server():
		return
	
	var requester_id = multiplayer.get_remote_sender_id()
	print("Player %d requesting map change to '%s' at spawn '%s'" % [requester_id, new_map_id, spawn_point_name])
	
	# Save player data before moving
	if not client_data_string.is_empty():
		print("Server: Saving client-provided data for player %d before map change." % requester_id)
		save_on_server(client_data_string)
	else:
		print("Server: No client data provided, saving server-side state for player %d." % requester_id)
		_data_changed()
	
	# Change map through MapManager
	MapManager.request_map_change(requester_id, new_map_id, spawn_point_name)


@rpc("authority", "call_local", "reliable")
func set_loading_state_rpc(is_loading: bool) -> void:
	"""Allow server to control loading state on client to prevent save spam during sync"""
	_is_loading_data = is_loading
	print("Client: Loading state set to ", is_loading)
