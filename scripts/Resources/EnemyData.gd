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
## Archetype preset — pick a "feel" and the enemy gets a defensive/offensive
## multiplier profile automatically (see _ARCHETYPE_PRESETS below). NONE = pure
## curve baseline. The per-enemy multipliers further down STACK multiplicatively
## on top (so leave them 1.0 unless fine-tuning a single mob beyond its archetype).
@export var archetype: Constants.MonsterArchetype = Constants.MonsterArchetype.NONE

## Per-enemy multipliers applied ON TOP of the archetype + shared monster_*_curves
## (1.0 = no change). Effective = curve x archetype x this. Use the archetype for
## the broad feel; use these only to nudge one specific mob.
@export var defense_mult: float = 1.0
@export var magic_defense_mult: float = 1.0
@export var health_mult: float = 1.0
## Scales BOTH the weapon- and magic-attack curve values (an enemy uses whichever
## matches is_magic_attacker), so a heavy-hitter or a weakling reads off one knob.
@export var attack_mult: float = 1.0

## Archetype -> {def, mdef, hp, atk} multiplier profiles. Keyed by
## Constants.MonsterArchetype. Tune the feels here in one place.
const _ARCHETYPE_PRESETS := {
	Constants.MonsterArchetype.NONE:       {"def": 1.0, "mdef": 1.0, "hp": 1.0, "atk": 1.0},
	Constants.MonsterArchetype.OOZE:       {"def": 1.5, "mdef": 0.4, "hp": 1.0, "atk": 0.8},
	Constants.MonsterArchetype.ARMORED:    {"def": 1.7, "mdef": 0.7, "hp": 1.2, "atk": 1.0},
	Constants.MonsterArchetype.SPECTRAL:   {"def": 0.5, "mdef": 1.7, "hp": 0.85, "atk": 1.0},
	Constants.MonsterArchetype.BRUTE:      {"def": 1.0, "mdef": 0.6, "hp": 1.6, "atk": 1.4},
	Constants.MonsterArchetype.GLASS:      {"def": 0.5, "mdef": 0.5, "hp": 0.6, "atk": 1.5},
	Constants.MonsterArchetype.JUGGERNAUT: {"def": 1.5, "mdef": 1.5, "hp": 2.2, "atk": 1.2},
}


## Effective stat multipliers = archetype preset x per-enemy fine-tune mults.
## Returns {def, mdef, hp, atk}. enemy_base applies these over the level curves.
func effective_stat_mults() -> Dictionary:
	var p: Dictionary = _ARCHETYPE_PRESETS.get(archetype, _ARCHETYPE_PRESETS[Constants.MonsterArchetype.NONE])
	return {
		"def": p["def"] * defense_mult,
		"mdef": p["mdef"] * magic_defense_mult,
		"hp": p["hp"] * health_mult,
		"atk": p["atk"] * attack_mult,
	}

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
