extends Resource
class_name Item

@export var name: String
@export var icon: Texture2D
@export var description: StringName
@export var can_stack: bool
@export var max_stack_amount: int
@export var current_stack_amount: int = 1
