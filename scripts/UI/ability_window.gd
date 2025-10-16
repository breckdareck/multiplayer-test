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

var selected_ability_id: String = ""
var player: MultiplayerPlayerV2
var ability_component: AbilityComponent

var is_dragging = false
var drag_offset = Vector2()

const COLOR_NORMAL = "#FFFFFF"
const COLOR_UPGRADE = "#00FF00" # Green for stat increases
const COLOR_DOWNGRADE = "#FF0000" # Red for stat decreases (e.g., cooldown time)
const COLOR_BASE = "#B0B0B0" # Gray for base stats

func _ready():
	if owner is MultiplayerPlayerV2:
		player = owner as MultiplayerPlayerV2
		ability_component = player.ability_component
		
		if not ability_component:
			push_error("AbilityWindow: Could not find AbilityComponent on player")
			return
	
	# Connect signals
	level_up_button.pressed.connect(on_level_up_button_pressed)
	
	# Connect to ability component signals
	if ability_component:
		ability_component.ability_leveled_up.connect(_on_ability_leveled_up)
		ability_component.ability_learned.connect(_on_ability_learned)
		ability_component.ability_points_changed.connect(_on_ability_points_changed)
		print("AbilityWindow: Connected to ability component signals")
	
	# Load UI
	update_skill_points_display()
	load_ability_list()
	
	# Select first ability if any exist
	if ability_component and not ability_component._ability_levels.is_empty():
		var first_ability_id = ability_component._ability_levels.keys()[0]
		select_ability(first_ability_id)
	else:
		clear_details()


func _process(_delta: float) -> void:
	if not ability_component:
		return
		
	if multiplayer.get_unique_id() == player.player_id:
		if Input.is_action_just_pressed("OpenAbilityWindow"):
			self.visible = !self.visible
			if self.visible:
				# Refresh the display when opening
				update_skill_points_display()
				load_ability_list()
				if selected_ability_id:
					select_ability(selected_ability_id)
			
	if is_dragging:
		global_position = get_global_mouse_position() - drag_offset


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if self.get_global_rect().has_point(get_global_mouse_position()):
				is_dragging = true
				drag_offset = get_global_mouse_position() - global_position
		else:
			is_dragging = false


## Clears the list and generates AbilitySlot nodes for each ability
func load_ability_list():
	if not ability_component:
		return
		
	for child in ability_list_container.get_children():
		child.queue_free()
	
	# Get all abilities from the ability component
	for ability_id in ability_component._ability_levels.keys():
		var ability_data = ResourceManager.get_ability_data(ability_id)
		if not ability_data:
			continue
			
		var current_level = ability_component._ability_levels[ability_id]
		var slot = AbilitySlot.instantiate()
		slot.setup(ability_data, current_level)
		slot.ability_selected.connect(select_ability)
		ability_list_container.add_child(slot)
		
		# Select first ability if none is selected
		if selected_ability_id.is_empty():
			select_ability(ability_id)


## Selects an ability, updates the details panel, and highlights the slot
func select_ability(ability_id: String):
	if not ability_component:
		return
		
	# Deselect previous slot
	if selected_ability_id:
		for child in ability_list_container.get_children():
			if child is AbilitySlot and child.ability_data and child.ability_data.ability_id == selected_ability_id:
				child.set_selected(false)
				break
	
	selected_ability_id = ability_id
	
	# Get ability data from ResourceManager
	var selected_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not selected_data:
		clear_details()
		return
	
	# Get current level from ability component
	var current_level: int = ability_component.get_ability_level(ability_id)
	
	# Select the new slot
	for child in ability_list_container.get_children():
		if child is AbilitySlot and child.ability_data and child.ability_data.ability_id == ability_id:
			child.set_selected(true)
			break
	
	update_details(selected_data, current_level)


## Updates the right-side detail panel with the selected ability's info
func update_details(data: AbilityData, current_level: int):
	if not ability_component:
		return
		
	ability_icon.texture = data.ability_icon
	ability_name_label.text = data.ability_name
	ability_level_label.text = "LEVEL: %d / %d" % [current_level, data.max_level]
	
	var is_max_level = current_level >= data.max_level
	var next_level = current_level + 1
	
	var current_stats: AbilityLevelData = data.get_level_stats(current_level)
	var next_stats: AbilityLevelData = data.get_level_stats(next_level)
	
	# Check prerequisites
	var prereq_met = true
	var prereq_text = ""
	if current_level <= 0 and data.prerequisite_abilities and not data.prerequisite_abilities.is_empty():
		prereq_text = "\n[color=%s]PREREQUISITES:[/color]\n" % COLOR_BASE
		for prereq_ability in data.prerequisite_abilities:
			var required_level = data.prerequisite_abilities[prereq_ability]
			var current_prereq_level = ability_component.get_ability_level(prereq_ability.ability_id)
			var is_met = current_prereq_level >= required_level
			
			if not is_met:
				prereq_met = false
			
			var check_mark = "[color=%s]✓[/color]" if is_met else "[color=%s]✗[/color]"
			var color = COLOR_UPGRADE if is_met else COLOR_DOWNGRADE
			prereq_text += "%s %s: [color=%s]Level %d[/color] (Current: %d)\n" % [
				check_mark % color,
				prereq_ability.ability_name,
				color,
				required_level,
				current_prereq_level
			]
	
	# --- Description and Stats Update ---
	var desc: String
	var mana_cost_text: String
	var cooldown_text: String

	# --- Max Level Display ---
	if is_max_level:
		desc = create_description_text(data, current_stats)
		
		mana_cost_text = str(current_stats.mana_cost) if current_stats else "N/A"
		cooldown_text = "%.1fs" % current_stats.cooldown_time if current_stats and data.ability_type == Constants.AbilityType.ACTIVE else "N/A"
		
		cost_label.text = "Max Level Reached!"
		level_up_button.text = "MAXED"
		level_up_button.disabled = true
		cost_label.add_theme_color_override("font_color", Color(COLOR_NORMAL))

	# --- Level Up Comparison Display ---
	elif next_stats:
		desc = create_description_comparison_text(data, current_stats, next_stats)
		
		# Add prerequisite info to description
		if prereq_text:
			desc += "\n" + prereq_text
		
		# Mana Cost Comparison
		mana_cost_text = format_comparison_text(current_stats.mana_cost, next_stats.mana_cost, false) if current_stats else str(next_stats.mana_cost)
		
		# Cooldown Comparison
		if data.ability_type == Constants.AbilityType.ACTIVE:
			cooldown_text = format_comparison_text(current_stats.cooldown_time, next_stats.cooldown_time, true) if current_stats else "%.1fs" % next_stats.cooldown_time
		else:
			cooldown_text = "N/A"

		# Level Up Cost/Button Logic
		var cost = 1
		var available_points = ability_component.get_available_ability_points()
		var can_level_up = ability_component.can_level_up_ability(data.ability_id)
		
		# Update button text based on current level
		if current_level <= 0:
			level_up_button.text = "LEARN"
		else:
			level_up_button.text = "LEVEL UP"
		
		# Determine why leveling up is blocked
		if not prereq_met:
			cost_label.text = "Prerequisites Not Met!"
			cost_label.add_theme_color_override("font_color", Color(COLOR_DOWNGRADE))
		elif available_points < cost:
			cost_label.text = "Not Enough SP (Need: %d)" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_DOWNGRADE))
		elif current_level <= 0:
			cost_label.text = "Cost to Learn: %d SP" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE) if can_level_up else Color(COLOR_DOWNGRADE))
		else:
			cost_label.text = "Cost to Upgrade: %d SP" % cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE) if can_level_up else Color(COLOR_DOWNGRADE))
		
		level_up_button.disabled = not can_level_up
		
	else:
		clear_details()
		return
		
	# Apply final text values to UI
	description_text.text = desc
	mana_cost_label.text = mana_cost_text
	cooldown_label.text = cooldown_text
	
	# Passive abilities often don't have mana/cooldown
	if data.ability_type == Constants.AbilityType.PASSIVE:
		mana_cost_label.text = "N/A"
		cooldown_label.text = "N/A"


## Helper function to create the final description text for comparison
func create_description_comparison_text(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	var desc_template = data.description
	var output = ""
	
	if current == null: # Level 0 / Unlearned
		output += "[color=%s]Unlearned[/color]\n\n" % COLOR_DOWNGRADE
		output += "[color=%s]NEXT LEVEL (%d) STATS:[/color]\n" % [COLOR_UPGRADE, next.level]
		
		if data.ability_type == Constants.AbilityType.ACTIVE:
			var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_UPGRADE, next.damage_percent])
			output += damage_text
		elif data.ability_type == Constants.AbilityType.PASSIVE:
			var stat_key = next.stat_bonuses.keys()[0] if not next.stat_bonuses.is_empty() else null
			if stat_key:
				var stat_value = next.stat_bonuses.get(stat_key).total_value if next.stat_bonuses.get(stat_key).total_value > 0 else next.stat_bonuses.get(stat_key).percent_bonus_value
				var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [COLOR_UPGRADE, stat_value])
				output += stat_text
			
	else: # Level 1 to Max-1
		var current_damage = current.damage_percent
		var next_damage = next.damage_percent
		
		output += "[color=%s]Current Level (%d) Stats:[/color]\n" % [COLOR_BASE, current.level]
		
		if data.ability_type == Constants.AbilityType.ACTIVE:
			var color = COLOR_UPGRADE if next_damage > current_damage else COLOR_NORMAL
			var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_NORMAL, current_damage])
			output += damage_text
			output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
			output += "Damage: [color=%s]%d%%[/color] [color=%s](+ %d%%)[/color]\n" % [COLOR_BASE, current_damage, color, next_damage - current_damage]

		elif data.ability_type == Constants.AbilityType.PASSIVE:
			var stat_key = current.stat_bonuses.keys()[0] if not current.stat_bonuses.is_empty() else null
			if stat_key:
				var current_stat_bonus = current.stat_bonuses.get(stat_key).total_value if current.stat_bonuses.get(stat_key).total_value > 0 else current.stat_bonuses.get(stat_key).percent_bonus_value
				var next_stat_bonus = next.stat_bonuses.get(stat_key).total_value if next.stat_bonuses.get(stat_key).total_value > 0 else next.stat_bonuses.get(stat_key).percent_bonus_value
				var color = COLOR_UPGRADE
				
				var stat_text = desc_template.replace("$[stat_bonus]", "[color=%s]%d[/color]" % [COLOR_NORMAL, current_stat_bonus])
				output += stat_text
				output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
				output += "%s Bonus: [color=%s]%d[/color] [color=%s](+ %d)[/color]\n" % [str(Constants.StatType.keys()[current.stat_bonuses.get(stat_key).stat_type]), COLOR_BASE, current_stat_bonus, color, next_stat_bonus - current_stat_bonus]
			
	return output


## Helper function to create the final description text for MAX level
func create_description_text(data: AbilityData, current: AbilityLevelData) -> String:
	var desc_template = data.description
	var output = "[color=%s]MAX LEVEL STATS:[/color]\n" % COLOR_UPGRADE
	
	if data.ability_type == Constants.AbilityType.ACTIVE:
		var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%d%%[/color]" % [COLOR_NORMAL, current.damage_percent])
		output += damage_text
	elif data.ability_type == Constants.AbilityType.PASSIVE:
		var stat_key = current.stat_bonuses.keys()[0] if not current.stat_bonuses.is_empty() else null
		if stat_key:
			var stat_value = current.stat_bonuses.get(stat_key).total_value if current.stat_bonuses.get(stat_key).total_value > 0 else current.stat_bonuses.get(stat_key).percent_bonus_value
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
	if not ability_component or selected_ability_id.is_empty():
		return
	
	# Use the ability component's level up method
	if ability_component.level_up_ability(selected_ability_id):
		print("Successfully leveled up ability: %s" % selected_ability_id)
		# UI will be updated by the signal callback
	else:
		print("Failed to level up ability: %s" % selected_ability_id)


## Updates the SP display in the header
func update_skill_points_display():
	if not ability_component:
		skill_points_label.text = "SP: 0"
		return
		
	var points = ability_component.get_available_ability_points()
	skill_points_label.text = "SP: %d" % points


## Signal callback when ability levels up
func _on_ability_leveled_up(ability_id: String, new_level: int):
	print("AbilityWindow: Ability %s leveled up to %d" % [ability_id, new_level])
	
	# Update UI
	update_skill_points_display()
	load_ability_list()
	
	# Re-select if this was the selected ability
	if selected_ability_id == ability_id:
		select_ability(ability_id)


## Signal callback when ability is learned
func _on_ability_learned(ability_id: String):
	print("AbilityWindow: Ability %s learned" % ability_id)
	
	# Update UI
	load_ability_list()
	
	# Auto-select if no ability is selected
	if selected_ability_id.is_empty():
		select_ability(ability_id)


## Signal callback when ability points change
func _on_ability_points_changed(new_total: int):
	print("AbilityWindow: Ability points changed to %d" % new_total)
	
	# Update skill points display
	update_skill_points_display()
	
	# Refresh the details panel to update button state
	if selected_ability_id:
		var selected_data = ResourceManager.get_ability_data(selected_ability_id)
		if selected_data:
			var current_level = ability_component.get_ability_level(selected_ability_id)
			update_details(selected_data, current_level)
