class_name Pet
extends Node2D

## A summoned pet entity. Owner-bound, server-spawned, owner-client-authoritative
## on position. See docs/adr/0001-pet-system-architecture.md.

@export var sprite: AnimatedSprite2D
@export var bubble_label: Label
@export var event_bubble: Label
@export var summon_poof: CPUParticles2D

# ── Identity (assigned by PetManager.setup) ───────────────────────────────
var owner_peer_id: int = 0
var pet_uuid: String = ""
var pet_data: PetData = null
var owner_username: String = ""

# ── Position / animation state (owner client only) ────────────────────────
var _facing_right: bool = true
const ARRIVE_DISTANCE: float = 6.0

# ── Hunger display state (broadcast by server) ────────────────────────────
var current_hunger: float = 100.0
var max_hunger_display: float = 100.0
var is_hungry_state: bool = false
const LOW_HUNGER_FRACTION: float = 0.25

# ── Auto-loot (owner-client only) ─────────────────────────────────────────
var _autoloot_accumulator: float = 0.0
const AUTOLOOT_TICK_INTERVAL: float = 0.1

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
	# Summon poof — every peer plays it locally when the pet appears.
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
	# Idle bounce — small Y oscillation when not actively moving. Cosmetic;
	# runs on every peer.
	if is_instance_valid(sprite):
		_idle_bounce_phase += delta * 4.0
		var bounce_active := is_hungry_state or (sprite.animation == "idle")
		var bob := sin(_idle_bounce_phase) * _idle_bounce_amplitude if bounce_active else 0.0
		sprite.position.y = bob


func _physics_process(delta: float) -> void:
	if multiplayer.get_unique_id() != owner_peer_id:
		return

	# Hungry pets sit still and stop following.
	if is_hungry_state:
		_play_animation("idle")
		return

	var owner_node := PlayerManager.get_player_node(owner_peer_id)
	if not is_instance_valid(owner_node):
		return

	var offset := pet_data.follow_offset if pet_data else Vector2(-32.0, 0.0)
	var target := owner_node.global_position + offset

	var delta_pos := target - global_position
	var distance := delta_pos.length()

	if pet_data and distance > pet_data.leash_radius:
		global_position = target
		_play_animation("idle")
	elif distance > ARRIVE_DISTANCE:
		var speed: float = pet_data.walk_speed if pet_data else 120.0
		var step := delta_pos.normalized() * speed * delta
		if step.length() > distance:
			global_position = target
		else:
			global_position += step
		_facing_right = delta_pos.x >= 0.0
		_play_animation("walk")
	else:
		_play_animation("idle")

	_apply_facing()

	# Auto-loot scan (owner-client driven; server validates each request).
	_autoloot_accumulator += delta
	if _autoloot_accumulator >= AUTOLOOT_TICK_INTERVAL:
		_autoloot_accumulator = 0.0
		_try_autoloot()

	# Auto-pot tick (owner-client driven; server validates each request).
	_autopot_accumulator += delta
	if _autopot_accumulator >= AUTOPOT_TICK_INTERVAL:
		_autopot_accumulator = 0.0
		_try_autopot()


func _try_autoloot() -> void:
	if not pet_data:
		return
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		return
	var learned: Array = record.get(PetManager.KEY_LEARNED, [])
	var can_loot_items: bool = learned.has(PetManager.CMD_ITEM_POUCH)
	var can_loot_coins: bool = learned.has(PetManager.CMD_MESO_MAGNET)
	if not can_loot_items and not can_loot_coins:
		return

	var map_node := get_parent()
	if not map_node:
		return

	var best_drop: Node = _scan_drops(map_node, can_loot_items, can_loot_coins)
	# Fall back to the ItemDrops container if present.
	var drops_container := map_node.get_node_or_null("ItemDrops")
	if drops_container:
		var alt: Node = _scan_drops(drops_container, can_loot_items, can_loot_coins)
		if alt and (not best_drop or global_position.distance_to(alt.global_position) < global_position.distance_to(best_drop.global_position)):
			best_drop = alt

	if best_drop:
		PetManager.request_autoloot_server.rpc_id(1, pet_uuid, best_drop.name)


func _try_autopot() -> void:
	var record := PetManager.client_find_pet(pet_uuid)
	if record.is_empty():
		return
	if not (record.get(PetManager.KEY_LEARNED, []) as Array).has(PetManager.CMD_AUTO_POT):
		return
	var owner_node := PlayerManager.get_player_node(owner_peer_id)
	if not is_instance_valid(owner_node):
		return

	var inv: Dictionary = record.get(PetManager.KEY_INVENTORY, {})
	var cfg: Dictionary = record.get(PetManager.KEY_AUTOPOT_CONFIG, {})

	# HP
	var hp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_HP, {})
	if not hp_slot.is_empty() and int(hp_slot.get("stack", 0)) > 0:
		var hp_threshold: float = cfg.get(PetManager.KEY_HP_THRESHOLD, 0.5)
		var hp_node = owner_node.get("health_component") if owner_node.has_method("get") else null
		if is_instance_valid(hp_node) and hp_node.max_health > 0:
			if float(hp_node.current_health) < float(hp_node.max_health) * hp_threshold:
				PetManager.request_autopot_server.rpc_id(1, pet_uuid, "hp")

	# MP
	var mp_slot: Dictionary = inv.get(PetManager.KEY_AUTOPOT_MP, {})
	if not mp_slot.is_empty() and int(mp_slot.get("stack", 0)) > 0:
		var mp_threshold: float = cfg.get(PetManager.KEY_MP_THRESHOLD, 0.5)
		var mp_node = owner_node.get("mana_component") if owner_node.has_method("get") else null
		if is_instance_valid(mp_node) and mp_node.max_mana > 0:
			if float(mp_node.current_mana) < float(mp_node.max_mana) * mp_threshold:
				PetManager.request_autopot_server.rpc_id(1, pet_uuid, "mp")


func _scan_drops(container: Node, can_loot_items: bool, can_loot_coins: bool) -> Node:
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
		var is_coin: bool = drop.item_data.name == "Coin"
		if is_coin and not can_loot_coins:
			continue
		if not is_coin and not can_loot_items:
			continue
		var d: float = global_position.distance_to(drop.global_position)
		if d < best_dist:
			best_dist = d
			best = drop
	return best


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


## Called by PetManager via RPC when the server's hunger tick changes state.
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


## Plays a short feedback animation when the server broadcasts a pet event.
## Called from PetManager._pet_event_visual_rpc.
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
