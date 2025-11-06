class_name EnemyData
extends Resource

@export_category("General")
@export var monster_name: String
@export var monster_level: int = 1
@export var movement_speed: float = 60.0

@export_category("Visuals")
@export var sprite_frames: SpriteFrames
@export var character_collision_shape: Shape2D
@export var body_hitbox_shape: Shape2D
@export var attack_hitbox_shape: Shape2D

@export_category("Drops")
@export var item_drops: Array[ItemDropResource] = []
