@tool
class_name ActiveBehaviorData
extends Resource

@export var target_type: Constants.TargetType
@export var hit_box_shape_data: Shape2D # Reference a resource defining the hitbox shape/size
@export var hit_box_position_data: Vector2
@export var animation_name: String = ""
@export var sfx_path: String = ""
@export var logic_script: Script
## Channeled-cast mode. NONE = instant (logic_script.execute fires on cast,
## state lasts the attack animation). WINDUP_RELEASE = the caster is rooted
## for the ability's cast_time and the release (execute + hitbox) fires at
## the END of the wind-up; cancelled if the state is force-exited first
## (death), with no resource refund. HOLD = the release fires on cast as
## normal but the caster stays rooted in the attack state for cast_time
## (sustained channels like zone rains). Driven by the attack state's
## physics_update on every peer — the server's release is the only
## authoritative one.
@export_enum("None", "Windup Release", "Hold") var channel_mode: int = 0

# VFX override keys (a VfxEffectData effect_key under resources/VFX). Empty = let VfxCatalog.resolve_*
# pick from the ability's identity. Edited via the Resources editor plugin's
# "Ability VFX" dropdowns (with live preview), so they use @export_storage:
# persisted to the .tres but hidden from the generic inspector to avoid a
# confusing duplicate text field beside the plugin's dropdown.
## Cast effect, plays once at the caster when the ability fires.
@export_storage var cast_vfx: String = ""
## Hit effect, plays once at each enemy struck.
@export_storage var hit_vfx: String = ""

@export_group("Projectile")
@export var is_projectile: bool = false
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 500.0
