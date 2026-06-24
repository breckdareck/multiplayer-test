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

## Server-side one-shot guard: a projectile resolves a single hit, then frees.
## Stops area_entered + body_entered both firing in the same frame from
## double-applying damage.
var _consumed: bool = false
## Set once the projectile is in its impact-and-vanish phase: it stops moving and
## colliding, plays its "hit" clip (if any), then frees. Runs on every peer.
var _dying: bool = false
## Damage axis for an ENEMY projectile: null = the firing enemy's is_magic_attacker
## default; true/false = this attack's forced axis (a spell → magic, an arrow → physical).
## Set server-side by enemy_base.fire_projectile; ignored for player projectiles.
var enemy_damage_magic = null

@onready var sprite_2d: Node2D = $Sprite2D


## The visual node when it's an AnimatedSprite2D (the new looping/hit projectiles);
## null for the older static Sprite2D projectiles, which just vanish on impact.
func _anim_sprite() -> AnimatedSprite2D:
	return sprite_2d as AnimatedSprite2D

func _ready() -> void:
	# The projectile should only detect collisions on the server
	monitoring = multiplayer.is_server()
	if monitoring:
		# Player targets are AREAS (the enemy BodyHitbox, layer 8); player targets
		# of an ENEMY projectile are BODIES (the player CharacterBody2D, layer 2,
		# has no hurt-area). Connect both so the projectile works in both
		# directions; _consumed guards against a double-resolve in the same frame.
		area_entered.connect(_on_area_entered)
		body_entered.connect(_on_body_entered)

	# Set a lifetime for the projectile in case it never hits anything.
	# This runs on all peers, ensuring cleanup.
	get_tree().create_timer(1.0).timeout.connect(queue_free)

	# New AnimatedSprite2D projectiles loop a "default" clip while flying (autoplay
	# usually covers this; play it explicitly so one without autoplay still animates).
	# Static Sprite2D projectiles have no animation — _anim_sprite() is null.
	var anim := _anim_sprite()
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("default"):
		anim.play("default")

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
	# Impact-and-vanish phase: hold position while the "hit" clip plays out.
	if _dying:
		return
	# Every peer simulates the projectile's movement locally — there is no
	# MultiplayerSynchronizer. The server stays authoritative for hit detection
	# (see _on_area_entered, connected only on the server).
	var current_direction: Vector2

	if is_instance_valid(target):
		# Homing projectile logic
		var target_position = target.global_position
		if target.has_node("AimTarget"):
			target_position = target.get_node("AimTarget").global_position
		var to_target: Vector2 = target_position - global_position
		# Guard normalize() against a non-finite/zero offset (e.g. a target that
		# reached a NaN position) — keep the last heading rather than warn + stall.
		current_direction = to_target.normalized() if to_target.is_finite() and not to_target.is_zero_approx() else initial_direction
	else:
		# Non-homing projectile, moves in a straight line
		current_direction = initial_direction.normalized() if initial_direction.is_finite() and not initial_direction.is_zero_approx() else Vector2.RIGHT
		monitoring = false

	global_position += current_direction * speed * delta
	rotation = current_direction.angle()

# Server-side collision detection. Player projectiles strike enemy hurt-AREAS
# (BodyHitbox, layer 8); enemy projectiles strike the player BODY (CharacterBody2D,
# layer 2). Both route to _try_hit with the struck entity's root node.
func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	_try_hit(area.owner)


func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	_try_hit(body)


## Resolves a single hit against `hit_root` (a character root node). Only connected
## on the server. Guarded so area_entered + body_entered can't double-apply.
func _try_hit(hit_root: Node) -> void:
	if _consumed or not is_instance_valid(hit_root):
		return

	# Don't hit the caster.
	if hit_root == caster:
		return

	# Must be a valid, living damageable entity.
	if not "health_component" in hit_root:
		return
	var health_comp = hit_root.get("health_component")
	if not health_comp or health_comp.is_dead:
		return

	# If this is a targeted projectile, only hit the intended target.
	if is_instance_valid(target) and hit_root != target:
		return

	# Valid hit. Resolve damage through the caster's own pipeline:
	#  - Players/bots route through CombatComponent.process_projectile_hit (ability
	#    + crit + on-hit hooks).
	#  - Enemies have no CombatComponent — they fire projectiles too (ADR-0016), so
	#    route through the enemy's own damage_on_overlap, which IS its standard
	#    attack (hit roll, defense mitigation, level scaling). The projectile then
	#    deals exactly what the enemy's melee would.
	if not is_instance_valid(caster):
		printerr("Projectile: Caster is invalid.")
		return
	_consumed = true
	if "combat_component" in caster and caster.combat_component:
		caster.combat_component.process_projectile_hit(hit_root, ability, level_stats, is_ambush)
	elif caster.has_method("damage_on_overlap"):
		caster.damage_on_overlap(hit_root, enemy_damage_magic)
	else:
		printerr("Projectile: Caster %s has no damage pathway." % caster.name)

	# The projectile is destroyed on the server; tell clients to drop their copy.
	_server_destroy()


## Server-only: the projectile hit something — play the impact-and-vanish on every
## peer. The server runs it on its own copy (the host sees it) and broadcasts
## play_projectile_hit_visual to the same-map clients so they play it on theirs.
## Lifetime expiry needs no RPC — each peer's own _ready timer frees its copy.
func _server_destroy() -> void:
	var container := get_parent()
	if is_instance_valid(container):
		var map_node := container.get_parent()
		if is_instance_valid(map_node) and map_node.is_in_group("map_base"):
			var map_name: String = map_node.name.replace("Map_", "")
			MapManager.broadcast_to_map(map_name, func(peer_id): MapManager.play_projectile_hit_visual.rpc_id(peer_id, name), true, true)
	play_hit_and_die()


## Stops the projectile dead and, if it carries an AnimatedSprite2D with a "hit"
## clip, plays that clip once and frees when it finishes; otherwise frees right away
## (static-sprite projectiles, or no "hit" animation). Idempotent. Called on every
## peer — directly on the server's copy, via RPC on each client's copy.
func play_hit_and_die() -> void:
	if _dying:
		return
	_dying = true
	# Deferred: play_hit_and_die can run inside the area/body_entered signal (server
	# hit path), and Area2D forbids toggling monitoring mid-signal. _dying already
	# stops movement this frame; monitoring clears on the next idle frame.
	set_deferred("monitoring", false)
	var anim := _anim_sprite()
	if anim != null and anim.sprite_frames != null and anim.sprite_frames.has_animation("hit"):
		anim.play("hit")
		anim.animation_finished.connect(_free_self)
		# Fallback: free even if the clip never reports finished (looping/missing frames).
		get_tree().create_timer(0.5).timeout.connect(_free_self)
	else:
		queue_free()


func _free_self() -> void:
	if is_instance_valid(self):
		queue_free()
