class_name State
extends Node

@export var animation_name: String
@export var move_speed: float = 130

var allow_flip: bool = true
var gravity: int = ProjectSettings.get_setting("physics/2d/default_gravity")

var parent: CharacterBody2D
var animations: AnimatedSprite2D

func enter() -> void:
	if !parent:
		push_error("Parent Node is null")
		return

	if not OS.has_feature("dedicated_server"):
		if !animations:
			push_error("Animation Node is null")
			return
		
	_play_animation(animation_name)

func _play_animation(anim_name: String) -> void:
	"""A helper to play an animation, respecting the multiplayer host/client context."""
	if (not multiplayer.is_server() || MultiplayerManager.host_mode_enabled) and not anim_name.is_empty():
		animations.play(anim_name)

func exit() -> void:
	pass
	
func process_input(_event: InputEvent) -> State:
	return null
	
func process_frame(_delta: float) -> State:
	return null
	
func physics_update(_delta: float) -> State:
	"""
	This is a "virtual" method. Child states should override this for their
	specific physics logic instead of overriding process_physics().
	This ensures the universal checks in process_physics() are always run.
	"""
	return null

func process_physics(delta: float) -> State:
	# This universal check runs for every state. It ensures we can always
	# transition to the Death state if the parent has a HealthComponent.
	# This works for both Players and Enemies by checking for the exported property.
	if "health_component" in parent:
		var health_comp = parent.get("health_component") as HealthComponent
		if health_comp and health_comp.is_dead:
			# The state machine must have a child state named "death".
			return get_node_or_null("../death")

	# After the global checks, run the specific logic for the current state.
	var next_state: State = physics_update(delta)
	return next_state
	
