extends Node

var player

var party_window_scene = preload("res://scenes/UI/party_window.tscn")
var party_window_instance

var party_invite_popup_scene = preload("res://scenes/UI/party_invite_popup.tscn")
var scrolling_log_scene = preload("res://scenes/UI/ScrollingLog.tscn")
var chat_window_scene = preload("res://scenes/UI/ChatWindow.tscn")

@onready var health_bar: TextureProgressBar = $BottomStatsContainer/HealthBar
@onready var hp_value_label: Label = $BottomStatsContainer/HealthBar/HPValueLabel

@onready var mana_bar: TextureProgressBar = $BottomStatsContainer/ManaBar 
@onready var mp_value_label: Label = $BottomStatsContainer/ManaBar/MPValueLabel 

@onready var experience_bar: TextureProgressBar = $BottomStatsContainer/ExperienceBar
@onready var exp_percent_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/EXPPercentLabel

@onready var level_label: RichTextLabel = $BottomStatsContainer/ExperienceBar/LevelPanel/LevelLabel 
@onready var moveable_windows_container: Node = %MoveableWindows

func _ready() -> void:
	if owner is MultiplayerPlayer:
		player = owner
	elif owner is MultiplayerPlayerV2:
		player = owner
		
	if player.player_id != multiplayer.get_unique_id():
		return
	
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

	# Setup Scrolling Log
	var scrolling_log_instance = scrolling_log_scene.instantiate()
	add_child(scrolling_log_instance)
	LogManager.set_scrolling_log(scrolling_log_instance)

	# Setup Chat Window
	var chat_window_instance = chat_window_scene.instantiate()
	add_child(chat_window_instance)

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
	player.mana_component.mana_changed.connect(_on_mana_changed)
	player.level_component.experience_changed.connect(_on_experience_changed)
	player.level_component.leveled_up.connect(_on_level_changed)

func _on_party_invite_received(inviter_id: int, inviter_username: String, party_id: int):
	var invite_popup = party_invite_popup_scene.instantiate()
	add_child(invite_popup)
	invite_popup.set_invite_data(inviter_id, inviter_username, party_id)
	invite_popup.show()

func _input(event: InputEvent) -> void:
	if player.player_id != multiplayer.get_unique_id():
		return

	if event.is_action_pressed("OpenPartyWindow"):
		party_window_instance.visible = not party_window_instance.visible
		get_viewport().set_input_as_handled()

	# NEW: Handle "Esc" key to close all UI windows
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

func _on_health_changed(new_health: int, _max_health: int) -> void:
	"""Updates the ProgressBar value when health changes."""
	health_bar.max_value = _max_health
	health_bar.value = new_health
	hp_value_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)

func _on_mana_changed(new_mana: int, _max_mana: int) -> void:
	"""Updates the ProgressBar value when health changes."""
	mana_bar.max_value = _max_mana
	mana_bar.value = new_mana
	mp_value_label.text = str(player.mana_component.current_mana) + "/" + str(player.mana_component.max_mana)

func _on_experience_changed(new_value: int, _exp_to_level: int) -> void:
	experience_bar.max_value = _exp_to_level
	experience_bar.value = new_value
	exp_percent_label.text = "%0.2f" % (float(player.level_component.experience)/player.level_component.get_exp_to_next_level()*100) + "%"


func _on_level_changed(new_value: int) -> void:
	level_label.text = "LV.[color=yellow]%s[/color]" % str(new_value)
