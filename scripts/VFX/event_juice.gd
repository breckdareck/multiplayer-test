class_name EventJuice
extends Object

## One-call juice for cross-discipline proc moments (ADR 0013 escalations,
## weapon-pair synergy bursts): named colored floating text at the target,
## an SFX stinger, and an optional VfxCatalog impact — so the game's most
## build-expressive events are seen and heard, not just applied.
##
## Server-only by construction: every delivery channel used here re-guards on
## multiplayer.is_server() (display_event_text, play_sfx_for_map,
## broadcast_vfx_everywhere), so calling from server-side logic is safe and a
## stray client call is a no-op.

## Palette mirrors tools/gen_ability_icons_px.py so event text matches the
## established color language (FIRE/POISON/ICE/GOLD/GREEN/PURP).
const COLOR_THERMAL := Color("#ff8a3c")
const COLOR_SEPTIC := Color("#86e34a")
const COLOR_BRITTLE := Color("#9fe6ff")
const COLOR_COMBO := Color("#ffce5c")
const COLOR_MOMENTUM := Color("#9ff58a")
const COLOR_AMBUSH := Color("#b89bff")

const SFX_THERMAL := "res://assets/sounds/generated/escalation_thermal.wav"
const SFX_SEPTIC := "res://assets/sounds/generated/escalation_septic.wav"
const SFX_BRITTLE := "res://assets/sounds/generated/escalation_brittle.wav"
const SFX_SYNERGY := "res://assets/sounds/generated/synergy_proc.wav"


## Show `text` in `color` above `target`, play `sfx_path` at it, and spawn the
## optional `vfx_key` impact. Resolves the target's map by ancestry (the
## "Enemies" group is global across maps under the SubViewport-per-map
## architecture, so the map must be derived from the node, never assumed).
static func proc(target: Node, text: String, color: Color, sfx_path: String = "", vfx_key: String = "") -> void:
	if target == null or not is_instance_valid(target):
		return
	var map_node: Node = null
	for map_id in MapManager.active_maps.keys():
		var inst = MapManager.active_maps[map_id].scene_instance
		if is_instance_valid(inst) and inst.is_ancestor_of(target):
			map_node = inst
			break
	if map_node == null:
		return
	var map_name: String = map_node.name.replace("Map_", "")

	# Anchor above the damage-number origin when the target has one, so event
	# text stacks just over the number column instead of covering the sprite.
	var pos: Vector2 = target.global_position + Vector2(0, -40)
	var hc = target.get("health_component")
	if hc != null and is_instance_valid(hc) and hc.get("damage_number_origin") != null and is_instance_valid(hc.damage_number_origin):
		pos = hc.damage_number_origin.global_position + Vector2(0, -10)

	var spawner = map_node.find_child("DmgNumberSpawner", true, false)
	if spawner != null and spawner.has_method("display_event_text"):
		spawner.display_event_text(text, pos, color)

	if sfx_path != "":
		AudioManager.play_sfx_for_map(map_name, sfx_path, target.global_position, -4.0)

	if vfx_key != "":
		MapManager.broadcast_vfx_everywhere(map_name, vfx_key, target.global_position, 1.0, 0.0, false)
