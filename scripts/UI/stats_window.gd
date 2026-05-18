class_name StatsWindow
extends Control

@onready var stats_window: Control = $"."
@onready var stats_panel: Panel = $StatsPanel
@onready var window_title_label: Label = $Label

@onready var name_string_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/NameContainer/NameStringLabel
@onready var class_string_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/ClassContainer/ClassStringLabel
@onready var level_string_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/LevelContainer/LevelStringLabel
@onready var experience_string_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/ExperienceContainer/ExperienceStringLabel
@onready var health_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/HealthContainer/HealthAmountLabel
@onready var health_regen_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/HealthRegenContainer/HealthRegenAmountLabel
@onready var mana_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/ManaContainer/ManaAmountLabel
@onready var mana_regen_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/ManaRegenContainer/ManaRegenAmountLabel

@onready var str_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/STRContainer/STRAmountLabel
@onready var dex_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/DEXContainer/DEXAmountLabel
@onready var int_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/INTContainer/INTAmountLabel
@onready var luk_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/LUKContainer/LUKAmountLabel
@onready var dmg_range_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/DMGRangeContainer/DMGRangeAmountLabel
@onready var weapon_attack_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/WeaponAttackContainer/WeaponAttackAmountLabel
@onready var magic_attack_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/MagicAttackContainer/MagicAttackAmountLabel
@onready var crit_rate_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/CritRateContainer/CritRateAmountLabel
@onready var crit_dmg_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/CritDmgContainer/CritDmgAmountLabel
@onready var defense_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/DefenseContainer/DefenseAmountLabel
@onready var magic_defense_amount_label: Label = $StatsPanel/ScrollContainer/MarginContainer/VBoxContainer/MagicDefenseContainer/MagicDefenseAmountLabel

var player: MultiplayerPlayerV2

var is_dragging = false
var drag_offset = Vector2()
var _ui_dirty: bool = false

func _ready() -> void:
	# Add to ui_window group for drop detection
	add_to_group("ui_window")
	
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		
	if multiplayer.get_unique_id() == player.player_id:
		player.stats_component.stats_changed.connect(_mark_ui_dirty)
		player.level_component.leveled_up.connect(_mark_ui_dirty.unbind(1))
		player.level_component.experience_changed.connect(_mark_ui_dirty.unbind(2))
		player.health_component.health_changed.connect(_mark_ui_dirty.unbind(2))
		player.class_component.class_changed.connect(_mark_ui_dirty.unbind(1))

		update_stats_window()

func _process(_delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenStatsWindow"):
			if stats_window.visible:
				stats_window.visible = false
			elif not InputManager.is_locked():
				stats_window.visible = true
				
	if is_dragging:
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var window_size = size
		
		new_position.x = clamp(new_position.x, 0, viewport_size.x - window_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - window_size.y)
		
		global_position = new_position

func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title_label.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
				self.move_to_front()
		else:
			is_dragging = false
			

func _mark_ui_dirty() -> void:
	if _ui_dirty:
		return
	_ui_dirty = true
	call_deferred("_flush_ui_update")


func _flush_ui_update() -> void:
	if not _ui_dirty:
		return
	_ui_dirty = false
	update_stats_window()


func update_stats_window():
	name_string_label.text = player.username
	class_string_label.text = str(Constants.ClassType.find_key(player.class_component.current_class))
	level_string_label.text = str(int(player.level_component.level))
	experience_string_label.text = str(int(player.level_component.experience)) + "/" + str(int(player.level_component.get_exp_to_next_level()))
	health_amount_label.text = str(player.health_component.current_health) + "/" + str(player.health_component.max_health)
	health_regen_amount_label.text = str(player.stats_component.stats.get(Constants.StatType.HPREGEN).total_value)
	mana_amount_label.text = str(player.mana_component.current_mana) + "/" + str(player.mana_component.max_mana)
	mana_regen_amount_label.text = str(player.stats_component.stats.get(Constants.StatType.MPREGEN).total_value)
	
	str_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.STRENGTH).total_value, player.stats_component.stats.get(Constants.StatType.STRENGTH).base_value, player.stats_component.stats.get(Constants.StatType.STRENGTH).combined_bonus_value]	
	dex_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.DEXTERITY).total_value, player.stats_component.stats.get(Constants.StatType.DEXTERITY).base_value, player.stats_component.stats.get(Constants.StatType.DEXTERITY).combined_bonus_value]	
	int_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).total_value, player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).base_value, player.stats_component.stats.get(Constants.StatType.INTELLIGENCE).combined_bonus_value]	
	luk_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.LUCK).total_value, player.stats_component.stats.get(Constants.StatType.LUCK).base_value, player.stats_component.stats.get(Constants.StatType.LUCK).combined_bonus_value]	
	
	dmg_range_label.text = "%d ~ %d" % [player.combat_component.min_damage, player.combat_component.max_damage]
	weapon_attack_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.WEAPONATTACK).total_value, player.stats_component.stats.get(Constants.StatType.WEAPONATTACK).base_value, player.stats_component.stats.get(Constants.StatType.WEAPONATTACK).combined_bonus_value]
	magic_attack_amount_label.text = "%d (%d+%d)" % [player.stats_component.stats.get(Constants.StatType.MAGICATTACK).total_value, player.stats_component.stats.get(Constants.StatType.MAGICATTACK).base_value, player.stats_component.stats.get(Constants.StatType.MAGICATTACK).combined_bonus_value]
	crit_rate_amount_label.text = "%d%%" % [player.stats_component.stats.get(Constants.StatType.CRITCHANCE).total_value]
	crit_dmg_amount_label.text = "%d%%" % [player.stats_component.stats.get(Constants.StatType.CRITDAMAGE).total_value]
	defense_amount_label.text = "%d" % player.stats_component.stats.get(Constants.StatType.DEFENSE).total_value
	magic_defense_amount_label.text = "%d" % player.stats_component.stats.get(Constants.StatType.MAGICDEFENSE).total_value
