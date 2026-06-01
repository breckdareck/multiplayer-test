extends Node

## Arcane Familiar (staff active) — SUMMON. Summons a mini arcane wisp at the
## caster's side for 12 seconds. The wisp auto-fires Arcane Bolt-style
## projectiles at nearby enemies on a fixed cadence.
##
## Staff analog to dagger's Shadow Partner (`AL_ShadowPartner.gd`). Adds the
## summon shape category to staff. Pairs with sustained channels
## (Stormcall + Familiar = a lot of incoming damage per second from one
## position) and with Mana Surge (familiar's bolts can consume / extend
## marks too).
##
## Implementation: a simple node spawned under the caster's map with a
## tick Timer that fires at INTERVAL. On each tick, find the nearest
## enemy within RANGE of the familiar and apply damage as if the caster
## had hit it. The familiar carries no AI / pathing — it just hovers
## at the caster's last known position and shoots from there.
##
## A full Arcane-Bolt-projectile spawn is deferred to v2 — for v1 the
## familiar applies instant-hit damage (no travel time) at FIRE_RATE.

const DURATION_SECONDS: float = 12.0
const FIRE_RATE: float = 0.8           ## seconds between bolts
const BOLT_RANGE: float = 280.0
## Bolt damage = 22% of MAGICATTACK per shot.
const BOLT_DAMAGE_PCT: float = 0.22


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return
	if not "player_id" in owner_node:
		return

	# Cache the caster's map so the familiar's tick stays scoped to the
	# same map as the caster. Bots / disconnects naturally clean up via the
	# duration timer + the networked_entities group sweep.
	var map_id: String = MapManager.get_player_map(owner_node.player_id)
	if map_id == "":
		return
	var map_inst = MapManager.active_maps[map_id].get("scene_instance")
	if not is_instance_valid(map_inst):
		return

	# Spawn the familiar as a plain Node2D under the map. It joins
	# `networked_entities` so MultiplayerManager's cleanup sweep frees it on
	# disconnect / channel switch.
	var familiar := Node2D.new()
	familiar.name = "ArcaneFamiliar"
	familiar.global_position = owner_node.global_position + Vector2(40.0, -20.0)
	familiar.add_to_group("networked_entities")
	map_inst.add_child(familiar)

	# Drive ticking via a Timer child so the familiar's lifecycle is
	# self-contained — when the duration timer expires, the familiar
	# queue_frees and the tick timer goes with it.
	var fire_timer := Timer.new()
	fire_timer.wait_time = FIRE_RATE
	fire_timer.autostart = true
	fire_timer.timeout.connect(_on_familiar_tick.bind(familiar, owner_node))
	familiar.add_child(fire_timer)

	# Self-destruct after DURATION_SECONDS.
	familiar.get_tree().create_timer(DURATION_SECONDS).timeout.connect(
		func():
			if is_instance_valid(familiar):
				familiar.queue_free()
	)


## Per-tick fire: find the nearest living enemy on the same map within
## BOLT_RANGE of the familiar's position; apply BOLT_DAMAGE_PCT × MAGICATTACK
## to it. Server-only — fires from inside a Timer connected on the server.
func _on_familiar_tick(familiar: Node2D, caster: Node) -> void:
	if not is_instance_valid(familiar) or not is_instance_valid(caster):
		return
	# Caster could have died / despawned mid-summon — let the familiar finish
	# its duration but use null as the damage source for kill credit (no
	# applier means no XP / on_kill, which is acceptable for an orphan
	# familiar).
	var stats = caster.get("stats_component") if is_instance_valid(caster) else null
	if stats == null or not stats.stats.has(Constants.StatType.MAGICATTACK):
		return
	var magic_attack: int = int(stats.stats[Constants.StatType.MAGICATTACK].total_value)
	var damage: int = maxi(1, roundi(magic_attack * BOLT_DAMAGE_PCT))

	# Find nearest living enemy on the same map (familiar's parent = map).
	var familiar_pos: Vector2 = familiar.global_position
	var nearest: Node = null
	var best_dist: float = BOLT_RANGE
	var map_root: Node = familiar.get_parent()
	for enemy in familiar.get_tree().get_nodes_in_group("Enemies"):
		if not is_instance_valid(enemy):
			continue
		if map_root != null and not map_root.is_ancestor_of(enemy):
			continue
		var hc = enemy.get("health_component")
		if hc == null or not is_instance_valid(hc) or hc.is_dead:
			continue
		var d: float = enemy.global_position.distance_to(familiar_pos)
		if d < best_dist:
			best_dist = d
			nearest = enemy
	if nearest == null:
		return
	var hc2 = nearest.get("health_component")
	if hc2 == null or not is_instance_valid(hc2):
		return
	hc2.take_damage(damage, caster if is_instance_valid(caster) else null, true, false, true)
