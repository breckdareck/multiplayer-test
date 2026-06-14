extends Node

var player

var party_window_scene = preload("res://scenes/UI/party_window.tscn")
var party_window_instance

var party_invite_popup_scene = preload("res://scenes/UI/party_invite_popup.tscn")
var death_popup_scene = preload("res://scenes/UI/death_popup.tscn")
var scrolling_log_scene = preload("res://scenes/UI/ScrollingLog.tscn")
var chat_window_scene = preload("res://scenes/UI/ChatWindow.tscn")

var death_popup_instance: DeathPopup
var ping_display_script = preload("res://scripts/UI/ping_display.gd")

## Player-to-player trade UI. The window is created lazily when a trade session
## opens; the request popup is created per incoming request.
var _trade_window: TradeWindow = null
var _trade_request_popup: TradeRequestPopup = null

@onready var health_bar: TextureProgressBar = $BottomStatsContainer/HealthBar
@onready var hp_value_label: Label = $BottomStatsContainer/HealthBar/HPValueLabel

@onready var mana_bar: TextureProgressBar = $BottomStatsContainer/ManaBar 
@onready var mp_value_label: Label = $BottomStatsContainer/ManaBar/MPValueLabel 

@onready var experience_bar: TextureProgressBar = $BottomStatsContainer/ExperienceBar
@onready var exp_percent_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/EXPPercentLabel

@onready var level_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/LevelPanel/LevelLabel

@onready var mastery_bar: TextureProgressBar = $BottomStatsContainer/MasteryBar
@onready var mastery_label: Label = $BottomStatsContainer/MasteryBar/MasteryLabel
@onready var mastery_percent_label: Label = $BottomStatsContainer/MasteryBar/MasteryPercentLabel

## The discipline currently shown by the mastery bar — the player's ACTIVE
## (wielded) weapon discipline. Cached so mastery_xp_changed events for a
## non-displayed discipline (e.g. the secondary weapon earning kill credit)
## don't stomp the bar.
var _mastery_discipline: int = -1

@onready var moveable_windows_container: Node = %MoveableWindows

func _ready() -> void:
	# ADR 0009 Stage B: this HUD now lives in the persistent local-player UI layer,
	# which only ever exists for the LOCAL player — so the old remote-player gate
	# is gone. The session-scoped UI below is built ONCE here; the body's bars +
	# component signals are (re)wired per spawn / map change in bind_player().

	# Instantiate and add PartyWindow
	party_window_instance = party_window_scene.instantiate()
	if moveable_windows_container:
		moveable_windows_container.add_child(party_window_instance)
	else:
		add_child(party_window_instance) # Fallback
		push_error("MoveableWindows node not found. Adding PartyWindow as child of player_HUD.")
	party_window_instance.hide()

	# Connect to PartyManager invite signal
	PartyManager.party_invite_received.connect(_on_party_invite_received)

	# Connect to TradeManager signals for player-to-player trading
	TradeManager.trade_request_received.connect(_on_trade_request_received)
	TradeManager.trade_session_opened.connect(_on_trade_session_opened)

	# Setup Scrolling Log
	var scrolling_log_instance = scrolling_log_scene.instantiate()
	add_child(scrolling_log_instance)
	LogManager.set_scrolling_log(scrolling_log_instance)

	# Setup Chat Window
	var chat_window_instance = chat_window_scene.instantiate()
	add_child(chat_window_instance)

	# Setup Ping Display (top-right corner)
	var ping_label = Label.new()
	ping_label.name = "PingDisplay"
	ping_label.set_script(ping_display_script)
	ping_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ping_label.offset_left = -120
	ping_label.offset_top = 8
	ping_label.offset_right = -8
	ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(ping_label)


## Binds the HUD bars to the local player body — called by LocalPlayerUI on every
## spawn / map change. The body's component signals are auto-cleaned when it is
## freed, so connecting the new body each bind is safe.
func bind_player(body) -> void:
	if player == body:
		return
	player = body
	if not is_instance_valid(player):
		return

	health_bar.max_value = player.health_component.max_health
	health_bar.value = player.health_component.current_health
	hp_value_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)

	mana_bar.max_value = player.mana_component.max_mana
	mana_bar.value = player.mana_component.current_mana
	mp_value_label.text = str(player.mana_component.current_mana) + "/" + str(player.mana_component.max_mana)

	experience_bar.max_value = player.level_component.get_exp_to_next_level()
	experience_bar.value = player.level_component.experience
	exp_percent_label.text = "%0.2f" % (float(player.level_component.experience)/player.level_component.get_exp_to_next_level()*100) + "%"

	level_label.text = "LV.[color=yellow]%s[/color]" % str(player.level_component.level)

	player.health_component.health_changed.connect(_on_health_changed)
	player.health_component.died.connect(_on_player_died)
	player.mana_component.mana_changed.connect(_on_mana_changed)
	player.level_component.experience_changed.connect(_on_experience_changed)
	player.level_component.leveled_up.connect(_on_level_changed)

	# Mastery bar tracks the wielded weapon's discipline; repoint it on weapon swap.
	if is_instance_valid(player.weapon_mastery_component):
		player.weapon_mastery_component.mastery_xp_changed.connect(_on_mastery_xp_changed)
		player.weapon_mastery_component.mastery_level_changed.connect(_on_mastery_level_changed)
	if is_instance_valid(player.equipment_component):
		player.equipment_component.active_weapon_changed.connect(_on_active_weapon_changed_mastery)
	# Mastery is loaded with its signals suppressed, so the initial bind below can
	# read a stale 0. Refresh again on the post-load stats_changed — the same wake-up
	# that re-pushes HP/MP after _load_data — so the bar lands on real values.
	if is_instance_valid(player.stats_component):
		player.stats_component.stats_changed.connect(_refresh_mastery_display)
	_refresh_mastery_display()


func unbind_player() -> void:
	# Body component connections die with the freed body; just clear the ref.
	player = null

func _on_party_invite_received(inviter_id: int, inviter_username: String, party_id: int):
	var invite_popup = party_invite_popup_scene.instantiate()
	add_child(invite_popup)
	invite_popup.set_invite_data(inviter_id, inviter_username, party_id)
	invite_popup.show()
	# Juice: an attention ping so an off-screen party invite is noticed.
	AudioManager.play_ui_sfx("res://assets/sounds/generated/mark_ping.wav")


## An incoming trade request — show an accept/decline popup.
func _on_trade_request_received(_requester_id: int, requester_name: String) -> void:
	if is_instance_valid(_trade_request_popup):
		_trade_request_popup.queue_free()
	_trade_request_popup = TradeRequestPopup.create(requester_name)
	if moveable_windows_container:
		moveable_windows_container.add_child(_trade_request_popup)
	else:
		add_child(_trade_request_popup)
	_trade_request_popup.present()
	# Juice: an attention ping so an off-screen trade request is noticed (mirrors
	# the party-invite ping above).
	AudioManager.play_ui_sfx("res://assets/sounds/generated/mark_ping.wav")


## A trade session has been established — open the dual-offer trade window.
func _on_trade_session_opened(partner_id: int, partner_name: String) -> void:
	if not is_instance_valid(_trade_window):
		_trade_window = TradeWindow.create_player_window()
		if moveable_windows_container:
			moveable_windows_container.add_child(_trade_window)
		else:
			add_child(_trade_window)
	_trade_window.open_session(partner_id, partner_name)

func _input(event: InputEvent) -> void:
	if not is_instance_valid(player):
		return
	if player.player_id != multiplayer.get_unique_id():
		return

	if InputManager.is_locked():
		return

	if event.is_action_pressed("OpenPartyWindow"):
		party_window_instance.visible = not party_window_instance.visible
		get_viewport().set_input_as_handled()

	if event.is_action_pressed("ui_cancel"):
		var any_window_was_open = false
		
		# Explicitly hide party_window_instance if it's visible
		if party_window_instance.visible:
			party_window_instance.visible = false
			any_window_was_open = true

		for window in get_tree().get_nodes_in_group("ui_window"):
			# Ensure we don't try to hide party_window_instance twice
			if window is Control and window.visible and window != party_window_instance:
				window.visible = false
				any_window_was_open = true
		
		if any_window_was_open:
			get_viewport().set_input_as_handled()

func _on_player_died(_killer: Node) -> void:
	_is_dead_ui = true
	# Lock input so no other windows can be opened
	InputManager.set_input_locked(true)
	# Close all open UI windows
	if party_window_instance.visible:
		party_window_instance.visible = false
	for window in get_tree().get_nodes_in_group("ui_window"):
		if window is Control and window.visible:
			window.visible = false
	# Maple-style death beat: a somber sting + a dark vignette fading in
	# under the popup. Local-only cosmetics.
	AudioManager.play_ui_sfx("res://assets/sounds/generated/death_sting.wav")
	_fade_death_vignette(0.55, 0.6)
	# Show death popup
	if not is_instance_valid(death_popup_instance):
		death_popup_instance = death_popup_scene.instantiate()
		add_child(death_popup_instance)
		death_popup_instance.set_player(player)
	death_popup_instance.show()

func _on_health_changed(new_health: int, _max_health: int) -> void:
	if not is_instance_valid(player):
		return
	health_bar.max_value = _max_health
	health_bar.value = new_health
	hp_value_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)
	_update_low_hp_warning(float(new_health) / float(max(1, _max_health)), new_health > 0)
	# Clear the death UI when health is restored (respawned). Gated on the death
	# flag, NOT on the popup being visible — the respawn button hides the popup
	# synchronously, so by the time this server-confirmed heal arrives the popup is
	# already hidden; a `.visible` gate would skip the vignette fade + input unlock,
	# leaving the dim stuck on screen and the next death un-revivable.
	if new_health > 0 and _is_dead_ui:
		_is_dead_ui = false
		if is_instance_valid(death_popup_instance):
			death_popup_instance.hide()
		InputManager.set_input_locked(false)
		_fade_death_vignette(0.0, 0.4)

var _death_vignette: ColorRect = null
var _vignette_tween: Tween = null
var _is_dead_ui: bool = false

const LOW_HP_FRACTION := 0.25
var _low_hp_overlay: ColorRect = null
var _low_hp_tween: Tween = null
var _low_hp_active: bool = false


## Fades the full-screen death dim to `target_alpha` over `dur`. Built lazily,
## mouse-transparent, and kept below the popup so the Respawn button stays
## clickable.
func _fade_death_vignette(target_alpha: float, dur: float) -> void:
	if not is_instance_valid(_death_vignette):
		_death_vignette = ColorRect.new()
		_death_vignette.color = Color(0.10, 0.02, 0.03, 0.0)
		_death_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_death_vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_death_vignette)
	if _vignette_tween and _vignette_tween.is_valid():
		_vignette_tween.kill()
	_vignette_tween = create_tween()
	_vignette_tween.tween_property(_death_vignette, "color:a", target_alpha, dur)


## Pulsing red screen tint while alive and below LOW_HP_FRACTION — a "you're in
## danger" cue for the potion-loop survival model. Built lazily, mouse-transparent,
## kept behind the HUD bars. Starts/stops only on threshold crossings.
func _update_low_hp_warning(frac: float, alive: bool) -> void:
	var want: bool = alive and frac > 0.0 and frac <= LOW_HP_FRACTION
	if want == _low_hp_active:
		return
	_low_hp_active = want
	if want:
		if not is_instance_valid(_low_hp_overlay):
			_low_hp_overlay = ColorRect.new()
			_low_hp_overlay.color = Color(0.75, 0.05, 0.05, 0.0)
			_low_hp_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_low_hp_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
			add_child(_low_hp_overlay)
			move_child(_low_hp_overlay, 0)
		if _low_hp_tween and _low_hp_tween.is_valid():
			_low_hp_tween.kill()
		_low_hp_tween = create_tween().set_loops()
		_low_hp_tween.tween_property(_low_hp_overlay, "color:a", 0.28, 0.5)
		_low_hp_tween.tween_property(_low_hp_overlay, "color:a", 0.06, 0.5)
	else:
		if _low_hp_tween and _low_hp_tween.is_valid():
			_low_hp_tween.kill()
		if is_instance_valid(_low_hp_overlay):
			var t: Tween = create_tween()
			t.tween_property(_low_hp_overlay, "color:a", 0.0, 0.3)


func _on_mana_changed(new_mana: int, _max_mana: int) -> void:
	if not is_instance_valid(player):
		return
	mana_bar.max_value = _max_mana
	mana_bar.value = new_mana
	mp_value_label.text = str(player.mana_component.current_mana) + "/" + str(player.mana_component.max_mana)

func _on_experience_changed(new_value: int, _exp_to_level: int) -> void:
	if not is_instance_valid(player):
		return
	experience_bar.max_value = _exp_to_level
	experience_bar.value = new_value
	exp_percent_label.text = "%0.2f" % (float(player.level_component.experience)/player.level_component.get_exp_to_next_level()*100) + "%"


func _on_level_changed(new_value: int) -> void:
	level_label.text = "LV.[color=yellow]%s[/color]" % str(new_value)


## Rebuilds the mastery bar from scratch for the player's CURRENT active
## (wielded) discipline. Called on bind and whenever the active weapon changes.
func _refresh_mastery_display() -> void:
	if not is_instance_valid(player):
		return
	var wm = player.weapon_mastery_component
	if not is_instance_valid(wm):
		mastery_bar.visible = false
		return
	mastery_bar.visible = true
	var disc: int = wm.get_active_discipline()
	_mastery_discipline = disc
	_update_mastery_bar(disc, wm.get_mastery_xp(disc), wm.get_xp_to_next_level(disc), wm.get_mastery_level(disc))


## Paints the bar + labels for a discipline's mastery progress. At the cap the
## bar fills solid and reads "MAX" instead of a percentage.
func _update_mastery_bar(disc: int, xp: int, xp_to_next: int, level: int) -> void:
	var disc_name: String = ResourceManager.get_class_name(disc).to_upper()
	if level >= WeaponMasteryComponent.MASTERY_CAP:
		mastery_bar.max_value = 1
		mastery_bar.value = 1
		mastery_label.text = "%s MASTERY · MAX" % disc_name
		mastery_percent_label.text = ""
		return
	mastery_bar.max_value = max(1, xp_to_next)
	mastery_bar.value = xp
	mastery_label.text = "%s MASTERY · %d" % [disc_name, level]
	mastery_percent_label.text = "%d%%" % int(round(float(xp) / float(max(1, xp_to_next)) * 100.0))


func _on_mastery_xp_changed(discipline: int, current_xp: int, xp_to_next: int) -> void:
	# Only the wielded discipline drives the bar; ignore credit to other slots.
	if discipline != _mastery_discipline:
		return
	if not is_instance_valid(player) or not is_instance_valid(player.weapon_mastery_component):
		return
	_update_mastery_bar(discipline, current_xp, xp_to_next, player.weapon_mastery_component.get_mastery_level(discipline))


func _on_mastery_level_changed(discipline: int, _new_level: int) -> void:
	if discipline != _mastery_discipline:
		return
	_refresh_mastery_display()


func _on_active_weapon_changed_mastery(_active_weapon: String, _active_item) -> void:
	_refresh_mastery_display()
