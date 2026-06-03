class_name BossAttackData
extends Resource
## One authored boss special attack. A boss's EnemyData carries an Array of these
## (EnemyData.special_attacks); the generic executor state (enemy_boss_special.gd)
## reads the chosen one and runs it. Different bosses — and different attacks on
## the same boss — vary purely by editing these fields in the inspector. For
## anything the built-in shape/timing path can't express (a dragon's spreading
## fire, a multi-hit, a summon), set `logic_script` to a Node script with the
## duck-typed hooks the executor calls (see below) — mirrors AbilityData's
## ActiveBehaviorData.logic_script pattern.

## Telegraph + hit shape. RECT = forward slam band, CIRCLE = radial nova, CONE =
## forward fan (e.g. dragon breath). CONE damage is geometric; its telegraph
## visual currently approximates as a forward band (a true cone GroundZone visual
## is a follow-up).
enum Shape { RECT, CIRCLE, CONE }

## How the windup animation is timed against the windup window.
##   STRETCH — scale the clip so it finishes exactly as the hit lands (default;
##             the clip never races ahead of the attack).
##   HOLD    — play the clip, pause on `hold_frame` until the hit, then resume.
##   FREE    — play at the clip's native speed, no sync to the hit.
enum AnimMode { STRETCH, HOLD, FREE }

## Optional movement that resolves with the hit. NONE = rooted. DASH = lunge
## forward (to the far edge of the zone) as the hit lands — the Warlord slam.
enum Movement { NONE, DASH }

@export_category("Identity")
@export var attack_name: String = "Special"

@export_category("Timing")
## Telegraph window before the hit lands (seconds). The ground telegraph shows for
## this long.
@export var windup_time: float = 1.2
## When the damage actually resolves, in seconds from windup start. Usually equals
## windup_time; set lower to land the hit before the windup visual fully completes.
@export var hit_time: float = 1.2
## Seconds between uses of THIS attack (its own cooldown).
@export var cooldown: float = 8.0
@export var anim_mode: AnimMode = AnimMode.STRETCH
## Windup animation clip (must exist on the boss's SpriteFrames). Empty = keep the
## current pose. The executor also tries dash_attack/slash_attack/bomb_attack if
## this is empty.
@export var windup_anim: String = ""
## HOLD only: the clip frame to freeze on until the hit. -1 = the clip's last frame.
@export var hold_frame: int = -1

@export_category("Shape & Reach")
@export var shape: Shape = Shape.RECT
## CIRCLE: hit radius. RECT/CONE: forward reach (length).
@export var reach: float = 140.0
## RECT: full band height (short = airborne players clear it). Ignored by CIRCLE.
@export var band_height: float = 64.0
## CONE: full opening angle in degrees. Ignored by RECT/CIRCLE.
@export var cone_angle_deg: float = 70.0
## Offset of the zone from the boss along facing, as a fraction of `reach`.
## 0.5 = the zone's near edge sits at the boss's centre (forward box). 0 = centred
## on the boss. Ignored by CIRCLE (always centred on the boss).
@export var forward_offset_frac: float = 0.5

@export_category("Movement")
@export var movement: Movement = Movement.NONE
## DASH distance in px along facing. 0 = use `reach` (lunge to the zone's far edge).
@export var dash_distance: float = 0.0
@export var dash_time: float = 0.18

@export_category("Damage")
## Multiplier on the boss's attack stat (WEAPON/MAGIC) for this hit.
@export var damage_mult: float = 2.0

@export_category("Bespoke")
## Optional Node script for custom attacks. Duck-typed hooks, all optional, called
## by the executor on the SERVER:
##   on_windup_start(boss, attack)        — at telegraph start
##   on_hit(boss, attack, center, facing) — when the hit lands; return true to
##                                           SUPPRESS the built-in shape damage and
##                                           do your own (fire spread, multi-hit)
##   on_recover(boss, attack)             — when the state exits
@export var logic_script: Script
