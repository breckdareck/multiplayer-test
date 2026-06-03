extends Control

## Weapon-pair synergy HUD widget. Names the cross-gauge synergy you get from your
## TWO equipped weapons (e.g. Sword+Staff = "SPELLBLADE") and flashes whenever a
## synergy effect fires. The server drives the proc through
## WeaponPairSynergyComponent.synergy_proc (synced to the owning client); this
## widget only paints — it never reads or mutates gameplay state. Left edge, same
## family as the four gauge widgets. Design: project_farever_reference.

const SWORD := Constants.ClassType.SWORD
const BOW := Constants.ClassType.BOW
const STAFF := Constants.ClassType.STAFF
const DAGGER := Constants.ClassType.DAGGER

## Display name per equipped pair — keyed by the sorted "min_max" discipline ints
## (SWORD=0, BOW=1, STAFF=2, DAGGER=3).
const PAIR_NAMES := {
	"0_2": "SPELLBLADE",      # sword + staff — sword hits carry the stance element
	"1_2": "ELEMENTAL SHOT",  # bow + staff   — arrows carry the stance element
	"2_3": "HEXBLADE",        # staff + dagger — ambush carries the stance element
	"0_1": "SKIRMISHER",      # sword + bow   — bow hits bank combo
	"0_3": "ASSASSIN",        # sword + dagger — ambush spends banked combo
	"1_3": "AMBUSHER",        # bow + dagger  — ambush spends bow charge
}
const ACTIVE_COLOR: Color = Color(0.55, 0.9, 1.0, 1.0)   # cyan flash on proc
const IDLE_COLOR: Color = Color(0.6, 0.62, 0.7, 1.0)     # dim when idle

var player: MultiplayerPlayerV2 = null
var equipment_component: EquipmentComponent = null
var synergy_component: Node = null

@onready var pair_label: Label = $Panel/VBox/PairLabel


func _ready() -> void:
	# Resolve the player off the owner chain (instanced under CanvasLayer/PlayerHUD),
	# mirroring the gauge widgets.
	var node: Node = self
	while node and not (node is MultiplayerPlayerV2):
		node = node.get_parent()
	if node is MultiplayerPlayerV2:
		player = node as MultiplayerPlayerV2
	if not is_instance_valid(player):
		visible = false
		return
	# Local player only.
	if player.player_id != multiplayer.get_unique_id():
		visible = false
		return

	equipment_component = player.equipment_component
	synergy_component = player.get_node_or_null("Components/WeaponPairSynergy")

	if is_instance_valid(synergy_component) and synergy_component.has_signal("synergy_proc"):
		synergy_component.synergy_proc.connect(_on_synergy_proc)
	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)

	call_deferred("_refresh")


func _on_active_weapon_changed(_active_weapon, _active_item) -> void:
	_refresh()


## Show + name the synergy only when a recognized two-weapon pair is equipped.
func _refresh() -> void:
	if not is_instance_valid(player) or not player.has_method("get_equipped_disciplines"):
		visible = false
		return
	var key: String = _pair_key(player.get_equipped_disciplines())
	if not PAIR_NAMES.has(key):
		visible = false
		return
	visible = true
	if is_instance_valid(pair_label):
		pair_label.text = PAIR_NAMES[key]
		pair_label.add_theme_color_override("font_color", IDLE_COLOR)


## Normalized "min_max" key for a 2-discipline weapon set; "" if not a valid pair
## (bare-handed, one weapon, or a matched pair that de-dups to a single discipline).
func _pair_key(discs: Array) -> String:
	var w: Array = []
	for d in discs:
		var di: int = int(d)
		if di >= 0 and di <= 3 and not w.has(di):
			w.append(di)
	if w.size() != 2:
		return ""
	w.sort()
	return "%d_%d" % [w[0], w[1]]


func _on_synergy_proc(_pair_key: String) -> void:
	if not visible:
		return
	if is_instance_valid(pair_label):
		pair_label.add_theme_color_override("font_color", ACTIVE_COLOR)
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.2, 1.2), 0.07).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.12).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_interval(0.2)
	tween.tween_callback(_reset_color)


func _reset_color() -> void:
	if is_instance_valid(pair_label):
		pair_label.add_theme_color_override("font_color", IDLE_COLOR)
