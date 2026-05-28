class_name MultiplayerPlayerV2
extends CharacterBody2D

const SPEED: float = 130.0
const JUMP_VELOCITY: float = -300.0
const SERVER_ID: int = 1
# Terminal fall speed. Without this, a long fall (or velocity accumulated while
# dead) lets the body move far enough per frame to pass through thin one-way
# platforms via the one-way collision heuristic.
const MAX_FALL_SPEED: float = 1200.0

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
@export var weapon_mastery_component: WeaponMasteryComponent
## PR 5: Sword discipline's signature combat system — combo points built
## by basic-attack hits and consumed by Slash for amplified damage.
## See scripts/Components/sword_combo.gd.
@export var sword_combo_component: SwordComboComponent
@export var player_inventory: PlayerInventory
@export var inventory_component: InventoryComponent
@export var equipment_component: EquipmentComponent
@export var ability_component: AbilityComponent
@export var buff_component: BuffComponent

@export_category("UI")
@export var player_HUD: Control
@export var player_name_label: RichTextLabel
@export var stats_window: StatsWindow
@export var inventory_window: InventoryWindow
@export var quest_window: QuestWindow


var username: String = ""
var _current_party_id: int = -1

var direction: int = 0 # The current input direction from the synchronizer
var facing_direction: int = 1 # The last non-zero direction, for facing
var input_down: bool = false # The current down input from the synchronizer
var input_up: bool = false # The current up input from the synchronizer

var do_attack: bool = false
var do_jump: bool = false
var do_drop: bool = false
var do_pickup: bool = false
var do_portal_interact: bool = false
var current_portal: Portal = null

# Server-only list of Ladder Area2Ds the player currently overlaps. Ladders
# call enter_ladder/exit_ladder on their body_entered/exited signals.
var _ladder_zones: Array = []

# Position-based drop-through state. We disable the platform-layer mask until
# the player's center has cleared the bottom edge of the specific platform
# they dropped from — that way stacked platforms aren't all passed through.
var _drop_through_active: bool = false
var _drop_through_target_y: float = 0.0

var _sprite_base_offset_x: float
var _is_being_cleaned_up: bool = false
var _is_loading_data: bool = false
## PR 3: server-side gate for the weapon-swap transition window. While true,
## input flags are zeroed in _update_input_from_synchronizer so the player
## can't act mid-flash. Re-enabled when the transition timer fires.
var _swap_input_locked: bool = false
var _context_menu: PlayerContextMenu

@onready var camera: Camera2D = $Camera2D
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
	var _is_bot := BotManager.is_bot(player_id)

	if not _is_bot and multiplayer.get_unique_id() == player_id:
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

	# Client-specific setup (skip for bots — they have no display)
	if not _is_bot and not OS.has_feature("dedicated_server"):
		_setup_client_visuals()

	state_machine.init(self, animated_sprite)

	# Setup visibility filter if multiplayer (bots don't need input sync visibility)
	if not _is_bot and multiplayer.has_multiplayer_peer():
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
		velocity.y = minf(velocity.y, MAX_FALL_SPEED)
		state_machine.process_physics(delta)
		_check_drop_through_complete()

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


# --- Ladder zone tracking (server-authoritative) ---

func enter_ladder(ladder: Node) -> void:
	if not multiplayer.is_server():
		return
	if not _ladder_zones.has(ladder):
		_ladder_zones.append(ladder)

func exit_ladder(ladder: Node) -> void:
	if not multiplayer.is_server():
		return
	_ladder_zones.erase(ladder)

func is_in_ladder_zone() -> bool:
	# Prune any freed ladders lazily.
	for i in range(_ladder_zones.size() - 1, -1, -1):
		if not is_instance_valid(_ladder_zones[i]):
			_ladder_zones.remove_at(i)
	return _ladder_zones.size() > 0

func get_active_ladder() -> Node:
	if is_in_ladder_zone():
		return _ladder_zones[0]
	return null


func _unhandled_input(event: InputEvent) -> void:
	if _is_being_cleaned_up:
		return

	# Only local player handles UI input
	if multiplayer.get_unique_id() == player_id:
		# Ignore echo events for menu toggle
		if event is InputEventKey and event.is_echo():
			return

		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			if _handle_right_click(event):
				return

		if is_instance_valid(game_menu):
			# Always pass input to game_menu so it can open/close itself
			game_menu._unhandled_input(event)
			if game_menu.visible: # If game menu is now visible (or was already visible and handled an event)
				return # Consume input so it doesn't affect player movement

	if multiplayer.is_server():
		state_machine.process_input(event)


func _handle_right_click(event: InputEventMouseButton) -> bool:
	var click_world_pos := get_global_mouse_position()
	var click_range_sq := 900.0  # 30px radius for click detection
	var sprite_center_offset := Vector2(0, -16)

	var best_target: MultiplayerPlayerV2 = null
	var best_dist_sq := click_range_sq

	for node in get_tree().get_nodes_in_group("Players"):
		if node is not MultiplayerPlayerV2:
			continue
		if not is_instance_valid(node):
			continue
		if node == self:
			continue
		var char_center = node.global_position + sprite_center_offset
		var dist_sq := click_world_pos.distance_squared_to(char_center)
		if dist_sq < best_dist_sq:
			best_dist_sq = dist_sq
			best_target = node

	if not best_target:
		return false

	if not is_instance_valid(_context_menu):
		_context_menu = PlayerContextMenu.create()
		var moveable_container = get_node_or_null("CanvasLayer/MoveableWindows")
		if moveable_container:
			moveable_container.add_child(_context_menu)
		else:
			get_node("CanvasLayer").add_child(_context_menu)

	_context_menu.show_for_target(best_target.player_id, event.global_position)
	return true


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

	# Dead players earn no experience, even if they dealt damage before dying.
	if is_instance_valid(health_component) and health_component.is_dead:
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

	# Default fallback distance if we can't read the platform's shape.
	var target_y: float = global_position.y + 12.0

	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		if collision.get_angle(up_direction) >= floor_max_angle + 0.01:
			continue
		var collider_rid: RID = collision.get_collider_rid()
		var collider_layer_mask: int = PhysicsServer2D.body_get_collision_layer(collider_rid)
		if not (collider_layer_mask & (1 << (platform_layer - 1))):
			continue
		var collider_shape: Object = collision.get_collider_shape()
		if collider_shape is CollisionShape2D:
			var cs := collider_shape as CollisionShape2D
			if cs.shape is RectangleShape2D:
				var rect := cs.shape as RectangleShape2D
				target_y = cs.global_position.y + rect.size.y * 0.5 + 1.0
		break

	_drop_through_target_y = target_y
	_drop_through_active = true
	set_collision_mask_value(platform_layer, false)
	# Safety fallback in case the position check never fires (e.g. player gets
	# caught in a wall, gravity disabled, etc.). The position check normally
	# wins long before this expires.
	drop_timer.start()


func _check_drop_through_complete() -> void:
	if not _drop_through_active:
		return
	if global_position.y >= _drop_through_target_y:
		set_collision_mask_value(platform_layer, true)
		_drop_through_active = false
		if is_instance_valid(drop_timer):
			drop_timer.stop()


func cleanup_before_removal():
	#print("MPController: Cleaning up MultiplayerPlayer: ", player_id)
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
		level_component.experience_changed.connect(func(_c, _e): _data_changed())
		level_component.leveled_up.connect(func(_l): _data_changed())
		level_component.leveled_up.connect(_on_leveled_up_effect)
		level_component.experience_changed.connect(func(_c, _e): _data_changed("stats"))
		level_component.leveled_up.connect(func(_l): _data_changed("all")) # Level up might affect everything (points, stats)
		level_component.leveled_up.connect(func(new_level):
			if multiplayer.is_server() and not _is_loading_data:
				QuestManager.record_level_up(username, new_level)
				if new_level == JobAdvancementManager.ADVANCEMENT_LEVEL:
					QuestManager.notify_advancement_available(username)
		)
		if multiplayer.is_server():
			level_component.leveled_up.connect(_handle_sprite_change_on_server.unbind(1))
	
	if health_component:
		health_component.health_changed.connect(func(_c, _m): _data_changed("stats"))
		
	if ability_component:
		ability_component.ability_leveled_up.connect(func(_a, _l): _data_changed("abilities"))
		ability_component.ability_points_changed.connect(func(_k, _p): _data_changed("abilities"))
		ability_component.ability_learned.connect(func(_a): _data_changed("abilities"))

	if inventory_component:
		inventory_component.inventory_saved.connect(func(_inv): _data_changed("inventory"))
		
	if buff_component:
		buff_component.buff_applied.connect(func(_b, _d): _data_changed("buffs"))
		buff_component.buff_removed.connect(func(_b): _data_changed("buffs"))
		buff_component.buff_refreshed.connect(func(_b, _d): _data_changed("buffs"))

	if equipment_component:
		equipment_component.on_equipment_changed.connect(func(): _data_changed("equipment"))
		# PR 3: react to active-weapon flips for sprite swap + transition FX.
		# The active_weapon flag itself rides in the equipment save bucket.
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)
		# PR 4 fix (2026-05-27): also refresh the sprite when the ITEM in the
		# active weapon slot changes (e.g. dragging a different weapon in/out
		# of the equipped slot), not just on a Tab-swap. No FX/lock for this
		# path — just resync the sprite + class signals downstream. Runs on
		# the server so the change_sprite_rpc broadcast hits every peer.
		if multiplayer.is_server():
			equipment_component.on_equipment_changed.connect(_on_equipment_changed_refresh_sprite)

	if class_component:
		# Persist class changes (job advancement) so the new class survives the
		# next spawn / login. character_type rides in the "stats" save bucket,
		# which the backend maps onto the Player.character_class column.
		class_component.class_changed.connect(func(_new_class): _data_changed("stats"))

	# Server-only logic
	if multiplayer.is_server():
		if is_instance_valid(drop_timer):
			drop_timer.timeout.connect(_on_drop_timer_timeout)

		if is_instance_valid(respawn_timer):
			respawn_timer.timeout.connect(respawn)


## Read the current map's camera_limit_* from its MapBase root and apply to
## the local player's Camera2D. Called on every spawn (including map changes),
## so each zone gets its own bounds.
func _apply_map_camera_bounds(cam: Camera2D) -> void:
	if not is_instance_valid(cam):
		return
	var parent_node := get_parent()
	var map_root := parent_node.get_parent() if parent_node else null
	if map_root and map_root is MapBase:
		var mb := map_root as MapBase
		cam.limit_left = mb.camera_limit_left
		cam.limit_top = mb.camera_limit_top
		cam.limit_right = mb.camera_limit_right
		cam.limit_bottom = mb.camera_limit_bottom


func _setup_client_visuals() -> void:
	var cam: Camera2D = $Camera2D

	if multiplayer.get_unique_id() == player_id:
		cam.make_current()
		_apply_map_camera_bounds(cam)
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

			# Instantiate and add the always-on quest tracker overlay
			var quest_tracker := QuestTracker.new()
			quest_tracker.setup(self)
			player_HUD.add_child(quest_tracker)

			# Zone-entry banner — shown briefly when the local player spawns
			# into a new map. Reads the themed name from MapBase.display_name.
			var parent_node := get_parent()
			var map_root := parent_node.get_parent() if parent_node else null
			if map_root and map_root is MapBase and not (map_root as MapBase).display_name.is_empty():
				var banner := ZoneBanner.new()
				player_HUD.add_child(banner)
				banner.show_zone((map_root as MapBase).display_name)
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
	#print("Player %d: Added visibility filter to InputSynchronizer" % player_id)


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

	# Bots have no client — don't sync to them
	if BotManager.is_bot(peer_id):
		return false

	# Get other player's map - handle case where they might not exist
	var their_map = MapManager.get_player_map(peer_id)
	if their_map.is_empty():
		return false # They're not on any map yet or have disconnected
	
	# Only visible if on same map
	return my_map == their_map


func _update_input_from_synchronizer() -> void:
	# Bots set their own input flags via BotBrain — skip synchronizer read.
	if BotManager.is_bot(player_id):
		return

	# Do not process input if the player is dead.
	if is_instance_valid(health_component) and health_component.is_dead:
		direction = 0
		input_down = false
		input_up = false
		return

	# PR 3: zero input during the weapon-swap transition window so the player
	# can't act mid-flash. The lock auto-clears after SWAP_TRANSITION_DURATION.
	if _swap_input_locked:
		direction = 0
		input_down = false
		input_up = false
		do_attack = false
		do_jump = false
		do_drop = false
		return

	var input_sync: Node = get_node_or_null("%InputSynchronizer")
	if is_instance_valid(input_sync):
		direction = input_sync.input_direction
		input_down = input_sync.input_down
		input_up = input_sync.input_up
	else:
		# Fallback if the synchronizer is not found.
		direction = 0
		input_down = false
		input_up = false


func is_pressing_pickup() -> bool:
	return do_pickup

func _update_sprite_facing_direction() -> void:
	if state_machine.current_state and state_machine.current_state.allow_flip:
		animated_sprite.flip_h = facing_direction < 0

		var offset_sign: float = -1.0 if facing_direction < 0 else 1.0
		animated_sprite.offset.x = _sprite_base_offset_x * offset_sign

	var client_shadow = get_node_or_null("ShadowPartnerClient")
	if client_shadow:
		client_shadow.position = Vector2(-10 * facing_direction, 0)
		var shadow_sprite = client_shadow.get_node_or_null("ShadowSprite")
		if shadow_sprite and animated_sprite:
			shadow_sprite.flip_h = animated_sprite.flip_h
			if animated_sprite.is_playing():
				shadow_sprite.play(animated_sprite.animation)


func _change_sprite() -> void:
	if player_id != multiplayer.get_unique_id():
		return

	if multiplayer.is_server():
		_handle_sprite_change_on_server() # Host client can call directly.
	else:
		request_sprite_change.rpc_id(SERVER_ID) # Remote clients must ask server.

		
## Returns the discipline (Constants.ClassType) the player is CURRENTLY
## wielding — i.e. the discipline of the active weapon. Falls back to the
## starting class (class_component.current_class) when no weapon is equipped.
##
## This is the "I am my weapon" identity lookup. Use it for sprite picking,
## attack-state branches, and anything else whose behavior should follow the
## equipped weapon rather than the character's chosen starting class. HP/MP
## curves intentionally stay anchored to class_component.current_class
## (per the locked design — HP/MP doesn't shift on weapon swap).
func get_active_discipline() -> int:
	if is_instance_valid(equipment_component):
		var weapon: WeaponData = equipment_component.active_weapon_data
		if weapon != null:
			var disc: int = _weapon_type_to_class_type(weapon.weapon_type)
			if disc != -1:
				return disc
	if is_instance_valid(class_component):
		return class_component.current_class
	return Constants.ClassType.SWORD


## Returns the disciplines of ALL equipped weapons — both the primary AND
## the secondary slot. Used by AbilityComponent for the passive-application
## rule: a passive from discipline X applies if discipline X has a weapon
## in EITHER slot (not just the active one). Trees you've put points into
## but haven't equipped contribute nothing.
##
## De-duplicates (two swords in both slots → one SWORD entry). If neither
## slot is equipped (bare-handed), falls back to the starting class's
## discipline so passives still work in the un-equipped baseline case.
func get_equipped_disciplines() -> Array[int]:
	var disciplines: Array[int] = []
	if is_instance_valid(equipment_component):
		var primary_sd: SlotData = equipment_component.weapon_slot_data
		if primary_sd != null and primary_sd.item != null:
			var primary_weapon: WeaponData = primary_sd.item as WeaponData
			if primary_weapon != null:
				var disc: int = _weapon_type_to_class_type(primary_weapon.weapon_type)
				if disc != -1:
					disciplines.append(disc)
		var secondary_sd: SlotData = equipment_component.secondary_weapon_slot_data
		if secondary_sd != null and secondary_sd.item != null:
			var secondary_weapon: WeaponData = secondary_sd.item as WeaponData
			if secondary_weapon != null:
				var disc: int = _weapon_type_to_class_type(secondary_weapon.weapon_type)
				if disc != -1 and not disciplines.has(disc):
					disciplines.append(disc)
	if disciplines.is_empty() and is_instance_valid(class_component):
		disciplines.append(class_component.current_class)
	return disciplines


func _handle_sprite_change_on_server() -> void:
	if not is_instance_valid(level_component):
		return

	# Use the currently-wielded discipline, not the starting class — so a
	# Swordsman who's swapped to a bow stays an Archer sprite on level-up.
	var discipline: int = get_active_discipline()
	var current_level: int = level_component.level

	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(discipline, current_level)
	if sprite_frames:
		if BotManager.is_bot(player_id):
			# A bot's node may be missing on a client mid map-transition, so
			# route its sprite updates through MapManager (an autoload).
			MapManager.broadcast_player_appearance(player_id)
		else:
			# Pass the enum-key string so change_sprite_rpc resolves the same
			# way on every peer via ResourceManager.get_class_type_from_string.
			change_sprite_rpc.rpc(Constants.ClassType.find_key(discipline), current_level)

func change_to_map(new_map_id: String, spawn_point_name: String = ""):
	if not multiplayer.is_server():
		# Client requests map change from server
		# Send our local data to ensure the server has the absolute latest state before the swap
		var data_string: String = JSON.stringify(get_save_data())
		request_map_change_rpc.rpc_id(1, new_map_id, spawn_point_name, data_string)
	else:
		# Flush save before map change — the player node is freed during the transition,
		# so a debounced save would fire on an already-freed node and be silently skipped.
		# Bots skip this: PlayerManager.set_carried_state preserves their live state in
		# memory across the despawn/respawn, and at high bot counts every portal hop
		# firing a flush would saturate the save pool and freeze the server.
		if not username.is_empty() and SaveManager and not BotManager.is_bot(player_id):
			SaveManager.queue_save(username, "all", self)
			await SaveManager.flush_save(username)
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
		# Weapon mastery rides the "stats" update path since it feeds STR/DEX/
		# INT/LUK scaling in StatsComponent. The component returns a dict keyed
		# by lowercase discipline name (sword/bow/staff/dagger) with
		# {level, xp} entries.
		if is_instance_valid(weapon_mastery_component):
			data['weapon_mastery'] = weapon_mastery_component.save_mastery()
	
	if update_type == "all" or update_type == "inventory":
		if is_instance_valid(player_inventory):
			data['inventory'] = player_inventory.save_player_inventory()
	
	if update_type == "all" or update_type == "abilities":
		if is_instance_valid(ability_component):
			data['abilities'] = ability_component.save_abilities()
		
	if update_type == "all" or update_type == "buffs":
		if is_instance_valid(buff_component):
			data['buffs'] = buff_component.save_buffs()

	if update_type == "all":
		data['quests'] = QuestManager.save_quests(username)

	if update_type == "all" or update_type == "pets":
		# PetManager returns {pets: [...], summoned_pet_ids: [...]} —
		# merge both keys at the top level of the save payload (matches the
		# format named in docs/adr/0001-pet-system-architecture.md).
		data.merge(PetManager.get_save_data(username))

	return data


func _get_stats_data() -> Dictionary:
	return {
		'max_health': health_component.max_health if is_instance_valid(health_component) else 100,
		'current_health': health_component.current_health if is_instance_valid(health_component) else 100,
		'max_mana': mana_component.max_mana if is_instance_valid(mana_component) else 100,
		'current_mana': mana_component.current_mana if is_instance_valid(mana_component) else 100,
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
	
	#print("Loading data for ", data.get("username", "Unknown"))
	
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

	# Weapon mastery — must load BEFORE stats_component recalculates so the
	# mastery-driven STR/DEX/INT/LUK scaling has the right per-discipline
	# levels in hand. load_mastery toggles its own loading_mode internally to
	# suppress signal-driven recalcs; the final stats_changed.emit below picks
	# up the new totals.
	if is_instance_valid(weapon_mastery_component):
		var mastery_data = data.get("weapon_mastery", {})
		if mastery_data is Dictionary:
			weapon_mastery_component.load_mastery(mastery_data)

	if is_instance_valid(inventory_component):
		var inventory_data = data.get("inventory", {})
		if not inventory_data.is_empty():
			inventory_component.load_inventory(inventory_data)
		elif multiplayer.is_server() and data.get("level", 1) == 1:
			var disc := class_component.current_class if is_instance_valid(class_component) else Constants.ClassType.SWORD
			inventory_component.server_add_item(PlayerManager._starter_weapon_for(disc))

	if is_instance_valid(health_component):
		health_component.set_loading_mode(true)
		health_component.max_health = data.get("max_health", health_component.max_health)
		health_component.current_health = data.get("current_health", health_component.max_health)

	if is_instance_valid(mana_component):
		mana_component.max_mana = data.get("max_mana", mana_component.max_mana)
		mana_component.current_mana = data.get("current_mana", mana_component.max_mana)

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

	# Load quest progress
	var quest_data = data.get("quests", {})
	if not quest_data.is_empty():
		QuestManager.load_quests(username, quest_data)

	# Load pet roster (may be missing on legacy saves — defaults to empty).
	PetManager.load_pets(username, {
		PetManager.KEY_PETS: data.get("pets", []),
		PetManager.KEY_SUMMONED: data.get("summoned_pet_ids", []),
	})

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
	if BotManager.is_bot(peer_id):
		return

	# Wait a frame to ensure the new peer is ready.
	await get_tree().process_frame

	#print("Sending sprite data for player %d to new peer %d" % [player_id, peer_id])
	if is_instance_valid(level_component):
		# Use the currently-wielded discipline (NOT class_component.current_class)
		# so a newly-joining peer sees the player with whichever weapon they're
		# actually holding right now, not their starting-class default.
		var discipline: int = get_active_discipline()
		var current_level: int = level_component.level
		change_sprite_rpc.rpc_id(peer_id, Constants.ClassType.find_key(discipline), current_level)


#=============================================================================
# RPC (REMOTE PROCEDURE CALL) METHODS
#=============================================================================

# [SERVER -> CLIENT] Sets the loading state to suppress/enable saves during sync.
@rpc("authority", "call_remote", "reliable")
func set_loading_state_rpc(loading: bool) -> void:
	_is_loading_data = loading


# [SERVER-ONLY] Respawns the player at a designated point.
@rpc("any_peer", "call_local", "reliable")
func respawn() -> void:
	if not multiplayer.is_server() or _is_being_cleaned_up:
		return

	# The server authoritatively sets the respawn position from the current map's PlayerSpawn.
	var current_map_id = MapManager.get_player_map(player_id)
	if current_map_id != "":
		position = MapManager.get_spawn_position_for_map(current_map_id)
	else:
		position = MultiplayerManager.respawn_point
	# Clear any velocity accumulated while dead/falling so the player spawns at
	# rest — otherwise stale downward speed makes them tunnel through platforms.
	velocity = Vector2.ZERO
	do_attack = false
	do_jump = false
	do_drop = false
	# Reset drop-through state so a death mid-drop doesn't leave the next
	# life with a stale target_y far above the respawn point.
	_drop_through_active = false
	set_collision_mask_value(platform_layer, true)
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


# ============================================================================
# Weapon Swap (PR 3) — server-authoritative
# ============================================================================

const SWAP_TRANSITION_DURATION: float = 0.25
const SWAP_FX_PATH: String = "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png"
const SWAP_FX_FRAME_COUNT: int = 11
const SWAP_FX_FRAME_SIZE: int = 32
# Frame at which the sprite swap happens (visual peak of the flash).
const SWAP_FX_SPRITE_SWAP_FRAME: int = 3

## [CLIENT -> SERVER] Local player presses Tab. Forwarded by multiplayer_input.
## Validates and applies the swap; on success, the EquipmentComponent's
## swap_applied_rpc broadcasts the new active weapon to every peer (and our
## _on_active_weapon_changed handler runs the sprite swap + FX).
@rpc("any_peer", "call_local", "reliable")
func request_weapon_swap_server() -> void:
	if not multiplayer.is_server():
		return

	# Cleanup / death-state gate. A respawning player shouldn't swap mid-respawn.
	if _is_being_cleaned_up:
		return
	if is_instance_valid(health_component) and health_component.is_dead:
		return

	if not is_instance_valid(equipment_component):
		return

	var initiator: int = multiplayer.get_remote_sender_id()
	# When the host (peer 1) calls this locally, get_remote_sender_id() is 0.
	# Use the player_id so the denied-ping RPC has a real target.
	if initiator == 0:
		initiator = player_id

	equipment_component.try_perform_swap_server(initiator)


## Signal handler. Runs on every peer that mirrors this player. Triggers the
## sprite swap + transition FX. Sprite-swap timing is locked to frame 3 of
## the FX animation so the swap happens at the visual peak of the flash.
## PR 4 fix (2026-05-27): handles equipment changes that aren't a Tab-swap
## (e.g. user dragged a new weapon into the active slot). Triggers a sprite
## broadcast through the standard server pathway IF the wielded discipline
## actually changed. No transition FX / input lock — those are reserved for
## explicit swaps. Bare-hands fallback (no weapon equipped) reads through
## get_active_discipline()'s class_component fallback so the sprite never
## ends up "empty" — the player visually reverts to their starting-class
## sprite, which is the intended guard for the "no weapon equipped" case.
func _on_equipment_changed_refresh_sprite() -> void:
	if _is_being_cleaned_up:
		return
	if not multiplayer.is_server():
		return
	# Cheap call — the rpc/sprite resolution is idempotent if the discipline
	# didn't actually change. Don't try to gate this against the previous
	# value here; just re-emit and let the client overwrite with the same
	# sprite frames where appropriate.
	_handle_sprite_change_on_server()


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	if _is_being_cleaned_up:
		return

	# Persist the new active_weapon. The inventory bucket already serializes
	# equipment + active_weapon together (see InventoryComponent.save_inventory),
	# so queue an inventory save explicitly. The default `on_equipment_changed`
	# handler fires the "equipment" category, which today doesn't round-trip
	# in get_save_data — so we route through "inventory" for the swap.
	if multiplayer.is_server() and not _is_loading_data:
		_data_changed("inventory")

	# Spawn the transition FX on every peer that has this player node.
	_spawn_swap_transition_fx()

	# Schedule the sprite swap to land at the FX's visual peak.
	# Frame 3 of 11 frames at ~44fps (0.25s total) = ~0.068s.
	var swap_delay: float = SWAP_TRANSITION_DURATION * (float(SWAP_FX_SPRITE_SWAP_FRAME) / float(SWAP_FX_FRAME_COUNT))

	# Lock input for the full transition duration on the SERVER side only — the
	# server is authoritative over movement; the client mirrors anyway.
	if multiplayer.is_server():
		_lock_input_for_swap()

	get_tree().create_timer(swap_delay).timeout.connect(_apply_active_weapon_sprite)


## Locks input for the swap transition window on the server. Sets
## `_swap_input_locked` so `_update_input_from_synchronizer` zeros direction
## /jump/drop/attack each frame until the transition timer fires. Auto-clears
## via a one-shot create_timer connection.
func _lock_input_for_swap() -> void:
	if not multiplayer.is_server():
		return
	_swap_input_locked = true
	direction = 0
	do_attack = false
	do_jump = false
	do_drop = false
	# Auto-clear after the transition completes. The timer connection is
	# one-shot per Godot's create_timer contract — safe to wire as a fire-and-
	# forget. No `await` here so the sync-emit-await-hang trap is avoided.
	get_tree().create_timer(SWAP_TRANSITION_DURATION).timeout.connect(
		func() -> void:
			if is_instance_valid(self):
				_swap_input_locked = false
	)


## Resolves the active weapon's discipline and updates the AnimatedSprite2D
## frames. Runs on the same peers that see the FX. Reads through
## `active_weapon_data.weapon_type` and maps to the matching tier-1 sprite.
func _apply_active_weapon_sprite() -> void:
	if _is_being_cleaned_up:
		return
	if not is_instance_valid(equipment_component) or not is_instance_valid(animated_sprite):
		return
	if not is_instance_valid(level_component):
		return

	var weapon: WeaponData = equipment_component.active_weapon_data
	# If the active slot is empty (bare hands), fall back to the character's
	# current discipline so the sprite stays sensible.
	var discipline_class: int = -1
	if weapon != null:
		discipline_class = _weapon_type_to_class_type(weapon.weapon_type)
	if discipline_class == -1 and is_instance_valid(class_component):
		discipline_class = class_component.current_class

	if discipline_class == -1:
		return

	var frames: SpriteFrames = ResourceManager.get_sprite_for_level(discipline_class, level_component.level)
	if frames:
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")


static func _weapon_type_to_class_type(weapon_type: int) -> int:
	match weapon_type:
		Constants.WeaponType.SWORD:
			return Constants.ClassType.SWORD
		Constants.WeaponType.BOW:
			return Constants.ClassType.BOW
		Constants.WeaponType.STAFF:
			return Constants.ClassType.STAFF
		Constants.WeaponType.DAGGER:
			return Constants.ClassType.DAGGER
	return -1


## Spawns the one-shot transition FX at the player's chest position. Runs on
## every peer that has this player node (server included). Auto-frees when
## the animation finishes.
func _spawn_swap_transition_fx() -> void:
	# Skip for headless dedicated server, and skip for bots whose UI subtree
	# is freed — but DO render on the host (server + client in one tree) and
	# on every remote client that sees this player.
	if OS.has_feature("dedicated_server"):
		return

	if not is_instance_valid(animated_sprite):
		return

	var fx_texture: Texture2D = load(SWAP_FX_PATH)
	if fx_texture == null:
		return

	var fx_frames := SpriteFrames.new()
	fx_frames.add_animation("swap")
	fx_frames.set_animation_loop("swap", false)
	# 11 frames over 0.25s = 44 fps.
	fx_frames.set_animation_speed("swap", float(SWAP_FX_FRAME_COUNT) / SWAP_TRANSITION_DURATION)

	for i in range(SWAP_FX_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = fx_texture
		atlas.region = Rect2(i * SWAP_FX_FRAME_SIZE, 0, SWAP_FX_FRAME_SIZE, SWAP_FX_FRAME_SIZE)
		fx_frames.add_frame("swap", atlas)

	var fx_sprite := AnimatedSprite2D.new()
	fx_sprite.name = "WeaponSwapFX"
	fx_sprite.sprite_frames = fx_frames
	fx_sprite.position = Vector2(0, -16) # Roughly the player's chest.
	fx_sprite.z_index = 5
	add_child(fx_sprite)
	fx_sprite.play("swap")

	# Auto-free when the animation finishes. animation_finished is one-shot
	# per non-looping animation, so this fires exactly once.
	fx_sprite.animation_finished.connect(fx_sprite.queue_free)


# [SERVER -> CLIENTS] Broadcasts the sprite change to all clients.
@rpc("authority", "call_local", "reliable")
func change_sprite_rpc(_class_name: String, level: int) -> void:
	var class_type: int = ResourceManager.get_class_type_from_string(_class_name)
	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, level)
	#print("Sprite Frames:" + sprite_frames.resource_path)
	if sprite_frames:
		animated_sprite.sprite_frames = sprite_frames
		animated_sprite.play("idle")
	else:
		push_warning("Could not find sprite for %s level %d" % [_class_name, level])


# [CLIENT] Applies sprite frames for the given class/level. Used for bots,
# whose appearance is delivered via MapManager rather than the node-addressed
# change_sprite_rpc (a bot's node may be missing on a client mid-transition).
func apply_appearance(class_type: int, level: int) -> void:
	if is_instance_valid(class_component):
		class_component.current_class = class_type as Constants.ClassType
	var frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, level)
	if frames and is_instance_valid(animated_sprite):
		animated_sprite.sprite_frames = frames
		animated_sprite.play("idle")


# [CLIENT -> SERVER] Client requests to change their class.
@rpc("any_peer", "call_local", "reliable")
func change_class_request(new_class: int) -> void:
	if not multiplayer.is_server():
		return
	#print("Change Class Request")
	if is_instance_valid(class_component):
		class_component.change_class_rpc.rpc(new_class)
		_handle_sprite_change_on_server()


# [CLIENT -> SERVER] A new client requests the sprite states of all existing players.
@rpc("any_peer", "call_local", "reliable")
func request_all_sprite_states() -> void:
	if not multiplayer.is_server():
		return
	
	var requester_id: int = multiplayer.get_remote_sender_id()
	#print("Player %d requesting all sprite states" % requester_id)
	
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
			#print("  Syncing sprite for player %d to requester %d" % [other_player_id, requester_id])
			other_player._on_peer_connected(requester_id)


# [ALL PEERS] Sets the username for this player instance across all clients.
@rpc("any_peer", "call_local", "reliable")
func set_username(uname: String) -> void:
	username = uname
	if is_instance_valid(player_name_label):
		player_name_label.text = username


@rpc("authority", "call_local", "reliable")
func sync_dark_sight_visual(alpha: float) -> void:
	if is_instance_valid(animated_sprite):
		animated_sprite.modulate.a = alpha


@rpc("authority", "call_local", "reliable")
func sync_shadow_partner(active: bool) -> void:
	if multiplayer.is_server():
		return
	if active:
		if not get_node_or_null("ShadowPartnerClient"):
			var shadow := Node2D.new()
			shadow.name = "ShadowPartnerClient"
			var shadow_sprite := AnimatedSprite2D.new()
			shadow_sprite.name = "ShadowSprite"
			if is_instance_valid(animated_sprite) and animated_sprite.sprite_frames:
				shadow_sprite.sprite_frames = animated_sprite.sprite_frames
				shadow_sprite.offset = animated_sprite.offset
				shadow_sprite.scale = animated_sprite.scale
				shadow_sprite.position = animated_sprite.position
			shadow_sprite.modulate = Color(0.15, 0.05, 0.25, 0.6)
			shadow_sprite.z_index = -1
			shadow.add_child(shadow_sprite)
			add_child(shadow)
			shadow.position = Vector2(-10 * facing_direction, 0)
	else:
		var shadow := get_node_or_null("ShadowPartnerClient")
		if shadow:
			shadow.queue_free()


func _on_leveled_up_effect(_new_level: int) -> void:
	if _is_loading_data or _is_being_cleaned_up:
		return
	if not multiplayer.is_server():
		return
	# Broadcast to all players on the same map
	var map_node = MapManager.get_player_map_node(player_id)
	if map_node:
		var map_name: String = map_node.name.replace("Map_", "")
		var players_on_map: Array = MapManager.get_real_players_on_map(map_name)
		for peer_id in players_on_map:
			_play_levelup_effect.rpc_id(peer_id)
		# Also play on server if host
		if multiplayer.get_unique_id() == 1:
			_play_levelup_effect()
	else:
		_play_levelup_effect.rpc()


@rpc("authority", "call_local", "reliable")
func _play_levelup_effect() -> void:
	# Create a temporary GPUParticles2D for the level-up burst
	var particles := GPUParticles2D.new()
	particles.name = "LevelUpParticles"
	particles.position = Vector2(0, -12)
	particles.emitting = true
	particles.one_shot = true
	particles.amount = 24
	particles.lifetime = 0.8
	particles.explosiveness = 0.9

	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, -1, 0)
	mat.spread = 180.0
	mat.initial_velocity_min = 40.0
	mat.initial_velocity_max = 80.0
	mat.gravity = Vector3(0, 60, 0)
	mat.scale_min = 2.0
	mat.scale_max = 4.0
	mat.color = Color(1.0, 0.9, 0.2, 1.0)  # Golden yellow
	var color_ramp := Gradient.new()
	color_ramp.set_color(0, Color(1.0, 0.9, 0.2, 1.0))
	color_ramp.set_color(1, Color(1.0, 0.5, 0.0, 0.0))
	var color_texture := GradientTexture1D.new()
	color_texture.gradient = color_ramp
	mat.color_ramp = color_texture

	particles.process_material = mat
	add_child(particles)

	# Auto-cleanup after particles finish
	await get_tree().create_timer(1.5).timeout
	if is_instance_valid(particles):
		particles.queue_free()

@rpc("any_peer", "call_local", "reliable")
func request_map_change_rpc(new_map_id: String, spawn_point_name: String = "", _client_data_string: String = ""):
	"""Server receives map change request"""
	if not multiplayer.is_server():
		return

	var requester_id = multiplayer.get_remote_sender_id()
	#print("Player %d requesting map change to '%s' at spawn '%s'" % [requester_id, new_map_id, spawn_point_name])

	# Flush save before map change — the player node is freed during the transition,
	# so a debounced save would fire on an already-freed node and be silently skipped.
	if not username.is_empty() and SaveManager:
		SaveManager.queue_save(username, "all", self)
		await SaveManager.flush_save(username)

	# Change map through MapManager
	MapManager.request_map_change(requester_id, new_map_id, spawn_point_name)

## Apply camera shake effect. Only runs on the local player's camera.
func screen_shake(intensity: float = 4.0, duration: float = 0.2) -> void:
	if player_id != multiplayer.get_unique_id():
		return  # Only shake the local player's camera
	if not UserConfig.screen_shake_enabled:
		return
	if not is_instance_valid(camera):
		return
	var tween: Tween = create_tween()
	var shake_count: int = int(duration / 0.04)
	for i in range(shake_count):
		var offset := Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity))
		tween.tween_property(camera, "offset", offset, 0.02)
		tween.tween_property(camera, "offset", Vector2.ZERO, 0.02)
	tween.tween_property(camera, "offset", Vector2.ZERO, 0.02)



const BUBBLE_MAX_WIDTH := 95.0
const BUBBLE_MAX_HEIGHT := 120
const BUBBLE_MAX_CHARS := 80
const BUBBLE_FONT_SIZE := 14
const BUBBLE_Y_OFFSET := -20.0  # How far above origin to start the bubble
const BUBBLE_SCALE := 0.3
const BUBBLE_FONT := preload("res://assets/fonts/Inter.ttc")
var _active_chat_bubble: PanelContainer = null
var _active_emote_bubble: PanelContainer = null

func _build_bubble(text: String) -> PanelContainer:
	var display_text := text.substr(0, BUBBLE_MAX_CHARS)
	if text.length() > BUBBLE_MAX_CHARS:
		display_text = text.substr(0, BUBBLE_MAX_CHARS - 3) + "..."

	var label := Label.new()
	label.text = display_text
	label.add_theme_font_override("font", BUBBLE_FONT)
	label.add_theme_font_size_override("font_size", BUBBLE_FONT_SIZE)
	label.add_theme_color_override("font_color", Color.WHITE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size = Vector2.ZERO

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_bottom", 5)
	margin.add_child(label)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(margin)

	# Must be in the tree before get_minimum_size() returns real values
	add_child(panel)
	await get_tree().process_frame

	var natural_width := label.get_minimum_size().x + 16
	var bubble_width := minf(natural_width, BUBBLE_MAX_WIDTH)
	label.custom_minimum_size = Vector2(bubble_width, 0)
	if natural_width > BUBBLE_MAX_WIDTH:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	return panel


func _position_bubble(panel: PanelContainer) -> void:
	await get_tree().process_frame
	await get_tree().process_frame

	if panel.size.y > BUBBLE_MAX_HEIGHT:
		panel.custom_minimum_size.y = BUBBLE_MAX_HEIGHT
		panel.size.y = BUBBLE_MAX_HEIGHT

	# Apply scale first so position math accounts for the shrunken size
	panel.scale = Vector2(BUBBLE_SCALE, BUBBLE_SCALE)

	panel.position = Vector2(
		roundf(-panel.size.x * BUBBLE_SCALE / 2.0),
		roundf(BUBBLE_Y_OFFSET - panel.size.y * BUBBLE_SCALE)
	)

	panel.resized.connect(func():
		var clamped_height := minf(panel.size.y, BUBBLE_MAX_HEIGHT)
		panel.position = Vector2(
			roundf(-panel.size.x * BUBBLE_SCALE / 2.0),
			roundf(BUBBLE_Y_OFFSET - clamped_height * BUBBLE_SCALE)
		)
	)


func show_chat_bubble(message: String) -> void:
	if is_instance_valid(_active_chat_bubble):
		_active_chat_bubble.queue_free()
		_active_chat_bubble = null

	var panel := await _build_bubble(message)
	_active_chat_bubble = panel
	# No add_child here — _build_bubble already added it
	await _position_bubble(panel)

	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(panel):
		panel.queue_free()
	_active_chat_bubble = null


func show_emote_bubble(text: String) -> void:
	if is_instance_valid(_active_emote_bubble):
		_active_emote_bubble.queue_free()
		_active_emote_bubble = null

	var panel := await _build_bubble(text)
	panel.modulate = Color(1.0, 0.92, 0.6, 1.0)
	_active_emote_bubble = panel
	# No add_child here — _build_bubble already added it
	await _position_bubble(panel)

	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(panel):
		panel.queue_free()
	_active_emote_bubble = null
