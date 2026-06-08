extends Control

## Weapon-pair synergy HUD widget. Names the cross-gauge synergy you get from your
## TWO equipped weapons (e.g. Sword+Staff = "SPELLBLADE") and flashes whenever a
## synergy effect fires. Hovering the widget shows a tooltip explaining what the
## synergy does and how the two weapons feed each other (see SynergyInfo). The
## server drives the proc through WeaponPairSynergyComponent.synergy_proc (synced
## to the owning client); this widget only paints — it never reads or mutates
## gameplay state. Left edge, same family as the four gauge widgets.
## Design: project_farever_reference.

const SynergyInfo = preload("res://scripts/UI/synergy_info.gd")

const SWORD := Constants.ClassType.SWORD
const BOW := Constants.ClassType.BOW
const STAFF := Constants.ClassType.STAFF
const DAGGER := Constants.ClassType.DAGGER

const ACTIVE_COLOR: Color = Color(0.55, 0.9, 1.0, 1.0)   # cyan flash on proc
const IDLE_COLOR: Color = Color(0.6, 0.62, 0.7, 1.0)     # dim when idle

var player: MultiplayerPlayerV2 = null
var equipment_component: EquipmentComponent = null
var synergy_component: Node = null

## Pair key of the synergy currently shown ("" when none) — drives the tooltip.
var _current_pair_key: String = ""

@onready var pair_label: Label = $Panel/VBox/PairLabel


func _ready() -> void:
	# Lifted into the persistent UI layer (ADR 0009 Stage B): the body is injected
	# via bind_player() on every spawn / map change, not resolved off `owner`.
	visible = false


## Binds this widget to the local player body. Called by LocalPlayerUI.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
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


## Drops the binding (teardown). The old body's signal connections die with it
## when it is freed, so this just clears refs. Stage C (live-body reparent) will
## need explicit disconnects here.
func unbind_player() -> void:
	player = null
	equipment_component = null
	synergy_component = null
	visible = false


func _on_active_weapon_changed(_active_weapon, _active_item) -> void:
	_refresh()


## Show + name the synergy only when a recognized two-weapon pair is equipped.
func _refresh() -> void:
	if not is_instance_valid(player) or not player.has_method("get_equipped_disciplines"):
		_set_pair("")
		return
	var key: String = _pair_key(player.get_equipped_disciplines())
	var rec = SynergyInfo.get_for_key(key)
	if rec == null:
		_set_pair("")
		return
	_set_pair(key)
	if is_instance_valid(pair_label):
		pair_label.text = rec["name"]
		pair_label.add_theme_color_override("font_color", IDLE_COLOR)


## Stores the active pair key and updates visibility + the hover tooltip trigger.
## tooltip_text must be non-empty for Godot to call _make_custom_tooltip(); the
## name doubles as the plain-text fallback.
func _set_pair(key: String) -> void:
	_current_pair_key = key
	if key == "":
		visible = false
		tooltip_text = ""
		return
	visible = true
	var rec = SynergyInfo.get_for_key(key)
	tooltip_text = rec["name"] if rec != null else ""


## Render the synergy explanation as a skinned BBCode tooltip (matches the
## ability / item tooltip look), rather than Godot's raw-text default.
func _make_custom_tooltip(_for_text: String) -> Object:
	return AbilityTooltip.build(SynergyInfo.tooltip_bbcode(_current_pair_key))


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


func _on_synergy_proc(_key: String) -> void:
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
