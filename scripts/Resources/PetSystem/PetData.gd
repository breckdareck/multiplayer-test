@tool
class_name PetData
extends Resource

## Static definition of a pet variety. Authored as a .tres in
## resources/PetSystem/. The runtime per-character pet record (hunger,
## learned commands, name, inventory) lives in the player's save under
## `pets: []` and is owned by PetManager.

@export var pet_id: String:
	set(value):
		if value.is_empty():
			pet_id = _generate_uuid()
		else:
			pet_id = value

@export var display_name: String = "Pet"
@export var description: String = ""
@export var icon: Texture2D
@export var sprite_frames: SpriteFrames

@export_group("Movement")
## How fast the pet walks toward its follow target (px/sec).
@export var walk_speed: float = 120.0
## Max distance from owner before the pet teleports back.
@export var leash_radius: float = 200.0
## Pixel offset behind the owner the pet aims to settle at.
@export var follow_offset: Vector2 = Vector2(-32.0, 0.0)
## Initial upward velocity when jumping platforms (px/sec, negative is up).
@export var jump_velocity: float = -360.0
## Downward gravity applied each second (px/sec²).
@export var gravity: float = 900.0
## How much higher the owner must be than the pet (and pet on floor) before
## the pet attempts a jump (px).
@export var jump_threshold_y: float = 24.0
## How long (seconds) the pet can be > leash_radius from owner before it
## auto-teleports. Used to bridge ropes/ladders the pet can't navigate.
@export var leash_teleport_grace_sec: float = 1.5

@export_group("Auto-loot")
## Range around the pet body within which it will auto-loot drops (px).
@export var autoloot_radius: float = 100.0

@export_group("Hunger")
## Maximum fullness value.
@export var max_hunger: float = 100.0
## How much fullness decays per second while the pet is summoned + owner online.
@export var hunger_decay_per_sec: float = 1.0 / 30.0


func _init() -> void:
	if pet_id.is_empty():
		pet_id = _generate_uuid()


func _generate_uuid() -> String:
	var id = []
	for i in range(32):
		id.append(str(int(randf() * 16)).to_upper())
	return "%s-%s-%s-%s-%s" % [
		"".join(id.slice(0, 8)),
		"".join(id.slice(8, 12)),
		"".join(id.slice(12, 16)),
		"".join(id.slice(16, 20)),
		"".join(id.slice(20, 32))
	]
