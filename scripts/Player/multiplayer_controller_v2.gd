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
@export var weapon_mastery_component: WeaponMasteryComponent
## PR 5: Sword discipline's signature combat system — combo points built
## by basic-attack hits and consumed by Slash for amplified damage.
## See scripts/Components/sword_combo.gd.
@export var sword_combo_component: SwordComboComponent
## Bow discipline's signature combat system — MOMENTUM. A gauge that fills on
## every landed bow hit and decays when you stop firing; while up it ramps ALL
## bow damage (combat.calculate_ability_damage) and fire-rate (attack.gd).
## See scripts/Components/bow_momentum.gd.
@export var bow_momentum_component: BowMomentumComponent
## PR 7: Staff discipline's signature combat system — the active element stance
## (FIRE/ICE/LIGHTNING) cycled by WeaponSignature. See scripts/Components/staff_element.gd.
## (Export added alongside Shadowmeld: player.tscn already wired this NodePath but
## the property declaration was missing, so player.staff_element_component / the
## "staff_cycle_element" input path resolved to null.)
@export var staff_element_component: StaffElementComponent
## PR 7: Dagger discipline's signature combat system — Shadowmeld stealth toggled
## by WeaponSignature; the next dagger hit from stealth is an ambush.
## See scripts/Components/shadowmeld.gd.
@export var shadowmeld_component: ShadowmeldComponent
## PR (candidate 3): owns ALL sprite/appearance application — the single apply
## path, the swap-transition FX, and the sprite-state RPCs. See
## scripts/Components/appearance.gd.
@export var appearance_component: AppearanceComponent
@export var player_inventory: PlayerInventory
@export var inventory_component: InventoryComponent
@export var equipment_component: EquipmentComponent
@export var ability_component: AbilityComponent
@export var buff_component: BuffComponent

@export_category("UI")
# ADR 0009 Stage B: the HUD (PlayerHUD subtree) was lifted into the persistent
# LocalPlayerUI layer, so the body no longer holds a ref to it. player_name_label
# is the world-space overhead name (PlayerWorldHUD), which STAYS on the body.
@export var player_name_label: RichTextLabel


var username: String = ""
var _current_party_id: int = -1

## Map ids this character has set foot in — drives the world map's fog-of-war
## (reveal on first visit). Server-authoritative: the server appends on each map
## change (see MapManager) and it rides the normal save; the client receives it
## via load data and augments it live from its own current map.
var visited_maps: Array = []

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

## The enemy this character most recently DAMAGED + when (ticks ms). Players have
## no explicit target lock (they swing in a direction), so this is the proxy for
## "what I'm fighting" — party bots read it via get_recent_combat_target() to
## focus-fire a human teammate's target instead of scattering. Set in
## combat._execute_hit; goes stale after RECENT_TARGET_WINDOW_MS.
var recent_combat_target: Node = null
var recent_combat_target_ms: int = 0
const RECENT_TARGET_WINDOW_MS: int = 3000


## Returns the enemy this character damaged within the last few seconds, or null
## if none/stale. Used by party bots for focus-fire.
func get_recent_combat_target() -> Node:
	if not is_instance_valid(recent_combat_target):
		return null
	if Time.get_ticks_msec() - recent_combat_target_ms > RECENT_TARGET_WINDOW_MS:
		return null
	return recent_combat_target

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
## Set by MapManager around a map-change reparent (ADR 0008) so _exit_tree skips
## cleanup while the live node is moved between map subtrees.
var _reparenting: bool = false
var _is_loading_data: bool = false
## PR 3: server-side gate for the weapon-swap transition window. While true,
## input flags are zeroed in _update_input_from_synchronizer so the player
## can't act mid-flash. Re-enabled when the transition timer fires.
var _swap_input_locked: bool = false
var _context_menu: PlayerContextMenu

## The weapon-signature components (sword combo / bow momentum / staff element /
## dagger shadowmeld), collected once at _ready by scanning the Components node
## for WeaponSignatureComponent children. Notified as a group on weapon-state
## changes and on death — adding a fifth signature needs no edits here. See
## scripts/Components/weapon_signature.gd.
var _weapon_signatures: Array = []

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

	# Collect the weapon-signature components before signal wiring, so the death
	# hook and weapon-state notifications have the full set in hand.
	_collect_weapon_signatures()

	if not _is_bot and multiplayer.get_unique_id() == player_id:
		ChatManager.register_local_player(self)
		# Request the sprite states of all other players from the server.
		if is_instance_valid(appearance_component):
			appearance_component.request_all_sprite_states.rpc_id(SERVER_ID)

	# Server-specific setup
	if multiplayer.is_server():
		# Handle sprite change on initial spawn
		await get_tree().process_frame
		if is_instance_valid(appearance_component):
			appearance_component.refresh_on_server()

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
		# Mount in the persistent LocalPlayerUI (ADR 0009 Stage B) — falls back to
		# /root if it isn't up yet.
		var moveable_container = MapManager.get_local_ui_moveable_windows()
		if is_instance_valid(moveable_container):
			moveable_container.add_child(_context_menu)
		else:
			get_tree().root.add_child(_context_menu)

	_context_menu.show_for_target(best_target.player_id, event.global_position)
	return true


func _exit_tree():
	# During a map-change REPARENT (ADR 0008) the node leaves the old map's tree
	# and re-enters the new map's tree without being freed — skip cleanup, which
	# would brick the live node (disconnect signals, halt processing). MapManager
	# sets/clears this flag around the reparent.
	if _reparenting:
		return
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

## Scans the Components node for every WeaponSignatureComponent child and caches
## them. Detection is duck-typed (has_method) as well as type-checked so it works
## even before the editor has registered the base class globally. A fifth
## signature dropped under Components is picked up automatically — no edits here.
func _collect_weapon_signatures() -> void:
	_weapon_signatures.clear()
	var comps := get_node_or_null("Components")
	if comps == null:
		return
	for child in comps.get_children():
		if child is WeaponSignatureComponent or child.has_method("signature_discipline"):
			_weapon_signatures.append(child)


## Server-only. Tells every weapon signature the wielded-weapon state changed so
## each can apply its own deactivation rule (sword combo clears when no sword is
## equipped, bow Momentum / dagger Shadowmeld clear when no longer wielded).
## Called on Tab-swap and on any equipment edit.
func _notify_signatures_weapon_state_changed() -> void:
	if not multiplayer.is_server():
		return
	var active: int = get_active_discipline()
	var equipped: Array = get_equipped_disciplines()
	for sig in _weapon_signatures:
		if is_instance_valid(sig):
			sig.on_weapon_state_changed(active, equipped)


## Server-only. Tells every weapon signature the owner died so each can clear
## volatile state that shouldn't survive death (bow Momentum, dagger Shadowmeld;
## sword combo and staff element deliberately persist).
func _notify_signatures_owner_died() -> void:
	if not multiplayer.is_server():
		return
	for sig in _weapon_signatures:
		if is_instance_valid(sig):
			sig.on_owner_died()


func _setup_signals() -> void:
	# Connect component signals to handle game logic and data saving.
	# These should run on both Client (to trigger RPC save) and Server (to save directly).
	if level_component:
		# experience rides the lightweight "stats" save; a level-up can shift
		# points/stats/abilities, so it triggers a full "all" save. (Previously
		# each was also wired to a no-arg _data_changed(), double-saving.)
		level_component.experience_changed.connect(func(_c, _e): _data_changed("stats"))
		level_component.leveled_up.connect(_on_leveled_up_effect)
		level_component.leveled_up.connect(func(_l): _data_changed("all")) # Level up might affect everything (points, stats)
		level_component.leveled_up.connect(func(new_level):
			if multiplayer.is_server() and not _is_loading_data:
				QuestManager.record_level_up(username, new_level)
		)
		if multiplayer.is_server() and is_instance_valid(appearance_component):
			level_component.leveled_up.connect(appearance_component.refresh_on_server.unbind(1))
	
	if health_component:
		health_component.health_changed.connect(func(_c, _m): _data_changed("stats"))
		# Weapon signatures that shouldn't survive death (bow Momentum, dagger
		# Shadowmeld) reset through the unified WeaponSignature interface — each
		# signature decides for itself in on_owner_died(). died emits on the
		# server (HealthComponent.die). See scripts/Components/weapon_signature.gd.
		if multiplayer.is_server():
			health_component.died.connect(func(_killer): _notify_signatures_owner_died())

	if ability_component:
		ability_component.ability_leveled_up.connect(func(_a, _l): _data_changed("abilities"))
		ability_component.ability_points_changed.connect(func(_k, _p): _data_changed("abilities"))
		ability_component.ability_learned.connect(func(_a): _data_changed("abilities"))
		# ADR 0009 Stage B: per-weapon hotbar edits/swaps persist via this signal
		# (the hotbar left the body, so the server can't read it directly).
		ability_component.hotbar_bindings_changed.connect(func(): _data_changed("abilities"))

	if inventory_component:
		inventory_component.inventory_saved.connect(func(_inv): _data_changed("inventory"))
		
	if buff_component:
		buff_component.buff_applied.connect(func(_b, _d): _data_changed("buffs"))
		buff_component.buff_removed.connect(func(_b): _data_changed("buffs"))
		buff_component.buff_refreshed.connect(func(_b, _d): _data_changed("buffs"))

	if equipment_component:
		# Equipment is serialized inside the inventory save bucket, so persist
		# equipment changes via "inventory" (there is no standalone "equipment"
		# producer in get_save_data — a separate category saved an empty payload).
		equipment_component.on_equipment_changed.connect(func(): _data_changed("inventory"))
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

	if weapon_mastery_component:
		# Persist the primary discipline (set at spawn) so it survives the next
		# spawn / login. character_type rides in the "stats" save bucket, which
		# the backend maps onto the Player.character_class column.
		weapon_mastery_component.primary_discipline_changed.connect(func(_d): _data_changed("stats"))

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
	# ADR 0009 Stage B: the HUD (PlayerHUD + GameMenu/QuestTracker/ZoneBanner +
	# mobile controls) moved to the persistent LocalPlayerUI layer, which binds
	# itself on MapManager.local_player_changed. The body keeps ONLY its world
	# camera here.
	var cam: Camera2D = $Camera2D

	if multiplayer.get_unique_id() == player_id:
		cam.make_current()
		_apply_map_camera_bounds(cam)
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


## The "I am my weapon" identity lookups now LIVE on WeaponMasteryComponent —
## the single owner of weapon identity (ADR-0004). These two methods are thin
## forwarders kept so the many duck-typed callers (UI widgets, combat, ability,
## state machine, MapManager-driven refresh) that ask `player.get_active_discipline()`
## keep working unchanged. New code may call `weapon_mastery_component` directly.
func get_active_discipline() -> int:
	if is_instance_valid(weapon_mastery_component):
		return weapon_mastery_component.get_active_discipline()
	return Constants.ClassType.SWORD


func get_equipped_disciplines() -> Array[int]:
	if is_instance_valid(weapon_mastery_component):
		return weapon_mastery_component.get_equipped_disciplines()
	var fallback: Array[int] = [Constants.ClassType.SWORD]
	return fallback


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
	# Record wherever the player currently is for world-map fog-of-war. Every
	# stats/all save (incl. the snapshot taken on each map change) thus captures
	# the maps they've stood in; the client reveals instantly from its live map.
	if multiplayer.is_server():
		mark_map_visited(MapManager.get_player_map(player_id))

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

	if update_type == "all" or update_type == "quests":
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
		'last_map': MapManager.get_player_map(player_id) if multiplayer.is_server() else MapManager.current_map_id,
		'character_type': weapon_mastery_component.primary_discipline if is_instance_valid(weapon_mastery_component) else 0,
		'attribute_points': stats_component.save_attributes() if is_instance_valid(stats_component) else {},
		'visited_maps': visited_maps,
	}


## Server records that this character has now been to `map_id` (world-map
## fog-of-war). Appended to the save on the next debounce.
func mark_map_visited(map_id: String) -> void:
	if map_id == "" or map_id in visited_maps:
		return
	visited_maps.append(map_id)


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

	var loaded_visited = data.get("visited_maps", [])
	if loaded_visited is Array:
		visited_maps = loaded_visited.duplicate()

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
			var disc := weapon_mastery_component.primary_discipline if is_instance_valid(weapon_mastery_component) else Constants.ClassType.SWORD
			@warning_ignore("static_called_on_instance")
			inventory_component.server_add_item(PlayerManager._starter_weapon_for(disc))

	if is_instance_valid(health_component):
		health_component.set_loading_mode(true)
		health_component.max_health = data.get("max_health", health_component.max_health)
		health_component.current_health = data.get("current_health", health_component.max_health)

	if is_instance_valid(mana_component):
		mana_component.set_loading_mode(true)
		mana_component.max_mana = data.get("max_mana", mana_component.max_mana)
		mana_component.current_mana = data.get("current_mana", mana_component.max_mana)

	if is_instance_valid(ability_component):
		var ability_data = data.get("abilities", {})
		if not ability_data.is_empty():
			ability_component.load_abilities(ability_data)
		# PR 8 (2026-05-31): fresh-character bootstrap. No-op for any returning
		# character (guarded by "no mastery, no spent points" check inside).
		# Bumps chosen discipline to mastery 1 so the player gets 1 ability
		# point to spend at character creation — replaces the old free
		# discipline starter ability.
		ability_component.bootstrap_fresh_character_if_needed()

	if is_instance_valid(level_component):
		level_component.set_block_signals(false)
		level_component.leveled_up.emit(level_component.level)
		level_component.experience_changed.emit(level_component.experience, level_component.get_exp_to_next_level())

	# PR 7: load allocated attribute points (or default-allocate to the starting
	# discipline's ratio for un-migrated characters) before the final recalc.
	if is_instance_valid(stats_component):
		stats_component.load_attributes(data.get("attribute_points", {}))
		stats_component.reconcile_attribute_points(true)

	if is_instance_valid(stats_component):
		stats_component.set_block_signals(false)
		stats_component.stats_changed.emit()
	
	if is_instance_valid(ability_component):
		ability_component.reconnect_level_signals()
		ability_component.set_loading_mode(false)
		# PR 8 fix: bootstrap_fresh_character_if_needed() above emits
		# mastery_level_changed while the point-grant signal was disconnected
		# (disconnect_level_signals ran at the top of this load), so the fresh
		# character's first ability point never lands via the live pathway. And
		# reconcile_ability_points() normally only runs inside load_abilities,
		# which is skipped for fresh characters (empty ability data). Run the
		# reconcile here unconditionally: it recomputes each discipline's pool as
		# granted(mastery_level) - spent, granting the bootstrap point and
		# self-healing any save that drifted (incl. characters already saved in
		# the broken 0-point state).
		ability_component.reconcile_ability_points()

	if is_instance_valid(health_component):
		health_component.set_loading_mode(false)
		health_component.health_changed.emit(health_component.current_health, health_component.max_health)

	if is_instance_valid(mana_component):
		mana_component.set_loading_mode(false)
		mana_component.mana_changed.emit(mana_component.current_mana, mana_component.max_mana)
		
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
	# Bots persist via SaveManager's 60s auto-save safety net ONLY — they don't
	# need an event-driven save on every health tick. Without this guard, 4+ bots
	# fighting each queue a "stats" save ~2x/sec (health_changed -> _data_changed),
	# which floods the save pipeline and makes real players' saves / map transfers /
	# spawns slow. Their earned state still persists every AUTO_SAVE_INTERVAL.
	if BotManager.is_bot(player_id):
		return
	# Server: queue a debounced save through SaveManager
	if username and SaveManager:
		SaveManager.queue_save(username, update_type, self)


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


# ============================================================================
# Weapon Swap (PR 3) — server-authoritative
# ============================================================================

## Swap-transition window. Drives the server-side input lock here AND is passed
## to AppearanceComponent.play_swap_transition for the FX + sprite-swap timing.
const SWAP_TRANSITION_DURATION: float = 0.25

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
## get_active_discipline()'s primary-discipline fallback so the sprite never
## ends up "empty" — the player visually reverts to their primary-discipline
## sprite, which is the intended guard for the "no weapon equipped" case.
func _on_equipment_changed_refresh_sprite() -> void:
	if _is_being_cleaned_up:
		return
	if not multiplayer.is_server():
		return
	# Notify every weapon signature of the equipment change — sword combo (resets
	# when neither slot is a sword), bow Momentum, and dagger Shadowmeld each apply
	# their own deactivation rule via on_weapon_state_changed.
	_notify_signatures_weapon_state_changed()
	# Cheap call — the sprite resolution is idempotent if the discipline didn't
	# actually change. Don't try to gate this against the previous value here;
	# just re-broadcast and let the client overwrite with the same frames.
	if is_instance_valid(appearance_component):
		appearance_component.refresh_on_server()


func _on_active_weapon_changed(_active_weapon: String, _active_item: ItemData) -> void:
	if _is_being_cleaned_up:
		return

	# Notify every weapon signature that the wielded weapon changed; each one
	# resets its own volatile state if its discipline just went inactive (bow
	# Momentum, dagger Shadowmeld). Server-guarded inside the helper.
	_notify_signatures_weapon_state_changed()

	# Persist the new active_weapon. The inventory bucket serializes equipment +
	# active_weapon together (see InventoryComponent.save_inventory). A Tab-swap
	# fires active_weapon_changed WITHOUT on_equipment_changed, so queue the
	# inventory save here explicitly.
	if multiplayer.is_server() and not _is_loading_data:
		_data_changed("inventory")

	# Lock input for the full transition duration on the SERVER side only — the
	# server is authoritative over movement; the client mirrors anyway. The input
	# lock stays on the body (it's an input concern); the swap VISUALS belong to
	# AppearanceComponent.
	if multiplayer.is_server():
		_lock_input_for_swap()

	# Appearance owns the swap visuals: spawn the transition FX on every peer that
	# has this player node and swap the sprite at the FX's visual peak.
	if is_instance_valid(appearance_component):
		appearance_component.play_swap_transition(SWAP_TRANSITION_DURATION)


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


# [CLIENT] Forwarder: appearance application lives on AppearanceComponent. Kept
# so MapManager (bot appearance delivery) can keep calling node.apply_appearance.
func apply_appearance(class_type: int, level: int) -> void:
	if is_instance_valid(appearance_component):
		appearance_component.apply_appearance(class_type, level)


# [ALL PEERS] Sets the username for this player instance across all clients.
@rpc("any_peer", "call_local", "reliable")
func set_username(uname: String) -> void:
	username = uname
	if is_instance_valid(player_name_label):
		player_name_label.text = ("Lv." + str(level_component.level)) + " " + username


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
	panel.z_index += 2
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


func show_emote_bubble(text: String, icon_path: String = "") -> void:
	if is_instance_valid(_active_emote_bubble):
		_active_emote_bubble.queue_free()
		_active_emote_bubble = null

	# Pixel-art emote icon (ADR 0012) when one exists; the text form is the
	# fallback for emotes without generated art.
	var panel: PanelContainer
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		panel = await _build_emote_icon_bubble(icon_path)
	else:
		panel = await _build_bubble(text)
		panel.modulate = Color(1.0, 0.92, 0.6, 1.0)
	_active_emote_bubble = panel
	# No add_child here — the builders already added it
	await _position_bubble(panel)

	await get_tree().create_timer(3.0).timeout
	if is_instance_valid(panel):
		panel.queue_free()
	_active_emote_bubble = null


## An overhead bubble holding a pixel emote icon instead of text. Same panel
## styling and positioning contract as _build_bubble.
func _build_emote_icon_bubble(icon_path: String) -> PanelContainer:
	var icon := TextureRect.new()
	icon.texture = load(icon_path)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size = Vector2(28, 28)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 3)
	margin.add_theme_constant_override("margin_bottom", 3)
	margin.add_child(icon)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.6)
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = Color(1.0, 1.0, 1.0, 0.15)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", style)
	panel.add_child(margin)

	# Must be in the tree before size math (same contract as _build_bubble).
	add_child(panel)
	await get_tree().process_frame
	return panel
