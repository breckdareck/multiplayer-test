extends Control

@onready var stats_window: Window = $StatsWindow
@onready var stats_panel: Panel = $StatsWindow/StatsPanel
@onready var str_amount_label: Label = $StatsWindow/StatsPanel/VBoxContainer/STRContainer/STRAmountLabel
@onready var dex_amount_label: Label = $StatsWindow/StatsPanel/VBoxContainer/DEXContainer/DEXAmountLabel
@onready var int_amount_label: Label = $StatsWindow/StatsPanel/VBoxContainer/INTContainer/INTAmountLabel
@onready var vit_amount_label: Label = $StatsWindow/StatsPanel/VBoxContainer/VITContainer/VITAmountLabel

var player: MultiplayerPlayerV2

func _ready() -> void:
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		
	if multiplayer.get_unique_id() == player.player_id:
		player.stats_component.stats_changed.connect(update_stats_window)
		
		update_stats_window()

func _process(delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenStatsWindow"):
			stats_window.visible = !stats_window.visible


func update_stats_window():
	str_amount_label.text = str(player.stats_component.current_strength)
	dex_amount_label.text = str(player.stats_component.current_dexterity)
	int_amount_label.text = str(player.stats_component.current_intelligence)
	vit_amount_label.text = str(player.stats_component.current_vitality)
	
