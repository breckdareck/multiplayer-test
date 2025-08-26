extends Control

@onready var stats_window: Control = $"."
@onready var stats_panel: Panel = $StatsPanel
@onready var window_title_label: Label = $Label
@onready var str_amount_label: Label = $StatsPanel/VBoxContainer/STRContainer/STRAmountLabel
@onready var dex_amount_label: Label = $StatsPanel/VBoxContainer/DEXContainer/DEXAmountLabel
@onready var int_amount_label: Label = $StatsPanel/VBoxContainer/INTContainer/INTAmountLabel
@onready var vit_amount_label: Label = $StatsPanel/VBoxContainer/VITContainer/VITAmountLabel

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()

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
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset


func update_stats_window():
	str_amount_label.text = str(player.stats_component.current_strength)
	dex_amount_label.text = str(player.stats_component.current_dexterity)
	int_amount_label.text = str(player.stats_component.current_intelligence)
	vit_amount_label.text = str(player.stats_component.current_vitality)
	

func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
		else:
			is_dragging = false
