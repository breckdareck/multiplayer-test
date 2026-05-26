class_name Pet
extends CharacterBody2D

## A summoned pet entity. Owner-bound, server-spawned, owner-client-authoritative
## on position. See docs/adr/0001-pet-system-architecture.md.
##
## Movement is platform-aware: gravity, walking, jumping to follow the owner
## up short platforms. When the owner gets clearly out of reach (rope/ladder
## travel, big drops), the pet teleports after a short grace period.

@export var sprite: AnimatedSprite2D
@export var bubble_label: Label
@export var event_bubble: Label
@export var summon_poof: CPUParticles2D
@export var collision_shape: CollisionShape2D

# ── Identity (assigned by PetManager.setup) ───────────────────────────────
var owner_peer_id: int = 0
var pet_uuid: String = ""
var pet_data: PetData = null
var owner_username: String = ""

# ── Movement state ────────────────────────────────────────────────────────
# FOLLOW mode uses hysteresis: don't start walking until the owner is more
# than FOLLOW_START_X away on X, don't stop until the gap shrinks below
# FOLLOW_STOP_X. This prevents the walk/idle flicker that happens when the
# owner walks at a speed close to the pet's. The pet targets the owner's
# position directly (no fixed-side offset), so it ends up trailing on
# whichever side it currently is, swapping naturally when the owner walks
# past it.
const FOLLOW_START_X: float = 70.0     # gap that triggers walking
const FOLLOW_STOP_X: float = 22.0      # gap at which we stop (acts as standoff)
const PICKUP_X_DISTANCE: float = 4.0   # walk onto the item's center before grabbing
const SAME_LEVEL_Y_DELTA: float = 64.0 # max Y diff to consider items "same platform"

enum PetMode { FOLLOW, LOOT }
var _mode: PetMode = PetMode.FOLLOW
var _loot_target_node: Node = null  # DroppedItem we're pursuing
var _facing_right: bool = true
var _is_following: bool = false  # FOLLOW-mode hysteresis state
var _leash_breach_timer: float = 0.0
var _has_pending_jump: bool = false
# Previous-frame owner state tracking so we can fire edge-triggered behaviors
# (jump-when-owner-jumps, pop-up-when-owner-exits-ladder) without re-firing
# every frame the state stays the same.
var _was_owner_climbing: bool = false
var _was_owner_jumping: bool = false
const CLIMB_EXIT_POP_PX: float = 16.0   # upward bias when owner finishes climbing
const TELEPORT_UP_BIAS_PX: float = 32.0  # upward bias on any teleport-to-owner

# Vertical-stuck detection — owner is on a higher platform and we're not
# gaining height. Tracks Y progress over a short grace; if none, teleport
# instead of pogo-jumping in place forever. Real platform pathing would need
# a nav graph; this is the practical fallback.
const VERTICAL_STUCK_MIN_GAP: float = 48.0    # owner this far above counts as "different platform"
const VERTICAL_STUCK_GRACE_SEC: float = 0.9   # how long to keep trying before teleporting
const VERTICAL_STUCK_PROGRESS_PX: float = 16.0  # upward movement that resets the timer
const VERTICAL_STUCK_GIVEUP_JUMP_SEC: float = 0.25  # stop height-jumping after this if no progress
var _vertical_stuck_timer: float = 0.0
var _vertical_stuck_y_anchor: float = 0.0

# ── Hunger display state (broadcast by server) ────────────────────────────
var current_hunger: float = 100.0
var max_hunger_display: float = 100.0
var is_hungry_state: bool = false
const LOW_HUNGER_FRACTION: float = 0.25

# ── Auto-loot scan (owner client only) ────────────────────────────────────
var _autoloot_accumulator: float = 0.0
const AUTOLOOT_SCAN_INTERVAL: float = 0.1

# Per-drop cooldown — when we fire a pickup RPC and the server rejects, the
# drop stays alive in the world. Without a cooldown the vacuum re-targets it
# next frame and spams the server. Successful pickups are filtered out by
# the COLLECTED state check instead, so this only delays *rejected* drops.
var _recently_tried_drops: Dictionary = {}  # drop.name -> Time.get_ticks_msec()
const PICKUP_RETRY_COOLDOWN_MS: int = 350

# Vacuum fires AT MOST one pickup RPC per VACUUM_FIRE_INTERVAL_MS, paced just
# faster than the server's AUTOLOOT_RATE_LIMIT_MS so RPCs don't get rejected
# for rate-limiting and clutter the recently-tried map. Sweep through a
# cluster runs at ~20 picks/sec.
const VACUUM_FIRE_INTERVAL_MS: int = 50
var _last_vacuum_fire_ms: int = 0

# Dwell at the drop before firing pickup, so the pet pauses on the item
# rather than instant-snapping the RPC. Cosmetic — gives a small "yoink"
# beat that reads better. Only triggers as a fallback; the vacuum pass below
# usually grabs the item before the pet reaches the precise pickup distance.
var _pickup_dwell_target: Node = null
var _pickup_dwell_start_ms: int = 0
const PICKUP_DWELL_MS: int = 200

# Vacuum: drops within this radius are picked up immediately on any frame,
# without changing mode or stopping. Lets the pet sweep through an item
# cluster in one pass instead of stopping at each drop. Tuned wider than
# PICKUP_X_DISTANCE so the pet "sucks up" items while walking past them.
const PICKUP_VACUUM_RADIUS: float = 36.0

# ── Auto-pot (owner-client only) ──────────────────────────────────────────
var _autopot_accumulator: float = 0.0
const AUTOPOT_TICK_INTERVAL: float = 0.2

# ── Juice (every peer) ────────────────────────────────────────────────────
var _idle_bounce_phase: float = 0.0
var _idle_bounce_amplitude: float = 1.5
var _event_bubble_tween: Tween = null
var _pulse_tween: Tween = null
var _sprite_base_scale: Vector2 = Vector2.ONE  # captured once; pulses always return here


func _ready() -> void:
	add_to_group("networked_entities")
	if is_instance_valid(sprite):
		_sprite_base_scale = sprite.scale
	_apply_pet_data()
	_refresh_bubble()
	if is_instance_valid(summon_poof):
		summon_poof.restart()
		summon_poof.emitting = true


func setup(pet_data_in: PetData, peer_owner: int, uuid: String, owner_name: String) -> void:
	pet_data = pet_data_in
	owner_peer_id = peer_owner
	pet_uuid = uuid
	owner_username = owner_name
	if pet_data:
		max_hunger_display = pet_data.max_hunger
		current_hunger = max_hunger_display
	if is_inside_tree():
		_apply_pet_data()
		_refresh_bubble()


func _apply_pet_data() -> void:
	if not pet_data or not sprite:
		return
	if pet_data.sprite_frames:
		sprite.sprite_frames = pet_data.sprite_frames
	_play_animation("idle")


func _process(delta: float) -> void:
	# Idle bounce — small visual oscillation. Runs on every peer.
	if is_instance_valid(sprite):
		_idle_bounce_phase += delta * 4.0
		var bounce_active := (sprite.animation == "idle") or is_hungry_state
		var bob := sin(_idle_bounce_phase) * _idle_bounce_amplitude if bounce_active else 0.0
		sprite.position.y = bob


func _physics_process(delta: float) -> void:
	# Only the owner's client computes motion. Other peers receive position via
	# the MultiplayerSynchronizer.
	if multiplayer.get_unique_id() != owner_peer_id:
		return

	# Apply gravity always (so the pet falls onto platforms after being placed).
	if not is_on_floor():
		velocity.y += (pet_data.gravity if pet_data else 900.0) * delta
	else:
		_has_pending_jump = false

	if is_hungry_state:
		# Hungry pets sit still where they are (gravity still keeps them on floor).
		velocity.x = 0.0
		_play_animation("idle")
		move_and_slide()
		return

	var owner_node := PlayerManager.get_player_node(owner_peer_id)
	if not is_instance_valid(owner_node):
		move_and_slide()
		return

	# Ride along while the owner is climbing a ladder/rope. Player state-machine
	# state isn't replicated to non-host clients, so we detect the climb by
	# geometry: the climb state snaps the owner's X to the ladder's center.
	var owner_climbing_now: bool = _owner_is_climbing(owner_node)
	if owner_climbing_now:
		global_position = owner_node.global_position
		velocity = Vector2.ZERO
		_facing_right = true
		_play_animation("idle")
		_has_pending_jump = false
		_leash_breach_timer = 0.0
		_is_following = false
		_mode = PetMode.FOLLOW
		_loot_target_node = null
		_pickup_dwell_target = null
		_was_owner_climbing = true
		move_and_slide()
		return

	# Owner just exited a climb (top or bottom). If exiting from above, the pet
	# was glued to the owner's climb-end position which is right at the platform
	# edge — physics often slides it off. Pop it up a few px so it lands on the
	# platform surface instead.
	if _was_owner_climbing:
		_was_owner_climbing = false
		global_position.y -= CLIMB_EXIT_POP_PX
		velocity = Vector2.ZERO

	# Periodic loot scan (decides whether to switch to LOOT mode).
	_autoloot_accumulator += delta
	if _autoloot_accumulator >= AUTOLOOT_SCAN_INTERVAL:
		_autoloot_accumulator = 0.0
		_refresh_loot_target(owner_node)

	# Pick the target position for this frame based on current mode.
	var target_pos: Vector2 = _resolve_target_position(owner_node)

	# Leash timeout (e.g., owner climbed a rope the pet can't follow).
	var dist_to_owner: float = global_position.distance_to(owner_node.global_position)
	var leash: float = pet_data.leash_radius if pet_data else 200.0
	if dist_to_owner > leash:
		_leash_breach_timer += delta
		var grace: float = pet_data.leash_teleport_grace_sec if pet_data else 1.5
		if _leash_breach_timer >= grace:
			_teleport_to_owner(owner_node)
			move_and_slide()
			return
	else:
		_leash_breach_timer = 0.0

	# Hard teleport if the owner moved very far above/below in one frame
	# (e.g., portal, instant respawn) — no point grinding the pet up.
	if absf(owner_node.global_position.y - global_position.y) > leash * 1.5:
		_teleport_to_owner(owner_node)
		move_and_slide()
		return

	# Vertical-stuck: owner is on a higher platform we can't reach by jumping.
	# Give the pet a short grace to find a route by walking, then teleport.
	var owner_y_gap: float = global_position.y - owner_node.global_position.y
	if owner_y_gap > VERTICAL_STUCK_MIN_GAP:
		if _vertical_stuck_timer == 0.0:
			_vertical_stuck_y_anchor = global_position.y
		_vertical_stuck_timer += delta
		var upward_progress: float = _vertical_stuck_y_anchor - global_position.y
		if upward_progress >= VERTICAL_STUCK_PROGRESS_PX:
			_vertical_stuck_y_anchor = global_position.y
			_vertical_stuck_timer = 0.0
		elif _vertical_stuck_timer >= VERTICAL_STUCK_GRACE_SEC:
			_teleport_to_owner(owner_node)
			_vertical_stuck_timer = 0.0
			move_and_slide()
			return
	else:
		_vertical_stuck_timer = 0.0

	# Horizontal motion — walk toward target X.
	var to_target_x: float = target_pos.x - global_position.x
	var speed: float = pet_data.walk_speed if pet_data else 120.0
	var should_walk: bool
	if _mode == PetMode.LOOT:
		should_walk = absf(to_target_x) > PICKUP_X_DISTANCE
	else:
		# Hysteresis around the owner: start at FOLLOW_START_X, stop at FOLLOW_STOP_X.
		var gap: float = absf(to_target_x)
		if _is_following:
			if gap <= FOLLOW_STOP_X:
				_is_following = false
		else:
			if gap > FOLLOW_START_X:
				_is_following = true
		should_walk = _is_following
	if should_walk:
		velocity.x = sign(to_target_x) * speed
		_facing_right = to_target_x >= 0.0
		_play_animation("walk")
	else:
		velocity.x = 0.0
		_play_animation("idle")

	# Jump in FOLLOW mode for three reasons:
	#  1. Owner is settled on a platform above us (jump_threshold_y higher).
	#     Owner must be grounded — otherwise the pet copies every player jump
	#     just because the player's Y briefly went up mid-air.
	#  2. We're trying to walk but a wall is blocking us (obstacle on the
	#     way to the owner). is_on_wall() reflects the previous frame's slide.
	#  3. Owner just entered the "jump" state. Edge-triggered — fires once at
	#     the start of the owner's jump, so the pet hops along in the same
	#     direction instead of staying on the ground while the player leaps.
	# After the brief give-up window, suppress height-jumping so we walk
	# horizontally toward the owner instead of bouncing in place.
	var owner_jumping_now: bool = _owner_state_name(owner_node) == "jump"
	var owner_jump_edge: bool = owner_jumping_now and not _was_owner_jumping
	_was_owner_jumping = owner_jumping_now

	if _mode == PetMode.FOLLOW and is_on_floor() and not _has_pending_jump:
		var jump_threshold: float = pet_data.jump_threshold_y if pet_data else 24.0
		var owner_grounded: bool = owner_node.has_method("is_on_floor") and owner_node.is_on_floor()
		var jump_for_height: bool = owner_grounded and target_pos.y < global_position.y - jump_threshold
		if _vertical_stuck_timer >= VERTICAL_STUCK_GIVEUP_JUMP_SEC:
			jump_for_height = false
		var jump_for_wall: bool = should_walk and is_on_wall()
		if jump_for_height or jump_for_wall or owner_jump_edge:
			velocity.y = pet_data.jump_velocity if pet_data else -360.0
			# Mirror the owner's jump direction when copying their jump. For the
			# height/wall paths we keep the horizontal velocity already computed
			# from the FOLLOW walk logic.
			if owner_jump_edge:
				var owner_dir: float = 0.0
				if "facing_direction" in owner_node:
					owner_dir = sign(float(owner_node.facing_direction))
				if owner_dir == 0.0 and "velocity" in owner_node and owner_node.velocity is Vector2:
					owner_dir = sign(owner_node.velocity.x)
				if owner_dir != 0.0:
					velocity.x = owner_dir * (pet_data.walk_speed if pet_data else 120.0)
					_facing_right = owner_dir >= 0.0
			_has_pending_jump = true

	_apply_facing()
	move_and_slide()

	# Vacuum pass: pick up any same-level drop within PICKUP_VACUUM_RADIUS this
	# frame, no targeting / no dwell. Lets the pet drive-by-sweep an item
	# cluster instead of stopping at each one.
	_vacuum_pickup_pass()

	# Pickup with a short dwell: pet stops at the item, waits PICKUP_DWELL_MS,
	# then fires the RPC. Reads better than the instant snap-pickup.
	if _mode == PetMode.LOOT and is_instance_valid(_loot_target_node):
		var loot_pos: Vector2 = _loot_target_node.global_position
		var at_item: bool = absf(loot_pos.x - global_position.x) <= PICKUP_X_DISTANCE \
				and absf(loot_pos.y - global_position.y) <= SAME_LEVEL_Y_DELTA
		if at_item:
			var now_ms: int = Time.get_ticks_msec()
			if _pickup_dwell_target != _loot_target_node:
				# Just arrived — start the dwell timer.
				_pickup_dwell_target = _loot_target_node
				_pickup_dwell_start_ms = now_ms
			elif now_ms - _pickup_dwell_start_ms >= PICKUP_DWELL_MS:
				# Dwell complete — fire the pickup.
				var drop_name: String = _loot_target_node.name
				_recently_tried_drops[drop_name] = now_ms
				PetManager.request_autoloot_server.rpc_id(1, pet_uuid, drop_name)
				_mode = PetMode.FOLLOW
				_loot_target_node = null
				_pickup_dwell_target = null
		else:
			# Wandered off the item before dwell completed (e.g., another drop
			# became closer and we're switching targets). Reset.
			_pickup_dwell_target = null

	# Auto-pot tick (independent of mode — happens while walking).
	_autopot_accumulator += delta
	if _autopot_accumulator >= AUTOPOT_TICK_INTERVAL:
		_autopot_accumulator = 0.0
		_try_autopot()


func _resolve_target_position(owner_node: Node) -> Vector2:
	if _mode == PetMode.LOOT and is_instance_valid(_loot_target_node):
		# Only chase loot on the same vertical level — if the player walked off
		# the platform, we'll follow them back via FOLLOW mode instead.
		if absf(_loot_target_node.global_position.y - global_position.y) <= SAME_LEVEL_Y_DELTA:
			return _loot_target_node.global_position
		# Drop pursuit if it became out-of-level (player moved away from it).
		_mode = PetMode.FOLLOW
		_loot_target_node = null
	# Aim directly at the owner; FOLLOW_STOP_X gives the natural standoff and
	# the pet ends up on whichever side it was already on.
	return owner_node.global_position


func _teleport_to_owner(owner_node: Node) -> void:
	# Bias the teleport upward by TELEPORT_UP_BIAS_PX so the pet spawns above
	# the platform surface and falls onto it with gravity. Without the bias
	# the pet lands exactly on the platform edge and physics slides it off
	# before the next frame.
	var offset := pet_data.follow_offset if pet_data else Vector2(-32.0, 0.0)
	offset.y -= TELEPORT_UP_BIAS_PX
	global_position = owner_node.global_position + offset
	velocity = Vector2.ZERO
	_leash_breach_timer = 0.0
	_mode = PetMode.FOLLOW
	_loot_target_node = null
	_has_pending_jump = false


func _owner_state_name(owner_node: Node) -> String:
	# Authoritative state from the player's state machine. State changes are
	# RPC'd to every peer (state_machine.gd:_set_state_rpc), so this is
	# accurate on host AND remote clients.
	var sm = owner_node.get("state_machine") if "state_machine" in owner_node else null
	if sm == null or not is_instance_valid(sm):
		return ""
	var cs = sm.current_state
	return cs.name if cs != null else ""


func _owner_is_climbing(owner_node: Node) -> bool:
	return _owner_state_name(owner_node) == "climb"


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-LOOT (owner client picks targets, server validates the actual pickup)
# ═══════════════════════════════════════════════════════════════════════════

func _refresh_loot_target(_owner_node: Node) -> void:
	if not pet_data:
		return
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		return
	if not PetManager.is_command_active(record, PetManager.CMD_MAGNET):
		_mode = PetMode.FOLLOW
		_loot_target_node = null
		return

	# Pick the FURTHEST valid same-level drop in range. Walking to it sweeps
	# the pet across every closer drop, and the vacuum pass collects them in
	# passing — one sweep instead of a hop-by-hop nearest-neighbor walk.
	var map_node := get_parent()
	if not map_node:
		return
	var best: Node = _scan_drops(map_node)
	var drops_container := map_node.get_node_or_null("ItemDrops")
	if drops_container:
		var alt: Node = _scan_drops(drops_container)
		if alt and (not best or global_position.distance_to(alt.global_position) > global_position.distance_to(best.global_position)):
			best = alt
	if best:
		_loot_target_node = best
		_mode = PetMode.LOOT
	else:
		_loot_target_node = null
		_mode = PetMode.FOLLOW


func _vacuum_pickup_pass() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _last_vacuum_fire_ms < VACUUM_FIRE_INTERVAL_MS:
		return
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		return
	if not PetManager.is_command_active(record, PetManager.CMD_MAGNET):
		return
	var map_node := get_parent()
	if not map_node:
		return
	# Pick the closest in-radius drop and fire ONE RPC. Throttling here keeps
	# the wire quiet and lets the server's rate limit do its job without
	# rejecting and burning the per-drop retry cooldown.
	var target: Node = _find_vacuum_target(map_node, now)
	var drops_container := map_node.get_node_or_null("ItemDrops")
	if drops_container:
		var alt: Node = _find_vacuum_target(drops_container, now)
		if alt and (not target or global_position.distance_to(alt.global_position) < global_position.distance_to(target.global_position)):
			target = alt
	if target == null:
		return
	_last_vacuum_fire_ms = now
	_recently_tried_drops[target.name] = now
	PetManager.request_autoloot_server.rpc_id(1, pet_uuid, target.name)
	# If we just fired on our LOOT target, clear it so the next scan retargets.
	if target == _loot_target_node:
		_mode = PetMode.FOLLOW
		_loot_target_node = null
		_pickup_dwell_target = null


func _find_vacuum_target(container: Node, now: int) -> Node:
	var best: Node = null
	var best_dist: float = PICKUP_VACUUM_RADIUS
	for child in container.get_children():
		if not (child is DroppedItem):
			continue
		var drop: DroppedItem = child
		if drop.current_state != DroppedItem.ItemState.SETTLED:
			continue
		if not drop.item_data:
			continue
		var tried: int = int(_recently_tried_drops.get(drop.name, 0))
		if tried > 0 and now - tried < PICKUP_RETRY_COOLDOWN_MS:
			continue
		if absf(drop.global_position.y - global_position.y) > SAME_LEVEL_Y_DELTA:
			continue
		var d: float = global_position.distance_to(drop.global_position)
		if d < best_dist:
			best_dist = d
			best = drop
	return best


func _scan_drops(container: Node) -> Node:
	# Returns the FURTHEST same-level drop within autoloot_radius. Walking
	# toward it lets the vacuum sweep every closer drop in passing.
	var best: Node = null
	var best_dist: float = 0.0
	var scan_radius: float = pet_data.autoloot_radius
	var now: int = Time.get_ticks_msec()
	for child in container.get_children():
		if not (child is DroppedItem):
			continue
		var drop: DroppedItem = child
		# Only chase SETTLED drops. POPPING / FALLING items are still in the
		# air arc and shouldn't be pursued (the pet would dart at the bounce
		# trajectory). COLLECTED items are already gone.
		if drop.current_state != DroppedItem.ItemState.SETTLED:
			continue
		if not drop.item_data:
			continue
		# Skip drops we recently tried to pick up — gives the server time to
		# respond and prevents ping-pong when a rejection happens.
		var tried: int = int(_recently_tried_drops.get(drop.name, 0))
		if tried > 0 and now - tried < PICKUP_RETRY_COOLDOWN_MS:
			continue
		# Magnet covers both items and coins — no type gate.
		if absf(drop.global_position.y - global_position.y) > SAME_LEVEL_Y_DELTA:
			continue
		var d: float = global_position.distance_to(drop.global_position)
		if d > scan_radius:
			continue
		if d > best_dist:
			best_dist = d
			best = drop
	return best


# ═══════════════════════════════════════════════════════════════════════════
# AUTO-POT
# ═══════════════════════════════════════════════════════════════════════════

func _try_autopot() -> void:
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		return
	if not PetManager.is_command_active(record, PetManager.CMD_AUTO_POT):
		return
	var owner_node := PlayerManager.get_player_node(owner_peer_id)
	if not is_instance_valid(owner_node):
		return

	var inv: Dictionary = record.get(PetManager.KEY_INVENTORY, {})
	var cfg: Dictionary = record.get(PetManager.KEY_AUTOPOT_CONFIG, {})

	# Pot slots are REFERENCES — non-empty item_id means "this potion type is
	# configured". The server consumes one from main inventory on each fire.
	var hp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_HP, {})
	if not (hp_slot.get("item_id", "") as String).is_empty():
		var hp_threshold: float = cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
		var hp_node = owner_node.get("health_component") if owner_node.has_method("get") else null
		if is_instance_valid(hp_node) and hp_node.max_health > 0:
			if float(hp_node.current_health) < float(hp_node.max_health) * hp_threshold:
				PetManager.request_autopot_server.rpc_id(1, pet_uuid, "hp")

	var mp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_MP, {})
	if not (mp_slot.get("item_id", "") as String).is_empty():
		var mp_threshold: float = cfg.get(PetManager.KEY_MP_THRESHOLD, 0.5)
		var mp_node = owner_node.get("mana_component") if owner_node.has_method("get") else null
		if is_instance_valid(mp_node) and mp_node.max_mana > 0:
			if float(mp_node.current_mana) < float(mp_node.max_mana) * mp_threshold:
				PetManager.request_autopot_server.rpc_id(1, pet_uuid, "mp")


# ═══════════════════════════════════════════════════════════════════════════
# DISPLAY / VISUAL FEEDBACK
# ═══════════════════════════════════════════════════════════════════════════

func _play_animation(anim_name: String) -> void:
	if not sprite or not sprite.sprite_frames:
		return
	var target_anim := anim_name
	if not sprite.sprite_frames.has_animation(target_anim):
		if anim_name == "walk" and sprite.sprite_frames.has_animation("patrol"):
			target_anim = "patrol"
		else:
			return
	if sprite.animation != target_anim or not sprite.is_playing():
		sprite.play(target_anim)


func _apply_facing() -> void:
	if not sprite:
		return
	sprite.flip_h = not _facing_right


func apply_hunger_state(hunger: float, max_hunger: float, hungry: bool) -> void:
	current_hunger = hunger
	max_hunger_display = max_hunger
	is_hungry_state = hungry
	_refresh_bubble()


func _refresh_bubble() -> void:
	if not is_instance_valid(bubble_label):
		return
	if is_hungry_state:
		bubble_label.text = "Feed me!"
		bubble_label.modulate = Color(1.0, 0.4, 0.4, 1.0)
		bubble_label.visible = true
		return
	if max_hunger_display > 0.0 and current_hunger / max_hunger_display <= LOW_HUNGER_FRACTION:
		bubble_label.text = "!"
		bubble_label.modulate = Color(1.0, 0.85, 0.3, 1.0)
		bubble_label.visible = true
		return
	bubble_label.visible = false


func play_event_visual(event_type: String) -> void:
	match event_type:
		"autoloot":
			_pulse_scale()
		"autopot_hp":
			_show_event_bubble("+HP", Color(1, 0.5, 0.5))
		"autopot_mp":
			_show_event_bubble("+MP", Color(0.5, 0.7, 1))
		"autobuff":
			_show_event_bubble("✨", Color(0.8, 0.6, 1))
		"fed":
			_show_event_bubble("Yum!", Color(0.8, 1, 0.6))
		"taught":
			_show_event_bubble("★", Color(1, 0.9, 0.3))


func _pulse_scale() -> void:
	if not is_instance_valid(sprite):
		return
	# Kill any in-flight pulse and snap back to base; otherwise rapid pickups
	# (vacuum sweep fires ~20/sec) compound — each new tween captures the
	# already-inflated scale as its "base" and the sprite grows unboundedly.
	if _pulse_tween and _pulse_tween.is_valid():
		_pulse_tween.kill()
	sprite.scale = _sprite_base_scale
	_pulse_tween = create_tween()
	_pulse_tween.tween_property(sprite, "scale", _sprite_base_scale * 1.25, 0.08).set_trans(Tween.TRANS_QUAD)
	_pulse_tween.tween_property(sprite, "scale", _sprite_base_scale, 0.18).set_trans(Tween.TRANS_QUAD)


func _show_event_bubble(text: String, color: Color) -> void:
	if not is_instance_valid(event_bubble):
		return
	event_bubble.text = text
	event_bubble.add_theme_color_override("font_color", color)
	event_bubble.modulate = Color(1, 1, 1, 1)
	event_bubble.visible = true
	if _event_bubble_tween and _event_bubble_tween.is_valid():
		_event_bubble_tween.kill()
	_event_bubble_tween = create_tween()
	_event_bubble_tween.tween_property(event_bubble, "position:y", event_bubble.position.y - 10.0, 0.5)
	_event_bubble_tween.parallel().tween_interval(0.4)
	_event_bubble_tween.tween_property(event_bubble, "modulate:a", 0.0, 0.3)
	_event_bubble_tween.tween_callback(func():
		event_bubble.visible = false
		event_bubble.position.y += 10.0
	)


func cleanup_before_removal() -> void:
	pet_data = null
