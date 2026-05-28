extends Node

## Bleed DOT buff logic — ticks every second, deals damage_per_tick × stack_count
## per interval. Persistent across casts via the buff system's stacks model
## (Hemorrhage's on_hit applies a stack; BuffData.max_stacks caps it).
##
## Tick damage is computed at on_apply from the source's current WEAPONATTACK,
## so a high-mastery character's bleed hits harder than a low-mastery one,
## without needing per-tick stat lookups.

## Damage dealt per second per stack. Set by the applying ability
## (Hemorrhage's AL script) before the buff is applied.
var damage_per_tick: int = 1

## Internal: accumulates delta so we tick on 1-second intervals rather than
## per frame. BuffComponent's on_tick fires every frame with the frame delta.
var _tick_accumulator: float = 0.0


func on_apply(_owner_node: Node, _active_buff) -> void:
	_tick_accumulator = 0.0


func on_tick(owner_node: Node, active_buff, delta: float) -> void:
	if not _owner_node_is_server_authoritative(owner_node):
		return
	_tick_accumulator += delta
	if _tick_accumulator < 1.0:
		return
	_tick_accumulator -= 1.0

	var health_comp = owner_node.get("health_component")
	if health_comp == null or not is_instance_valid(health_comp):
		return
	if health_comp.is_dead:
		return

	var total_damage: int = damage_per_tick * active_buff.stacks
	if total_damage <= 0:
		return
	# `source` is null — bleed is residual damage, not directly attributable
	# to the applier for the purpose of triggering procs again. is_ability=false
	# routes this through the standard take_damage pathway.
	health_comp.take_damage(total_damage, null, false, false, false)


func on_remove(_owner_node: Node, _active_buff) -> void:
	pass


## Damage application must be server-authoritative — clients run on_tick too
## (buff state is synced) but only the server mutates HP. Guard centrally.
func _owner_node_is_server_authoritative(owner_node: Node) -> bool:
	return owner_node.multiplayer.is_server()
