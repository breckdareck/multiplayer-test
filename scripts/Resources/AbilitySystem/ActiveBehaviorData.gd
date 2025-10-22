@tool
class_name ActiveBehaviorData
extends Resource

@export var target_type: Constants.TargetType
@export var hit_box_shape_data: Shape2D # Reference a resource defining the hitbox shape/size
@export var hit_box_position_data: Vector2
@export var animation_name: String = ""
@export var sfx_path: String = ""
@export var logic_script: Script
