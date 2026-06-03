class_name Projectile
extends Area2D

# These properties will be set by the server upon spawning
var caster: Node2D
var target: Node2D
var speed: float = 100.0
var initial_direction: Vector2 = Vector2.RIGHT

# Data for the ability that fired this projectile
var ability: AbilityData
var level_stats: AbilityLevelData
## Captured at SPAWN time: was the caster stealthed (dagger ambush) when this
## projectile was thrown? Carried per-projectile so every knife of a stealth-cast
## ambushes, even though they land across different frames after stealth has broken.
var is_ambush: bool = false

@onready var sprite_2d: Node2D = $Sprite2D

func _ready() -> void:
	# The projectile should only detect collisions on the server
	monitoring = multiplayer.is_server()
	if monitoring:
		area_entered.connect(_on_area_entered)
	
	# Set a lifetime for the projectile in case it never hits anything.
	# This runs on all peers, ensuring cleanup.
	get_tree().create_timer(1.0).timeout.connect(queue_free)

# Server-side initialization.
func initialize(p_caster: Node2D, p_target: Node2D, p_ability: AbilityData, p_level_stats: AbilityLevelData, p_speed: float, p_initial_direction: Vector2 = Vector2.RIGHT, p_is_ambush: bool = false):
	caster = p_caster
	target = p_target
	ability = p_ability
	level_stats = p_level_stats
	speed = p_speed
	initial_direction = p_initial_direction
	is_ambush = p_is_ambush
	#sprite_2d.texture = p_ability.ability_icon #TESTING

func _physics_process(delta: float) -> void:
	# Every peer simulates the projectile's movement locally — there is no
	# MultiplayerSynchronizer. The server stays authoritative for hit detection
	# (see _on_area_entered, connected only on the server).
	var current_direction: Vector2

	if is_instance_valid(target):
		# Homing projectile logic
		var target_position = target.global_position
		if target.has_node("AimTarget"):
			target_position = target.get_node("AimTarget").global_position
		current_direction = (target_position - global_position).normalized()
	else:
		# Non-homing projectile, moves in a straight line
		current_direction = initial_direction.normalized()
		monitoring = false

	global_position += current_direction * speed * delta
	rotation = current_direction.angle()

# Server-side collision detection
func _on_area_entered(area: Area2D) -> void:
	# It's possible for this area to be freed if another projectile killed it this frame.
	if not is_instance_valid(area):
		return

	##print("Projectile: Collision detected with %s (owner: %s)" % [area.name, area.owner.name])
	# This function is only connected on the server (_ready function)
	
	# Don't hit the caster
	if area.owner == caster:
		##print("Projectile: Hit caster, ignoring.")
		return

	# Check if the area belongs to a valid damagable entity
	if not "health_component" in area.owner:
		##print("Projectile: %s does not have a health_component, ignoring." % area.owner.name)
		return
		
	var health_comp = area.owner.get("health_component")
	if not health_comp or health_comp.is_dead:
		##print("Projectile: %s health_component is invalid or dead, ignoring." % area.owner.name)
		return

	# If this is a targeted projectile, only hit the intended target.
	if is_instance_valid(target) and area.owner != target:
		##print("Projectile: Targeted projectile hit %s, but target is %s, ignoring." % [area.owner.name, target.name])
		return

	# If we've reached here, we have a valid hit.
	# Instead of dealing damage directly, we tell the caster's CombatComponent to process the hit.
	if is_instance_valid(caster) and caster.combat_component:
		##print("Projectile: Valid hit on %s. Telling caster to process damage." % area.owner.name)
		caster.combat_component.process_projectile_hit(area.owner, ability, level_stats, is_ambush)
	else:
		printerr("Projectile: Caster or its CombatComponent is invalid.")

	# The projectile is destroyed on the server; tell clients to drop their copy.
	_server_destroy()


## Server-only: remove this projectile early (it hit something) and tell
## same-map clients to drop their visual copy. Lifetime expiry needs no RPC —
## each peer's own _ready timer frees its copy independently.
func _server_destroy() -> void:
	var container := get_parent()
	if is_instance_valid(container):
		var map_node := container.get_parent()
		if is_instance_valid(map_node) and map_node.is_in_group("map_base"):
			var map_name: String = map_node.name.replace("Map_", "")
			MapManager.broadcast_to_map(map_name, func(peer_id): MapManager.despawn_projectile_visual.rpc_id(peer_id, name), true, true)
	queue_free()
