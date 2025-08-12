extends EnemyAttackState

@export var slash_hitbox_shape: CollisionShape2D

func enter() -> void:
	super.enter() # This calls the base class enter() which zeroes velocity.
	slash_hitbox_shape.disabled = false


func exit() -> void:
	# It's good practice to clean up when exiting a state.
	slash_hitbox_shape.disabled = true
	super.exit()
