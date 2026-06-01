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

## When true, this enemy's attacks deal MAGIC damage — scaled by its MAGICATTACK
## and mitigated by the target's MAGICDEFENSE — instead of the default physical
## (WEAPONATTACK vs DEFENSE). Use for elemental / caster enemies so the magic-
## defense axis (magic armor) actually matters. See enemy_base.damage_on_overlap.
@export var is_magic_attacker: bool = false

@export_category("Stat Tuning")
## Per-enemy multipliers applied ON TOP of the shared monster_*_curves (1.0 = the
## curve baseline for this monster_level). These let two same-level enemies feel
## DIFFERENT without authoring separate curves — e.g. a slime with defense_mult
## 1.5 and magic_defense_mult 0.4 is a physical wall that melts to magic, while a
## wraith might invert it. Tune freely up or down; applied in enemy_base._ready.
@export var defense_mult: float = 1.0
@export var magic_defense_mult: float = 1.0
@export var health_mult: float = 1.0
## Scales BOTH the weapon- and magic-attack curve values (an enemy uses whichever
## matches is_magic_attacker), so a heavy-hitter or a weakling reads off one knob.
@export var attack_mult: float = 1.0

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
