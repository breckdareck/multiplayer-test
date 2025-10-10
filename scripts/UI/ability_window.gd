extends PanelContainer
class_name AbilityWindow

## References to ability data classes
const AbilityData = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")
const AbilityLevelData = preload("res://scripts/Resources/AbilitySystem/AbilityLevelData.gd")
const AbilitySlot = preload("res://scenes/UI/ability_slot.tscn")

## Unique Names from ability_window.tscn
@onready var ability_list_container: VBoxContainer = %AbilityListContainer
@onready var ability_icon: TextureRect = %AbilityIcon
@onready var ability_name_label: Label = %AbilityName
@onready var ability_level_label: Label = %AbilityLevel
@onready var description_text: RichTextLabel = %DescriptionText
@onready var mana_cost_label: RichTextLabel = %ManaCost
@onready var cooldown_label: RichTextLabel = %Cooldown
@onready var cost_label: Label = %CostLabel
@onready var level_up_button: Button = %LevelUpButton
@onready var skill_points_label: Label = %SkillPointsLabel

var current_skill_points: int = 20 ## Mock player skill points
var player_abilities: Dictionary = {} ## Key: AbilityData, Value: Current Level
var selected_ability_id: String = ""

var player: MultiplayerPlayerV2
var is_dragging = false
var drag_offset = Vector2()

# Mocking AbilityType constants for demonstration purposes
const ABILITY_TYPE_ACTIVE = 0
const ABILITY_TYPE_PASSIVE = 1

const COLOR_NORMAL = "#FFFFFF"
const COLOR_UPGRADE = "#00FF00" # Green for stat increases
const COLOR_DOWNGRADE = "#FF0000" # Red for stat decreases (e.g., cooldown time)
const COLOR_BASE = "#B0B0B0" # Gray for base stats

func _ready():
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
	# Connect signals
	level_up_button.pressed.connect(on_level_up_button_pressed)
	
	for abil in player.ability_component._ability_levels.keys():
		var data = ResourceManager.get_ability_data(abil)
		player_abilities[data] = player.ability_component._ability_levels.get(abil)
	# Mock data setup
	setup_mock_abilities()
	update_skill_points_display()
	
	# Load UI and select the first ability
	load_ability_list()
	if !player_abilities.is_empty():
		var first_ability_id = player_abilities.keys()[0].ability_id
		select_ability(first_ability_id)
	else:
		clear_details()


func _process(_delta: float) -> void:
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenAbilityWindow"):
			self.visible = !self.visible
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset


func _gui_input(event: InputEvent) -> void:
	# Check for a mouse button press (typically the left mouse button).
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if self.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				# Calculate the offset from the node's origin to the mouse position.
				drag_offset = get_global_mouse_position() - global_position
		else:
			is_dragging = false


## Creates mock AbilityData objects and sets player's current levels
func setup_mock_abilities():
	# --- MOCK ABILITY 1: Fireball (Active) ---
	var fireball_data = AbilityData.new()
	fireball_data.ability_id = "FIREBALL_1"
	fireball_data.ability_name = "Fireball"
	fireball_data.ability_icon = preload("uid://c6mv4q0v88j0l")
	fireball_data.max_level = 3
	fireball_data.ability_type = ABILITY_TYPE_ACTIVE
	fireball_data.description = "Launches a fiery projectile dealing $[damage_percent] damage."
	
	# Mock Level Data
	var fb_level_1 = AbilityLevelData.new(1)
	fb_level_1.mana_cost = 5
	fb_level_1.cooldown_time = 3.0
	fb_level_1.damage_percent = 75
	fireball_data.level_data.append(fb_level_1)

	var fb_level_2 = AbilityLevelData.new(2)
	fb_level_2.mana_cost = 8
	fb_level_2.cooldown_time = 2.5
	fb_level_2.damage_percent = 85
	fireball_data.level_data.append(fb_level_2)
	
	var fb_level_3 = AbilityLevelData.new(3)
	fb_level_3.mana_cost = 12
	fb_level_3.cooldown_time = 2.0
	fb_level_3.damage_percent = 100
	fireball_data.level_data.append(fb_level_3)

	# --- MOCK ABILITY 2: Endurance (Passive) ---
	var endurance_data = AbilityData.new()
	endurance_data.ability_id = "ENDURANCE_2"
	endurance_data.ability_name = "Endurance"
	endurance_data.max_level = 5
	endurance_data.ability_type = ABILITY_TYPE_PASSIVE
	endurance_data.description = "Permanently increases your total HP by $[stat_bonus] points."

	# Mock Level Data
	var end_level_1 = AbilityLevelData.new(1)
	end_level_1.stat_bonuses.assign({Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 10)})
	endurance_data.level_data.append(end_level_1)
	
	var end_level_2 = AbilityLevelData.new(2)
	end_level_2.stat_bonuses.assign({Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 20)})
	endurance_data.level_data.append(end_level_2)
	
	var end_level_3 = AbilityLevelData.new(3)
	end_level_3.stat_bonuses.assign({Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 30)})
	endurance_data.level_data.append(end_level_3)
	
	var end_level_4 = AbilityLevelData.new(4)
	end_level_4.stat_bonuses.assign({Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 40)})
	endurance_data.level_data.append(end_level_4)
	
	var end_level_5 = AbilityLevelData.new(5)
	end_level_5.stat_bonuses.assign({Constants.StatType.HEALTH: StatData.new(Constants.StatType.HEALTH, 50)})
	endurance_data.level_data.append(end_level_5)
	
	# --- MOCK ABILITY 2: Love (Passive) ---
	var love_data = AbilityData.new()
	love_data.ability_id = "LOVE_2"
	love_data.ability_name = "Love"
	love_data.max_level = 10
	love_data.ability_type = ABILITY_TYPE_PASSIVE
	love_data.description = "Permanently increases your Love for Amory by $[stat_bonus] points."
	
	# Mock Level Data
	for i in range(1, 11):
		var love_level = AbilityLevelData.new(i)
		love_level.stat_bonuses.assign({Constants.StatType.WEAPONATTACK: StatData.new(Constants.StatType.WEAPONATTACK, i)})
		love_data.level_data.append(love_level)
	
	# --- MOCK ABILITY 3+ ---
	for i in range(0, 10):
		var test_data = AbilityData.new()
		test_data.ability_id = "TEST_%d" % i
		test_data.ability_name = "Test %d" % i
		test_data.max_level = 1
		test_data.ability_type = ABILITY_TYPE_PASSIVE
		test_data.description = "Test Test Test %d" % i
		var test_level = AbilityLevelData.new(1)
		test_data.level_data.append(test_level)
		player_abilities[test_data] = 0
		
	
	# Set player's current levels
	player_abilities[fireball_data] = 0
	player_abilities[endurance_data] = 3
	player_abilities[love_data] = 0

## Clears the list and generates AbilitySlot nodes for each ability
func load_ability_list():
	for child in ability_list_container.get_children():
		child.queue_free()
		
	for ability_data_resource in player_abilities.keys():
		var current_level = player_abilities[ability_data_resource]
		var slot = AbilitySlot.instantiate()
		slot.setup(ability_data_resource, current_level)
		slot.ability_selected.connect(select_ability)
		ability_list_container.add_child(slot)
		
		# Immediately select the first ability if none is selected
		if selected_ability_id.is_empty() and ability_data_resource.ability_id:
			select_ability(ability_data_resource.ability_id)

## Selects an ability, updates the details panel, and highlights the slot
func select_ability(ability_id: String):
	# Deselect previous slot
	if selected_ability_id:
		for child in ability_list_container.get_children():
			if child is AbilitySlot and child.ability_data and child.ability_data.ability_id == selected_ability_id:
				child.set_selected(false)
				break
	
	selected_ability_id = ability_id
	
	# Find and select the new slot
	var selected_data: AbilityData = null
	var current_level: int = 0
	
	for ability_data_resource in player_abilities.keys():
		if ability_data_resource.ability_id == ability_id:
			selected_data = ability_data_resource
			current_level = player_abilities[ability_data_resource]
			break
			
	for child in ability_list_container.get_children():
		if child is AbilitySlot and child.ability_data and child.ability_data.ability_id == ability_id:
			child.set_selected(true)
			break
			
	if selected_data:
		update_details(selected_data, current_level)
	else:
		clear_details()

## Updates the right-side detail panel with the selected ability's info
func update_details(data: AbilityData, current_level: int):
	ability_icon.texture = data.ability_icon
	ability_name_label.text = data.ability_name
	ability_level_label.text = "LEVEL: %d / %d" % [current_level, data.max_level]
	
	var is_max_level = current_level >= data.max_level
	var next_level = current_level + 1
	
	var current_stats: AbilityLevelData = data.get_level_stats(current_level)
	var next_stats: AbilityLevelData = data.get_level_stats(next_level)
	
	# --- Description and Stats Update ---
	var desc: String
	var mana_cost_text: String
	var cooldown_text: String

	# --- Max Level Display ---
	if is_max_level:
		# Display current stats only
		desc = create_description_text(data, current_stats)
		
		mana_cost_text = str(current_stats.mana_cost) if current_stats else "N/A"
		cooldown_text = "%.1fs" % current_stats.cooldown_time if current_stats and data.ability_type == ABILITY_TYPE_ACTIVE else "N/A"
		
		cost_label.text = "Max Level Reached!"
		level_up_button.text = "MAXED"
		level_up_button.disabled = true
		cost_label.add_theme_color_override("font_color", Color(COLOR_NORMAL))

	# --- Level Up Comparison Display (Level 0 to Max-1) ---
	elif next_stats:
		# Always display next level's potential stats for the comparison
		desc = create_description_comparison_text(data, current_stats, next_stats)
		
		# Mana Cost Comparison
		mana_cost_text = format_comparison_text(current_stats.mana_cost, next_stats.mana_cost, false) if current_stats else str(next_stats.mana_cost)
		
		# Cooldown Comparison (Lower is better, so use COLOR_DOWNGRADE for increases, COLOR_UPGRADE for decreases)
		if data.ability_type == ABILITY_TYPE_ACTIVE:
			cooldown_text = format_comparison_text(current_stats.cooldown_time, next_stats.cooldown_time, true) if current_stats else "%.1fs" % next_stats.cooldown_time
		else:
			cooldown_text = "N/A"

		# Level Up Cost/Button Logic
		var cost = 1 # Simple cost: level_to_reach
		cost_label.text = "Cost to Upgrade: %d SP" % cost
		level_up_button.text = "LEVEL UP"
		
		var can_level_up = current_skill_points >= cost
		level_up_button.disabled = not can_level_up
		cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE) if can_level_up else Color(COLOR_DOWNGRADE))
		
	# --- Fallback/Error ---
	else:
		clear_details()
		return
		
	# Apply final text values to UI
	description_text.text = desc
	mana_cost_label.text = mana_cost_text
	cooldown_label.text = cooldown_text
	
	# Passive abilities often don't have mana/cooldown, display N/A for those.
	if data.ability_type == ABILITY_TYPE_PASSIVE:
		mana_cost_label.text = "N/A"
		cooldown_label.text = "N/A"

## Helper function to create the final description text for comparison
func create_description_comparison_text(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	var desc_template = data.description
	var output = ""
	
	if current == null: # Level 0 / Unlearned
		output += "[color=%s]Unlearned[/color]\n\n" % COLOR_DOWNGRADE
		output += "[color=%s]NEXT LEVEL (%d) STATS:[/color]\n" % [COLOR_UPGRADE, next.level]
		
		if data.ability_type == ABILITY_TYPE_ACTIVE:
			var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_UPGRADE, next.damage_percent])
			output += damage_text
		elif data.ability_type == ABILITY_TYPE_PASSIVE:
			var stat_key = next.stat_bonuses.keys()[0] if not next.stat_bonuses.is_empty() else "N/A"
			var stat_value = next.stat_bonuses.get(stat_key, 0).total_value if not next.stat_bonuses.is_empty() else 0
			var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [COLOR_UPGRADE, stat_value])
			output += stat_text
			
	else: # Level 1 to Max-1
		var current_damage = current.damage_percent
		var next_damage = next.damage_percent
		
		output += "[color=%s]Current Level (%d) Stats:[/color]\n" % [COLOR_BASE, current.level]
		
		if data.ability_type == ABILITY_TYPE_ACTIVE:
			var color = COLOR_UPGRADE if next_damage > current_damage else COLOR_NORMAL
			var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_NORMAL, current_damage])
			output += damage_text
			output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
			output += "Damage: [color=%s]%d%%[/color] [color=%s](+ %d%%)[/color]\n" % [COLOR_BASE, current_damage, color, next_damage - current_damage]

		elif data.ability_type == ABILITY_TYPE_PASSIVE:
			var current_stat_bonus = current.stat_bonuses.get(current.stat_bonuses.keys()[0]).total_value
			var next_stat_bonus = next.stat_bonuses.get(next.stat_bonuses.keys()[0]).total_value
			var color = COLOR_UPGRADE
			
			var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [COLOR_NORMAL, current_stat_bonus])
			output += stat_text
			output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
			output += "%s Bonus: [color=%s]%d[/color] [color=%s](+ %d)[/color]\n" % [str(Constants.StatType.keys()[current.stat_bonuses.get(current.stat_bonuses.keys()[0]).stat_type]), COLOR_BASE, current_stat_bonus, color, next_stat_bonus - current_stat_bonus]
			
	return output

## Helper function to create the final description text for MAX level
func create_description_text(data: AbilityData, current: AbilityLevelData) -> String:
	var desc_template = data.description
	var output = "[color=%s]MAX LEVEL STATS:[/color]\n" % COLOR_UPGRADE
	
	if data.ability_type == ABILITY_TYPE_ACTIVE:
		var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_NORMAL, current.damage_percent])
		output += damage_text
	elif data.ability_type == ABILITY_TYPE_PASSIVE:
		var stat_key = current.stat_bonuses.keys()[0] if not current.stat_bonuses.is_empty() else "N/A"
		var stat_value = current.stat_bonuses.get(stat_key, 0).total_value if not current.stat_bonuses.is_empty() else 0
		var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [COLOR_NORMAL, stat_value])
		output += stat_text
		
	return output

## Helper function for formatting a stat comparison string
func format_comparison_text(current_value, next_value, is_cooldown: bool) -> String:
	var difference = next_value - current_value
	
	if difference == 0:
		return "[color=%s]%s[/color]" % [COLOR_NORMAL, str(current_value)]
	
	# For Cooldown: negative difference (decrease) is an UPGRADE
	var is_upgrade = (is_cooldown and difference < 0) or (not is_cooldown and difference > 0)
	var color = COLOR_UPGRADE if is_upgrade else COLOR_DOWNGRADE
	
	var operator = "-" if is_cooldown and difference < 0 else "+"
	if not is_cooldown and difference < 0:
		operator = "-"

	var diff_string = " ( %s%s )" % [operator, abs(difference)]
	if is_cooldown:
		diff_string = " ( %s%.1fs )" % [operator, abs(difference)]
	
	var current_string = "%.1fs" if is_cooldown else "%s"
	
	return "[color=%s]%s[/color] [color=%s]%s[/color]" % [COLOR_BASE, current_string % current_value, color, diff_string]

## Clears the details panel when no ability is selected
func clear_details():
	selected_ability_id = ""
	ability_icon.texture = null
	ability_name_label.text = "No Ability Selected"
	ability_level_label.text = "LEVEL: 0 / 0"
	description_text.text = "Select an ability from the list on the left to view its details and upgrade it."
	mana_cost_label.text = "N/A"
	cooldown_label.text = "N/A"
	cost_label.text = "No cost"
	level_up_button.text = "LEVEL UP"
	level_up_button.disabled = true

## Handles the Level Up button press
func on_level_up_button_pressed():
	if selected_ability_id.is_empty():
		return # Should not happen if button is enabled
		
	var selected_data: AbilityData = null
	for ability_data_resource in player_abilities.keys():
		if ability_data_resource.ability_id == selected_ability_id:
			selected_data = ability_data_resource
			break
			
	if not selected_data:
		return

	var current_level = player_abilities[selected_data]
	var next_level = current_level + 1
	var cost = 1
	
	if current_skill_points >= cost and next_level <= selected_data.max_level:
		# 1. Deduct cost
		current_skill_points -= cost
		
		# 2. Increase level
		player_abilities[selected_data] = next_level
		
		# 3. Update UI
		update_skill_points_display()
		
		# 4. Refresh List and Details
		load_ability_list() # Re-generate the list to update level display
		select_ability(selected_ability_id) # Re-select to update details
		
		print("Ability %s leveled up to level %d!" % [selected_data.ability_name, next_level])
	else:
		print("Cannot level up: not enough SP or already max level.")

## Updates the SP display in the header
func update_skill_points_display():
	skill_points_label.text = "SP: %d" % current_skill_points
