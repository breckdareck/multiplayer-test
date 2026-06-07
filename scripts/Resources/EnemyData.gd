@tool
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


## The boss's special attacks. Authored `special_attacks` win; otherwise one is
## synthesised from the legacy special_attack_* fields (a forward RECT dash-slam),
## so bosses that predate BossAttackData keep working unchanged.
func get_special_attacks() -> Array[BossAttackData]:
	if not special_attacks.is_empty():
		return special_attacks
	if special_attack_cooldown <= 0.0:
		return []
	var a := BossAttackData.new()
	a.attack_name = "Dash Slam"
	a.shape = BossAttackData.Shape.RECT
	a.reach = special_attack_radius * 2.0
	a.band_height = clampf(special_attack_radius * 0.55, 48.0, 110.0)
	a.forward_offset_frac = 0.5
	a.windup_time = special_telegraph_time
	a.hit_time = special_telegraph_time
	a.cooldown = special_attack_cooldown
	a.damage_mult = special_attack_damage_mult
	a.anim_mode = BossAttackData.AnimMode.STRETCH
	a.movement = BossAttackData.Movement.DASH
	a.dash_distance = 0.0  # 0 = use reach
	a.dash_time = 0.18
	return [a]

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

@export_category("Boss")
## Master switch. When false (the default) NONE of the boss machinery below runs —
## every boss branch in enemy_base.gd is guarded by enemy_data.is_boss, so plain
## enemies are completely unaffected. When true the enemy gains phase transitions,
## an optional enrage, a telegraphed AoE special, and announces itself to the
## boss HP bar HUD widget.
@export var is_boss: bool = false
## Shown on the boss HP bar. Falls back to monster_name when empty.
@export var boss_title: String = ""
## Optional flavor line shown small under the boss title (a one-sentence "intro"
## for the encounter). Hidden when empty.
@export var boss_subtitle: String = ""
## HP fractions (0..1) that trigger a phase change as the boss's health crosses
## DOWN through them, e.g. [0.66, 0.33]. Each fires exactly once; the enemy_base
## tracker remembers the highest already-passed threshold so re-crossing (heal
## then re-damage) never re-fires a phase.
@export var phase_health_thresholds: Array[float] = []
## Below this HP fraction the boss enrages once (0 = no enrage). Independent of
## phases — both can be active simultaneously.
@export var enrage_health_threshold: float = 0.0
## Damage multiplier applied while enraged.
@export var enrage_damage_mult: float = 1.5
## Attack-cooldown DIVISOR while enraged (>1 = faster swings).
@export var enrage_attack_speed_mult: float = 1.5
## Seconds between telegraphed specials (0 = no special attack).
@export var special_attack_cooldown: float = 8.0
## Windup seconds before the telegraphed special lands (the dodge window).
@export var special_telegraph_time: float = 1.2
## AoE radius (px) of the special attack.
@export var special_attack_radius: float = 120.0
## Special damage multiplier vs the boss's normal hit.
@export var special_attack_damage_mult: float = 2.0

## Authored special attacks. When non-empty, these REPLACE the four legacy
## special_attack_* fields above and the boss can have several distinct attacks
## (each with its own shape/timing/cooldown). When empty, the executor synthesises
## one BossAttackData from the legacy fields (a forward dash-slam), so existing
## bosses keep working unchanged. Author new attacks here in the inspector.
@export var special_attacks: Array[BossAttackData] = []

@export_category("Drops")
@export var item_drops: Array[ItemDropResource] = []
