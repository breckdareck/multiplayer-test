class_name Pet
extends Node2D

## A summoned pet entity. Owner-bound, server-spawned, owner-client-authoritative
## on position. See docs/adr/0001-pet-system-architecture.md.
##
## The server creates this node via PetManager.spawn_pet_server and sets
## multiplayer_authority to the owner's peer id. The owner's client then
## drives the follow algorithm; other peers receive position via the node's
## MultiplayerSynchronizer.

@export var sprite: AnimatedSprite2D

# ── Identity (assigned by PetManager.setup) ───────────────────────────────
var owner_peer_id: int = 0
var pet_uuid: String = ""
var pet_data: PetData = null
var owner_username: String = ""

# ── Position / animation state (owner client only) ────────────────────────
var _facing_right: bool = true
const ARRIVE_DISTANCE: float = 6.0


func _ready() -> void:
	add_to_group("networked_entities")
	_apply_pet_data()


## Called by PetManager immediately after instantiation, before add_child.
func setup(pet_data_in: PetData, peer_owner: int, uuid: String, owner_name: String) -> void:
	pet_data = pet_data_in
	owner_peer_id = peer_owner
	pet_uuid = uuid
	owner_username = owner_name
	if is_inside_tree():
		_apply_pet_data()


func _apply_pet_data() -> void:
	if not pet_data or not sprite:
		return
	if pet_data.sprite_frames:
		sprite.sprite_frames = pet_data.sprite_frames
	_play_animation("idle")


func _physics_process(delta: float) -> void:
	# Position is owner-client-authoritative. Other peers only render what
	# the synchronizer streams to them.
	if multiplayer.get_unique_id() != owner_peer_id:
		return

	var owner_node := PlayerManager.get_player_node(owner_peer_id)
	if not is_instance_valid(owner_node):
		return

	var offset := pet_data.follow_offset if pet_data else Vector2(-32.0, 0.0)
	var target := owner_node.global_position + offset

	var delta_pos := target - global_position
	var distance := delta_pos.length()

	# Snap back if we've drifted past the leash.
	if pet_data and distance > pet_data.leash_radius:
		global_position = target
		_play_animation("idle")
		return

	if distance > ARRIVE_DISTANCE:
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


func _play_animation(anim_name: String) -> void:
	if not sprite or not sprite.sprite_frames:
		return
	var target_anim := anim_name
	# The repurposed enemy SpriteFrames use "patrol" for walking, not "walk".
	# Fall back gracefully so PetData can point at either.
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


## Cleanup hook called by PetManager.despawn_pet before queue_free,
## mirrors the pattern from character nodes.
func cleanup_before_removal() -> void:
	pet_data = null
