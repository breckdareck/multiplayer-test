class_name StatsWindow
extends Control

@onready var stats_window: Control = $"."
@onready var stats_panel: Panel = $StatsPanel
@onready var window_title_label: Label = $Label

@onready var name_string_label: Label = $StatsPanel/VBoxContainer/NameContainer/NameStringLabel
@onready var class_string_label: Label = $StatsPanel/VBoxContainer/ClassContainer/ClassStringLabel
@onready var level_string_label: Label = $StatsPanel/VBoxContainer/LevelContainer/LevelStringLabel
@onready var experience_string_label: Label = $StatsPanel/VBoxContainer/ExperienceContainer/ExperienceStringLabel
@onready var health_amount_label: Label = $StatsPanel/VBoxContainer/HealthContainer/HealthAmountLabel
@onready var mana_amount_label: Label = $StatsPanel/VBoxContainer/ManaContainer/ManaAmountLabel

@onready var str_amount_label: Label = $StatsPanel/VBoxContainer/STRContainer/STRAmountLabel
@onready var dex_amount_label: Label = $StatsPanel/VBoxContainer/DEXContainer/DEXAmountLabel
@onready var int_amount_label: Label = $StatsPanel/VBoxContainer/INTContainer/INTAmountLabel
@onready var luk_amount_label: Label = $StatsPanel/VBoxContainer/LUKContainer/LUKAmountLabel
@onready var dmg_range_label: Label = $StatsPanel/VBoxContainer/DMGRangeContainer/DMGRangeAmountLabel

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()

func _ready() -> void:
	# Add to ui_window group for drop detection
	add_to_group("ui_window")
	
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		
	if multiplayer.get_unique_id() == player.player_id:
		player.stats_component.stats_changed.connect(update_stats_window)
		player.level_component.leveled_up.connect(update_stats_window.unbind(1))
		player.level_component.experience_changed.connect(update_stats_window.unbind(2))
		player.health_component.health_changed.connect(update_stats_window.unbind(2))
		player.class_component.class_changed.connect(update_stats_window.unbind(1))
		
		update_stats_window()

func _process(_delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenStatsWindow"):
			stats_window.visible = !stats_window.visible
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset


func update_stats_window():
	name_string_label.text = player.username
	class_string_label.text = str(Constants.ClassType.find_key(player.class_component.current_class))
	level_string_label.text = str(int(player.level_component.level))
	experience_string_label.text = str(int(player.level_component.experience)) + "/" + str(int(player.level_component.get_exp_to_next_level()))
	health_amount_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)
	mana_amount_label.text = "100/100"
	
	str_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.STRENGTH).total_value, player.stats_component.stats.get(Constants.StatType.STRENGTH).base_value, player.stats_component.stats.get(Constants.StatType.STRENGTH).combined_bonus_value]	
	dex_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.DEXTERITY).total_value, player.stats_component.stats.get(Constants.StatType.DEXTERITY).base_value, player.stats_component.stats.get(Constants.StatType.DEXTERITY).combined_bonus_value]	
	int_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).total_value, player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).base_value, player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).combined_bonus_value]	
	luk_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.LUCK).total_value, player.stats_component.stats.get(Constants.StatType.LUCK).base_value, player.stats_component.stats.get(Constants.StatType.LUCK).combined_bonus_value]	
	
	dmg_range_label.text = "%d ~ %d" % [player.combat_component.min_damage, player.combat_component.max_damage]

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
