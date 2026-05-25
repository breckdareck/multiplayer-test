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
const ARRIVE_X_DISTANCE: float = 6.0   # close enough to "stop following" the owner
const PICKUP_X_DISTANCE: float = 4.0   # walk onto the item's center before grabbing
const SAME_LEVEL_Y_DELTA: float = 64.0 # max Y diff to consider items "same platform"

enum PetMode { FOLLOW, LOOT }
var _mode: PetMode = PetMode.FOLLOW
var _loot_target_node: Node = null  # DroppedItem we're pursuing
var _facing_right: bool = true
var _leash_breach_timer: float = 0.0
var _has_pending_jump: bool = false

# ── Hunger display state (broadcast by server) ────────────────────────────
var current_hunger: float = 100.0
var max_hunger_display: float = 100.0
var is_hungry_state: bool = false
const LOW_HUNGER_FRACTION: float = 0.25

# ── Auto-loot scan (owner client only) ────────────────────────────────────
var _autoloot_accumulator: float = 0.0
const AUTOLOOT_SCAN_INTERVAL: float = 0.1

# ── Auto-pot (owner-client only) ──────────────────────────────────────────
var _autopot_accumulator: float = 0.0
const AUTOPOT_TICK_INTERVAL: float = 0.2

# ── Juice (every peer) ────────────────────────────────────────────────────
var _idle_bounce_phase: float = 0.0
var _idle_bounce_amplitude: float = 1.5
var _event_bubble_tween: Tween = null


func _ready() -> void:
	add_to_group("networked_entities")
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

	# Horizontal motion — walk toward target X.
	var to_target_x: float = target_pos.x - global_position.x
	var speed: float = pet_data.walk_speed if pet_data else 120.0
	var arrive: float = PICKUP_X_DISTANCE if _mode == PetMode.LOOT else ARRIVE_X_DISTANCE
	if absf(to_target_x) > arrive:
		velocity.x = sign(to_target_x) * speed
		_facing_right = to_target_x >= 0.0
		_play_animation("walk")
	else:
		velocity.x = 0.0
		_play_animation("idle")

	# Jump if the target is above us and we're standing on ground.
	if is_on_floor() and not _has_pending_jump:
		var jump_threshold: float = pet_data.jump_threshold_y if pet_data else 24.0
		if target_pos.y < global_position.y - jump_threshold:
			velocity.y = pet_data.jump_velocity if pet_data else -360.0
			_has_pending_jump = true

	_apply_facing()
	move_and_slide()

	# Trigger pickup if we've reached a loot target.
	if _mode == PetMode.LOOT and is_instance_valid(_loot_target_node):
		var loot_pos: Vector2 = _loot_target_node.global_position
		if absf(loot_pos.x - global_position.x) <= PICKUP_X_DISTANCE \
				and absf(loot_pos.y - global_position.y) <= SAME_LEVEL_Y_DELTA:
			PetManager.request_autoloot_server.rpc_id(1, pet_uuid, _loot_target_node.name)
			_mode = PetMode.FOLLOW
			_loot_target_node = null

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
	# Default: follow owner with the configured offset.
	var offset := pet_data.follow_offset if pet_data else Vector2(-32.0, 0.0)
	return owner_node.global_position + offset


func _teleport_to_owner(owner_node: Node) -> void:
	global_position = owner_node.global_position + (pet_data.follow_offset if pet_data else Vector2(-32.0, 0.0))
	velocity = Vector2.ZERO
	_leash_breach_timer = 0.0
	_mode = PetMode.FOLLOW
	_loot_target_node = null
	_has_pending_jump = false


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

	# Always pick the closest valid same-level drop, every scan. This prevents
	# the pet from stalling on a stale target while a newer/closer drop is
	# available, and re-engages immediately after a drop is collected.
	var map_node := get_parent()
	if not map_node:
		return
	var best: Node = _scan_drops(map_node)
	var drops_container := map_node.get_node_or_null("ItemDrops")
	if drops_container:
		var alt: Node = _scan_drops(drops_container)
		if alt and (not best or global_position.distance_to(alt.global_position) < global_position.distance_to(best.global_position)):
			best = alt
	if best:
		_loot_target_node = best
		_mode = PetMode.LOOT
	else:
		_loot_target_node = null
		_mode = PetMode.FOLLOW


func _scan_drops(container: Node) -> Node:
	var best: Node = null
	var best_dist: float = pet_data.autoloot_radius
	for child in container.get_children():
		if not (child is DroppedItem):
			continue
		var drop: DroppedItem = child
		if drop.current_state == DroppedItem.ItemState.COLLECTED:
			continue
		if not drop.item_data:
			continue
		# Magnet covers both items and coins — no type gate.
		if absf(drop.global_position.y - global_position.y) > SAME_LEVEL_Y_DELTA:
			continue
		var d: float = global_position.distance_to(drop.global_position)
		if d < best_dist:
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

	var hp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_HP, {})
	if not hp_slot.is_empty() and int(hp_slot.get("stack", 0)) > 0:
		var hp_threshold: float = cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
		var hp_node = owner_node.get("health_component") if owner_node.has_method("get") else null
		if is_instance_valid(hp_node) and hp_node.max_health > 0:
			if float(hp_node.current_health) < float(hp_node.max_health) * hp_threshold:
				PetManager.request_autopot_server.rpc_id(1, pet_uuid, "hp")

	var mp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_MP, {})
	if not mp_slot.is_empty() and int(mp_slot.get("stack", 0)) > 0:
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
	var base: Vector2 = sprite.scale
	var tween := create_tween()
	tween.tween_property(sprite, "scale", base * 1.25, 0.08).set_trans(Tween.TRANS_QUAD)
	tween.tween_property(sprite, "scale", base, 0.18).set_trans(Tween.TRANS_QUAD)


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
