class_name ActiveBehaviorData
extends Resource

@export var cooldown_time: float = 1.0
@export var mana_cost: int = 1
@export var cast_time: float = 0.0 # Maplestory often has instant cast, but good to have
@export var hit_box_data: Resource # Reference a resource defining the hitbox shape/size
@export var animation_name: String = ""
@export var sfx_path: String = ""
