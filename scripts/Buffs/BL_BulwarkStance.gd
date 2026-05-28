extends Node

## Bulwark Stance — toggle defensive stance. While active:
##  - +250 flat DEFENSE (≈25% DR scaling with the defense formula)
##  - Drains MP per second; auto-removes when MP reaches 0
##  - Toggled off by recasting the ability (AL handles that path)

const MP_PER_SECOND: float = 2.0
const MP_TICK_INTERVAL: float = 1.0

var _mp_accumulator: float = 0.0


func on_apply(_owner_node: Node, _active_buff) -> void:
	_mp_accumulator = 0.0


func on_tick(owner_node: Node, _active_buff, delta: float) -> void:
	if not owner_node.multiplayer.is_server():
		return
	_mp_accumulator += delta
	if _mp_accumulator < MP_TICK_INTERVAL:
		return
	_mp_accumulator -= MP_TICK_INTERVAL

	var mana_comp = owner_node.get("mana_component")
	if mana_comp == null or not is_instance_valid(mana_comp):
		return

	if mana_comp.current_mana < MP_PER_SECOND:
		# Out of mana — drop the stance.
		mana_comp.current_mana = 0
		var buff_comp = owner_node.get("buff_component")
		if buff_comp:
			buff_comp.remove_buff(_active_buff_id())
		return

	mana_comp.consume_mana(int(MP_PER_SECOND))


func on_remove(_owner_node: Node, _active_buff) -> void:
	pass


func _active_buff_id() -> String:
	return "bulwark-stance-buff-pr6-2026-warrior-sword"
