class_name EnemyData
extends Resource

@export_category("General")
@export var monster_name: String
@export var monster_level: int = 1
@export var movement_speed: float = 60.0
## Training-dummy flag. When true the enemy can never die: enemy_base sets its
## HealthComponent to floor at 1 HP and hands it a huge health pool so the bar
## reads full. Damage numbers still show — it's a punching bag for testing.
@export var is_invincible: bool = false

@export_category("AI")
## When true the enemy chases any player/bot it spots; when false it ignores
## them until it is attacked, then fights back.
@export var is_aggressive: bool = false
## How far (in pixels) the enemy can spot a target.
@export var detection_radius: float = 160.0
## Distance at which an enemy that has an attack state begins its swing.
@export var attack_range: float = 36.0
## Seconds the enemy must wait between consecutive attacks.
@export var attack_cooldown: float = 1.4

@export_category("Visuals")
@export var sprite_frames: SpriteFrames
@export var character_collision_shape: Shape2D
@export var body_hitbox_shape: Shape2D
@export var attack_hitbox_shape: Shape2D

@export_category("Drops")
@export var item_drops: Array[ItemDropResource] = []
