@tool
class_name ActiveBehaviorData
extends Resource

@export var target_type: Constants.TargetType
@export var hit_box_shape_data: Shape2D # Reference a resource defining the hitbox shape/size
@export var hit_box_position_data: Vector2
@export var animation_name: String = ""
@export var sfx_path: String = ""
@export var logic_script: Script

@export_group("VFX")
## Optional override of the auto-resolved cast-VFX key (see VfxCatalog.CATALOG).
## Empty = let VfxCatalog.resolve_cast pick from the ability's identity. The cast
## effect plays once at the caster when the ability fires.
@export var cast_vfx: String = ""
## Optional override of the auto-resolved hit-VFX key (see VfxCatalog.CATALOG).
## Empty = let VfxCatalog.resolve_hit pick from the ability's identity. The hit
## effect plays once at each enemy struck.
@export var hit_vfx: String = ""

@export_group("Projectile")
@export var is_projectile: bool = false
@export var projectile_scene: PackedScene
@export var projectile_speed: float = 500.0
