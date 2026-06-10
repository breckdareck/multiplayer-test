extends Node

## Shared upgrade hook — WEAKEN ON HIT. Attached as the logic_script of
## abilities whose T3 variant saps struck enemies' damage output (Hailstorm's
## Suppressing Fire). on_hit no-ops unless the ability owns an upgrade with
## effect_key "bonus_weaken_on_hit" (magnitude = outgoing-damage fraction
## removed, e.g. 0.25 = enemies deal 25% less), so attaching this script
## costs nothing until the variant is purchased.
##
## Reuses Smoke Bomb's choke channel: the metas health.gd already reads on the
## ATTACKER when a player takes damage (smoke_choke_expire_at_ms /
## smoke_choke_pct — the names are smoke-flavored but the channel is the
## generic "weakened attacker" path). Max-wins on overlap so a stronger Choking
## Smoke is never diluted by a weaker volley debuff or vice versa.

const WEAKEN_DURATION_SEC: float = 3.0


func on_hit(_owner_node: Node, _target: Node, _ability: AbilityData) -> void:
	if not _owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(_target):
		return
	var weaken_pct: float = 0.0
	var ability_comp = _owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		weaken_pct = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_weaken_on_hit")
	if weaken_pct <= 0.0:
		return

	var smoke_al := preload("res://scripts/Abilities/AL_SmokeBomb.gd")
	var now: int = Time.get_ticks_msec()
	var expire_at: int = now + int(WEAKEN_DURATION_SEC * 1000.0)
	var cur_pct: float = 0.0
	if _target.has_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META) and now < int(_target.get_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META)):
		cur_pct = float(_target.get_meta(smoke_al.SMOKE_CHOKE_PCT_META)) if _target.has_meta(smoke_al.SMOKE_CHOKE_PCT_META) else 0.0
	if weaken_pct >= cur_pct:
		_target.set_meta(smoke_al.SMOKE_CHOKE_PCT_META, weaken_pct)
		_target.set_meta(smoke_al.SMOKE_CHOKE_EXPIRE_META, expire_at)
