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

const ACTIVE_COLOR: Color = Color(1.0, 0.82, 0.4, 1.0)   # amber flash on proc
const IDLE_COLOR: Color = Color(0.78, 0.72, 0.62, 1.0)   # warm dim when idle

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
	if is_instance_valid(synergy_component) and synergy_component.has_signal("duo_swap_proc"):
		synergy_component.duo_swap_proc.connect(_on_duo_swap_proc)
	if is_instance_valid(equipment_component):
		equipment_component.on_equipment_changed.connect(_refresh)
		equipment_component.active_weapon_changed.connect(_on_active_weapon_changed)
	# Spending / refunding ability points can cross the duo threshold — keep
	# the label's ★ live without waiting for an equipment event.
	var ac = player.get("ability_component")
	if ac != null and is_instance_valid(ac) and ac.has_signal("ability_points_changed"):
		ac.ability_points_changed.connect(_on_points_changed)

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


func _on_points_changed(_disc_key: String, _points: int) -> void:
	_refresh()


## Show + name the synergy only when a recognized two-weapon pair is equipped.
## A ★ on the label means the pair's DUO NODE is unlocked (hover for detail).
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
		pair_label.text = rec["name"] + (" ★" if _duo_unlocked() else "")
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
## ability / item tooltip look), rather than Godot's raw-text default. Duo
## state is computed fresh on hover so the tooltip tracks live point spending.
func _make_custom_tooltip(_for_text: String) -> Object:
	return AbilityTooltip.build(SynergyInfo.tooltip_bbcode(
		_current_pair_key, _duo_unlocked(), _duo_progress_text()))


# --- Duo node state (ADR 0013), mirrored client-side ---
# The unlock rule is derived: 30+ ability points spent in BOTH equipped
# disciplines (weapon_pair_synergy.DUO_THRESHOLD_POINTS — read off the bound
# component so the two can't drift). Ability levels + owned upgrades are
# synced to the owning client, so get_points_spent_in_discipline works here.

const _DISC_KEY := {SWORD: "sword", BOW: "bow", STAFF: "staff", DAGGER: "dagger"}


func _duo_threshold() -> int:
	if is_instance_valid(synergy_component) and "DUO_THRESHOLD_POINTS" in synergy_component:
		return int(synergy_component.DUO_THRESHOLD_POINTS)
	return 30


## The two equipped discipline keys, or [] when not a valid pair.
func _pair_disc_keys() -> Array:
	if not is_instance_valid(player) or not player.has_method("get_equipped_disciplines"):
		return []
	var keys: Array = []
	for d in player.get_equipped_disciplines():
		var k = _DISC_KEY.get(int(d), "")
		if k != "" and not keys.has(k):
			keys.append(k)
	return keys if keys.size() == 2 else []


func _duo_unlocked() -> bool:
	var keys: Array = _pair_disc_keys()
	if keys.is_empty():
		return false
	var ac = player.get("ability_component")
	if ac == null or not is_instance_valid(ac) or not ac.has_method("get_points_spent_in_discipline"):
		return false
	for k in keys:
		if int(ac.get_points_spent_in_discipline(k)) < _duo_threshold():
			return false
	return true


## "Sword 12/30 · Staff 30/30" — shown in the tooltip while the duo is locked.
func _duo_progress_text() -> String:
	var keys: Array = _pair_disc_keys()
	if keys.is_empty():
		return ""
	var ac = player.get("ability_component")
	if ac == null or not is_instance_valid(ac) or not ac.has_method("get_points_spent_in_discipline"):
		return ""
	var parts: Array = []
	for k in keys:
		var spent: int = mini(int(ac.get_points_spent_in_discipline(k)), _duo_threshold())
		parts.append("%s %d/%d" % [String(k).capitalize(), spent, _duo_threshold()])
	return " · ".join(parts)


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


## The duo rotation beat: rarer and bigger than an ordinary proc — louder
## flash and a stinger. Local-only (the signal already arrives client-side).
func _on_duo_swap_proc(_key: String) -> void:
	if not visible:
		return
	AudioManager.play_ui_sfx("res://assets/sounds/generated/duo_swap.wav", -2.0)
	if is_instance_valid(pair_label):
		pair_label.add_theme_color_override("font_color", ACTIVE_COLOR)
	pivot_offset = size * 0.5
	var tween: Tween = create_tween()
	tween.tween_property(self, "scale", Vector2(1.35, 1.35), 0.09).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "scale", Vector2(1.0, 1.0), 0.16).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


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
