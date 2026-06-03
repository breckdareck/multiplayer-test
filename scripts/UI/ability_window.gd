extends PanelContainer
class_name AbilityWindow

## References to ability data classes
const ABILITYDATA = preload("res://scripts/Resources/AbilitySystem/AbilityData.gd")
const ABILITYLEVELDATA = preload("res://scripts/Resources/AbilitySystem/AbilityLevelData.gd")

## Unique Names from ability_window.tscn
## The branching skill-tree canvas (replaces the old flat AbilitySlot list).
## Untyped on purpose so the script resolves by path without a global class entry.
@onready var skill_tree_canvas: Control = %SkillTreeCanvas
@onready var ability_icon: TextureRect = %AbilityIcon
@onready var ability_name_label: Label = %AbilityName
@onready var ability_level_label: Label = %AbilityLevel
@onready var description_text: RichTextLabel = %DescriptionText
@onready var mana_cost_label: RichTextLabel = %ManaCost
@onready var cooldown_label: RichTextLabel = %Cooldown
@onready var cost_label: Label = %CostLabel
@onready var level_up_button: Button = %LevelUpButton
@onready var skill_points_label: Label = %SkillPointsLabel
## Weapon-mastery readout for the active discipline tab: the level that grants
## the SP shown beside it, plus XP progress to the next level (= next SP).
@onready var mastery_label: Label = %MasteryLabel
## PR 6: upgrade panel — tier rows with buy buttons + a per-discipline respec.
@onready var upgrades_container: VBoxContainer = %UpgradesContainer
@onready var upgrades_list: VBoxContainer = %UpgradesList
## Per-ability respec (in the details/upgrades panel).
@onready var respec_button: Button = %RespecButton
## Top-header respec (tree / all weapons) — opens a popup.
@onready var respec_menu_button: Button = %RespecMenuButton
## PR 4: TabBar above the list, one tab per weapon discipline. Selecting a
## tab filters the ability list and switches the SP label to the matching
## discipline pool.
@onready var discipline_tab_bar: TabBar = %DisciplineTabBar

## PR 4: discipline keys in tab order. Stays in lockstep with TabBar tab
## indices set in `abilities_window.tscn`.
const DISCIPLINE_TAB_KEYS: Array[String] = ["sword", "bow", "staff", "dagger"]
const DISCIPLINE_TAB_TITLES: Array[String] = ["Sword", "Bow", "Staff", "Dagger"]

## PR 4: which discipline tab is currently selected. Drives both the list
## filter and the SP-label readout.
var _current_discipline_key: String = "sword"

var selected_ability_id: String = ""
## Canvas v2: what kind of node is selected ("ability" or "upgrade") and, for an
## upgrade, which one — drives the right panel's detail + the action button.
var _selected_kind: String = "ability"
var _selected_upgrade_id: String = ""
var player: MultiplayerPlayerV2
var ability_component: AbilityComponent
## PR 8: drives the header mastery readout (level + XP to next = next SP).
var weapon_mastery_component: WeaponMasteryComponent

## Coalesces skill-tree rebuilds. The join/map-transfer ability sync emits
## `ability_learned` once per ability (~80 after the weapon overhaul); routing
## every emit straight into the full `load_ability_list()` rebuild was an
## O(n²) storm that froze the client ~4s on each spawn. Instead, mark a flag
## and rebuild ONCE at end of frame via `_flush_ability_list_rebuild`.
var _ability_list_rebuild_queued: bool = false

const COLOR_NORMAL = "#FFFFFF"
const COLOR_UPGRADE = "#00FF00" # Green for stat increases
const COLOR_DOWNGRADE = "#FF0000" # Red for stat decreases (e.g., cooldown time)
const COLOR_BASE = "#B0B0B0" # Gray for base stats

func _ready():
	# Add to ui_window group for drop detection
	add_to_group("ui_window")
	
	player = owner as MultiplayerPlayerV2
	if player == null:
		# Nested inside the unified hub (game_window): owner is the hub, not the
		# player. Walk ancestors to find the player root.
		var n: Node = get_parent()
		while n != null and not (n is MultiplayerPlayerV2):
			n = n.get_parent()
		player = n as MultiplayerPlayerV2
	if player:
		ability_component = player.ability_component
		if not ability_component:
			push_error("AbilityWindow: Could not find AbilityComponent on player")
			return
		weapon_mastery_component = player.weapon_mastery_component
	
	# Connect signals
	level_up_button.pressed.connect(on_level_up_button_pressed)

	# PR 6: per-ability respec (details panel) + tree/all respec (top header).
	if is_instance_valid(respec_button):
		respec_button.pressed.connect(_on_respec_ability_pressed)
	if is_instance_valid(respec_menu_button):
		respec_menu_button.pressed.connect(_on_respec_button_pressed)

	# PR 4: discipline tab bar drives the list filter + SP label.
	if is_instance_valid(discipline_tab_bar):
		discipline_tab_bar.tab_selected.connect(_on_discipline_tab_selected)

	# Skill-tree canvas v2: a node click selects an ability OR an upgrade node.
	if is_instance_valid(skill_tree_canvas):
		skill_tree_canvas.node_selected.connect(_on_node_selected)
	# v2: upgrades live in the canvas now — keep the legacy right-panel list hidden.
	if is_instance_valid(upgrades_container):
		upgrades_container.visible = false

	# Connect to ability component signals
	if ability_component:
		ability_component.ability_leveled_up.connect(_on_ability_leveled_up)
		ability_component.ability_learned.connect(_on_ability_learned)
		# PR 4: signal now carries (discipline_key, new_total). The handler
		# only refreshes the UI when the changed key matches the open tab.
		ability_component.ability_points_changed.connect(_on_ability_points_changed)
		# PR 4: surface a UI ping when a spend is denied (empty pool, etc).
		if ability_component.has_signal("ability_points_spend_denied"):
			ability_component.ability_points_spend_denied.connect(_on_ability_points_spend_denied)
		# PR 6: refresh the upgrade panel + list badges when upgrades change.
		if ability_component.has_signal("ability_upgrade_purchased"):
			ability_component.ability_upgrade_purchased.connect(_on_ability_upgrade_changed)
		##print("AbilityWindow: Connected to ability component signals")

	# PR 8: keep the header mastery readout (level + XP to next = next SP) live.
	if is_instance_valid(weapon_mastery_component):
		weapon_mastery_component.mastery_level_changed.connect(_on_mastery_changed.unbind(2))
		weapon_mastery_component.mastery_xp_changed.connect(_on_mastery_changed.unbind(3))

	# PR 4: default the tab to the player's currently-active discipline so
	# someone who just swapped to a bow opens the window directly on the Bow
	# tab. Falls back to Sword on lookup failure.
	_select_initial_discipline()

	# Load UI
	update_skill_points_display()
	load_ability_list()

	# Select first ability if any exist
	var first_id_in_tab: String = _first_ability_id_in_current_tab()
	if first_id_in_tab != "":
		select_ability(first_id_in_tab)
	else:
		clear_details()


## Called by the unified hub (game_window) when the Abilities tab is shown. This
## window is now ALWAYS embedded as a hub tab page — it is no longer a free-floating
## window, so it has no drag handling and no self-owned open/close hotkey (the hub
## owns that). Re-syncs the open discipline tab to the currently-wielded weapon and
## refreshes the tree + points (the live signals keep it fresh while open).
func on_shown() -> void:
	if not ability_component:
		return
	# Re-default the tab to whichever discipline the player is currently wielding,
	# so swap-then-open keeps the open tab in sync with the visible weapon.
	_select_initial_discipline()
	update_skill_points_display()
	load_ability_list()
	var first_id := _first_ability_id_in_current_tab()
	if selected_ability_id != "" and _ability_in_current_tab(selected_ability_id):
		select_ability(selected_ability_id)
	elif first_id != "":
		select_ability(first_id)
	else:
		clear_details()


## Rebuilds the skill-tree canvas for the active discipline tab. Collects every
## ability mapped to the discipline (learned or not) and hands them to the
## canvas, which buckets them into the two path columns by tree_path/tree_depth,
## draws the connectors, and renders each node's locked/learnable/owned/maxed
## state. Selection is driven by the callers (window open / tab change / respec).
func load_ability_list():
	if not ability_component or not is_instance_valid(skill_tree_canvas):
		return

	var discipline_abilities: Array = []
	for ability_id in ResourceManager.ability_data.keys():
		var ability_data: AbilityData = ResourceManager.ability_data[ability_id]
		if not ability_data:
			continue
		if _ability_discipline_key(ability_data) != _current_discipline_key:
			continue
		discipline_abilities.append(ability_data)

	skill_tree_canvas.populate(ability_component, discipline_abilities, _current_discipline_key)
	# Restore the highlight after the rebuild.
	if selected_ability_id != "":
		skill_tree_canvas.select_node(_selected_kind, selected_ability_id, _selected_upgrade_id)


## Request a skill-tree rebuild that coalesces with any other request made in
## the same frame (see `_ability_list_rebuild_queued`). Use this instead of
## calling `load_ability_list()` directly from per-item signal handlers that can
## fire in bulk (e.g. the join/map-transfer ability sync).
func _queue_load_ability_list() -> void:
	if _ability_list_rebuild_queued:
		return
	_ability_list_rebuild_queued = true
	call_deferred("_flush_ability_list_rebuild")


func _flush_ability_list_rebuild() -> void:
	if not _ability_list_rebuild_queued:
		return
	_ability_list_rebuild_queued = false
	load_ability_list()


## Canvas v2 click router: an ability node opens the ability detail; an upgrade
## node opens the upgrade detail (with a BUY action).
func _on_node_selected(kind: String, ability_id: String, upgrade_id: String) -> void:
	if kind == "upgrade":
		_select_upgrade(ability_id, upgrade_id)
	else:
		select_ability(ability_id)


## Selects an ability and updates the right detail panel + highlights the node.
func select_ability(ability_id: String):
	if not ability_component:
		return

	_selected_kind = "ability"
	_selected_upgrade_id = ""
	selected_ability_id = ability_id

	# Get ability data from ResourceManager
	var selected_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not selected_data:
		clear_details()
		return

	# Get current level from ability component
	var current_level: int = ability_component.get_ability_level(ability_id)

	# Highlight the selected node in the tree canvas.
	if is_instance_valid(skill_tree_canvas):
		skill_tree_canvas.select_node("ability", ability_id, "")

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
		# PR 4: read the per-discipline pool for the ability we're showing,
		# not the global sum. "Not Enough SP" should fire when the *owning*
		# discipline's pool is empty even if other tabs have spare points.
		var ability_disc_key: String = _ability_discipline_key(data)
		var available_points: int = ability_component.get_available_points_for_discipline(ability_disc_key) if ability_disc_key != "" else 0
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
		
	# PR 6: append an ACTIVE UPGRADES section so the description reflects
	# every owned upgrade (damage %, combo coefficient, bleed, CD, etc.) —
	# the one place that transparently covers all effect types.
	desc += _owned_upgrades_section(data)

	# Apply final text values to UI
	description_text.text = desc
	mana_cost_label.text = mana_cost_text
	cooldown_label.text = cooldown_text

	# PR 6: reflect flat cooldown / mana reductions from owned upgrades in the
	# stat labels (current level's effective value). Only overrides when a
	# reduction is owned, so the level-up comparison stays intact otherwise.
	if data.ability_type == Constants.AbilityType.ACTIVE and ability_component and current_stats:
		var cd_reduction: float = ability_component.get_ability_upgrade_magnitude(data.ability_id, "cooldown_flat_reduction")
		if cd_reduction > 0.0:
			var eff_cd: float = maxf(0.0, current_stats.cooldown_time - cd_reduction)
			cooldown_label.text = "[color=%s]%.1fs[/color]" % [COLOR_UPGRADE, eff_cd]
		var mana_reduction: float = ability_component.get_ability_upgrade_magnitude(data.ability_id, "mana_flat_reduction")
		if mana_reduction > 0.0:
			var eff_mana: int = maxi(0, current_stats.mana_cost - int(mana_reduction))
			mana_cost_label.text = "[color=%s]%d[/color]" % [COLOR_UPGRADE, eff_mana]

	# Passive abilities often don't have mana/cooldown
	if data.ability_type == Constants.AbilityType.PASSIVE:
		mana_cost_label.text = "N/A"
		cooldown_label.text = "N/A"

	# PR 6: rebuild the upgrade tier panel for this ability.
	_refresh_upgrades(data, current_level)


## Builds a BBCode "ACTIVE UPGRADES" block listing owned upgrades for an
## ability (name — effect). Empty when none owned. This is how the
## description "changes with the upgrades" uniformly across every effect
## type, without rewriting each ability's base description text.
func _owned_upgrades_section(data: AbilityData) -> String:
	if not ability_component or data.upgrades == null or data.upgrades.is_empty():
		return ""
	var lines: PackedStringArray = []
	for up in data.upgrades:
		if up != null and ability_component.has_upgrade(data.ability_id, up.upgrade_id):
			lines.append("  [color=%s]%s[/color] — %s" % [COLOR_UPGRADE, up.upgrade_name, up.description])
	if lines.is_empty():
		return ""
	return "\n\n[color=%s]ACTIVE UPGRADES:[/color]\n%s" % [COLOR_UPGRADE, "\n".join(lines)]


## Helper function to create the final description text for comparison
func create_description_comparison_text(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	var output = ""
	
	if current == null: # Level 0 / Unlearned
		output += "[color=%s]Unlearned[/color]\n\n" % COLOR_DOWNGRADE
		output += "[color=%s]NEXT LEVEL (%d) STATS:[/color]\n" % [COLOR_UPGRADE, next.level]
		output += format_ability_description(data, next, COLOR_UPGRADE)
		
		# Show stat bonuses if any exist
		if not next.stat_bonuses.is_empty():
			output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_UPGRADE
			output += format_stat_bonuses(next, COLOR_UPGRADE)
			
	else: # Level 1 to Max-1
		output += "[color=%s]Current Level (%d) Stats:[/color]\n" % [COLOR_BASE, current.level]
		output += format_ability_description(data, current, COLOR_NORMAL)
		
		# Show current stat bonuses if any exist
		if not current.stat_bonuses.is_empty():
			output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_BASE
			output += format_stat_bonuses(current, COLOR_NORMAL)
		
		output += "\n\n[color=%s]NEXT LEVEL (%d) UPGRADE:[/color]\n" % [COLOR_UPGRADE, next.level]
		
		# Show damage/target/hit upgrades for active abilities
		if data.ability_type == Constants.AbilityType.ACTIVE:
			var current_damage = current.damage_percent
			var next_damage = next.damage_percent

			if next_damage != current_damage:
				var color = COLOR_UPGRADE if next_damage > current_damage else COLOR_DOWNGRADE
				var diff = next_damage - current_damage
				var diff_sign = "+" if diff > 0 else ""
				output += "Damage: [color=%s]%s%%[/color] [color=%s](%s%s%%)[/color]\n" % [COLOR_BASE, AbilityData._smart_format_number(current_damage), color, diff_sign, AbilityData._smart_format_number(diff)]

			if data.scaling_data.max_targets_formula:
				var current_target_count = data.scaling_data.max_targets_formula.calculate(current.level)
				var next_target_count = data.scaling_data.max_targets_formula.calculate(next.level)
				if next_target_count != current_target_count:
					var color = COLOR_UPGRADE
					output += "Target Count: [color=%s]%d[/color] [color=%s](%+d)[/color]\n" % [COLOR_BASE, current_target_count, color, next_target_count - current_target_count]

			if data.scaling_data.max_hits_formula:
				var current_hit_count = data.scaling_data.max_hits_formula.calculate(current.level)
				var next_hit_count = data.scaling_data.max_hits_formula.calculate(next.level)
				if next_hit_count != current_hit_count:
					var color = COLOR_UPGRADE
					output += "Hit Count: [color=%s]%d[/color] [color=%s](%+d)[/color]\n" % [COLOR_BASE, current_hit_count, color, next_hit_count - current_hit_count]
		elif data.ability_type == Constants.AbilityType.PASSIVE and data.scaling_data and data.scaling_data.damage_percent_formula:
			# PR 6: passives that use damage_percent_formula as a generic
			# level-scaled value (e.g. Bloodthirst's heal %) need an
			# upgrade-preview line too. Mirrors the active "Damage" diff
			# but labels generically ("Effect") since the value isn't
			# necessarily damage on a passive.
			var cur_val: float = data.scaling_data.damage_percent_formula.calculate(current.level)
			var nxt_val: float = data.scaling_data.damage_percent_formula.calculate(next.level)
			if nxt_val != cur_val:
				var color = COLOR_UPGRADE if nxt_val > cur_val else COLOR_DOWNGRADE
				var diff: float = nxt_val - cur_val
				var diff_sign: String = "+" if diff > 0 else ""
				output += "Effect: [color=%s]%s%%[/color] [color=%s](%s%s%%)[/color]\n" % [COLOR_BASE, AbilityData._smart_format_number(cur_val), color, diff_sign, AbilityData._smart_format_number(diff)]

		# NEW: Show buff duration upgrade
		var buff_duration_diff = format_buff_duration_comparison(data, current, next)
		if not buff_duration_diff.is_empty():
			output += buff_duration_diff
		
		# Show stat bonus upgrades
		if not next.stat_bonuses.is_empty():
			output += format_stat_bonus_comparison(current, next)
			
	return output


## Helper function to create the final description text for MAX level
func create_description_text(data: AbilityData, current: AbilityLevelData) -> String:
	var output = "[color=%s]MAX LEVEL STATS:[/color]\n" % COLOR_UPGRADE
	output += format_ability_description(data, current, COLOR_NORMAL)
	
	# Show stat bonuses if any exist
	if not current.stat_bonuses.is_empty():
		output += "\n\n[color=%s]Stat Bonuses:[/color]\n" % COLOR_NORMAL
		output += format_stat_bonuses(current, COLOR_NORMAL)
		
	return output


## Formats the ability description with damage/target/hit counts
func format_ability_description(data: AbilityData, level_data: AbilityLevelData, color: String) -> String:
	var desc_template = data.description
	var output = ""
	
	if data.ability_type == Constants.AbilityType.ACTIVE:
		var damage_text = desc_template.replace("$[damage_percent]", "[color=%s]%s%%[/color]" % [color, AbilityData._smart_format_number(level_data.damage_percent)])
		# Null-guard the formula access: a utility ability (Smoke Bomb, Banner,
		# Mana Surge, etc.) may have no hits/targets formulas at all. Only call
		# .calculate() when the placeholder is actually present in the template
		# AND the formula exists — skips wasted work and prevents the
		# "Nonexistent function 'calculate' in base 'Nil'" crash.
		var target_text = damage_text
		if "$[target_count]" in target_text and data.scaling_data and data.scaling_data.max_targets_formula:
			target_text = target_text.replace("$[target_count]", "[color=%s]%d[/color]" % [color, data.scaling_data.max_targets_formula.calculate(level_data.level)])
		var hit_text = target_text
		if "$[hit_count]" in hit_text and data.scaling_data and data.scaling_data.max_hits_formula:
			hit_text = hit_text.replace("$[hit_count]", "[color=%s]%d[/color]" % [color, data.scaling_data.max_hits_formula.calculate(level_data.level)])

		# NEW: Handle buff duration placeholder
		if data.applies_buff and data.buff_duration_formula:
			var duration = data.buff_duration_formula.calculate(level_data.level)
			hit_text = hit_text.replace("$[buff_duration]", "[color=%s]%.0fs[/color]" % [color, duration])

		# Stat-bonus placeholder — replaced regardless of whether the ability also
		# applies a buff (an active can grant a stat bonus without a duration).
		var stat_key = level_data.stat_bonuses.keys()[0] if not level_data.stat_bonuses.is_empty() else null
		if stat_key != null:
			var stat_value = level_data.stat_bonuses.get(stat_key).total_value if level_data.stat_bonuses.get(stat_key).total_value > 0 else level_data.stat_bonuses.get(stat_key).percent_bonus_value
			hit_text = hit_text.replace("$[stat_bonus]", "[color=%s]%s[/color]" % [color, AbilityData._smart_format_number(stat_value)])

		output += hit_text
	elif data.ability_type == Constants.AbilityType.PASSIVE:
		var passive_text: String = desc_template
		# PR 6: passives may use $[damage_percent] as a generic level-scaled
		# value (e.g. Bloodthirst's heal %). Pulls directly from
		# scaling_data.damage_percent_formula since level_data.damage_percent
		# is only populated for active abilities.
		if data.scaling_data and data.scaling_data.damage_percent_formula:
			var v: float = data.scaling_data.damage_percent_formula.calculate(level_data.level)
			passive_text = passive_text.replace("$[damage_percent]", "[color=%s]%s%%[/color]" % [color, AbilityData._smart_format_number(v)])
		# Stat bonus path (HP Boost, STR Passive, etc.)
		var stat_key = level_data.stat_bonuses.keys()[0] if not level_data.stat_bonuses.is_empty() else null
		if stat_key != null:
			var stat_value = level_data.stat_bonuses.get(stat_key).total_value if level_data.stat_bonuses.get(stat_key).total_value > 0 else level_data.stat_bonuses.get(stat_key).percent_bonus_value
			passive_text = passive_text.replace("$[stat_bonus]", "[color=%s]%s[/color]" % [color, AbilityData._smart_format_number(stat_value)])
		output += passive_text
	else:
		output += desc_template

	# Named custom values ($[value:KEY]) — applies to active AND passive. Mirrors
	# AbilityData._format_plain_description; the value comes from the SAME formula
	# the ability's AL script reads, so display and gameplay stay in lockstep.
	if data.scaling_data:
		for key in data.scaling_data.custom_value_formulas:
			var f: AbilityScalingFormula = data.scaling_data.custom_value_formulas[key]
			if f:
				output = output.replace("$[value:%s]" % key, "[color=%s]%s[/color]" % [color, AbilityData._smart_format_number(f.calculate(level_data.level))])

	return output


## Formats all stat bonuses for display
func format_stat_bonuses(level_data: AbilityLevelData, color: String) -> String:
	var output = ""
	
	for stat_type in level_data.stat_bonuses:
		var stat_data: StatData = level_data.stat_bonuses[stat_type]
		var stat_name = Constants.StatType.keys()[stat_type]
		
		# Show flat bonus if it exists
		if stat_data.flat_bonus_value > 0:
			output += "  %s: [color=%s]+%s[/color]\n" % [stat_name, color, AbilityData._smart_format_number(stat_data.flat_bonus_value)]

		# Show percent bonus if it exists
		if stat_data.percent_bonus_value > 0:
			output += "  %s: [color=%s]+%s%%[/color]\n" % [stat_name, color, AbilityData._smart_format_number(stat_data.percent_bonus_value)]
	
	return output


## Formats stat bonus comparison between current and next level
func format_stat_bonus_comparison(current: AbilityLevelData, next: AbilityLevelData) -> String:
	var output = ""
	var has_changes = false
	
	# Get all stat types from both levels
	var all_stat_types = {}
	if current and not current.stat_bonuses.is_empty():
		for stat_type in current.stat_bonuses:
			all_stat_types[stat_type] = true
	
	for stat_type in next.stat_bonuses:
		all_stat_types[stat_type] = true
	
	# Compare each stat type
	for stat_type in all_stat_types:
		var current_stat: StatData = current.stat_bonuses.get(stat_type) if current else null
		var next_stat: StatData = next.stat_bonuses.get(stat_type)
		
		if not next_stat:
			continue
			
		var stat_name = Constants.StatType.keys()[stat_type]
		var current_flat = current_stat.flat_bonus_value if current_stat else 0
		var next_flat = next_stat.flat_bonus_value
		var current_percent = current_stat.percent_bonus_value if current_stat else 0.0
		var next_percent = next_stat.percent_bonus_value
		
		# Show flat bonus changes
		if next_flat != current_flat:
			has_changes = true
			var diff = next_flat - current_flat
			var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
			var sign_str: String = "+" if diff > 0 else ""
			output += "%s: [color=%s]+%s[/color] [color=%s](%s%s)[/color]\n" % [stat_name, COLOR_BASE, AbilityData._smart_format_number(current_flat), color, sign_str, AbilityData._smart_format_number(diff)]

		# Show percent bonus changes
		if next_percent != current_percent:
			has_changes = true
			var diff = next_percent - current_percent
			var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
			var sign_str: String = "+" if diff > 0 else ""
			output += "%s: [color=%s]+%s%%[/color] [color=%s](%s%s%%)[/color]\n" % [stat_name, COLOR_BASE, AbilityData._smart_format_number(current_percent), color, sign_str, AbilityData._smart_format_number(diff)]
	
	return output if has_changes else ""


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


func format_buff_info(data: AbilityData, level_data: AbilityLevelData, color: String) -> String:
	if not data.applies_buff:
		return ""
	
	var output = "\n\n[color=%s]Buff Details:[/color]\n" % COLOR_BASE
	var buff: BuffData = data.applies_buff
	
	# Show buff duration
	if data.buff_duration_formula:
		var duration = data.buff_duration_formula.calculate(level_data.level)
		output += "  Duration: [color=%s]%.0fs[/color]\n" % [color, duration]
	elif buff.duration > 0:
		output += "  Duration: [color=%s]%.0fs[/color]\n" % [color, buff.duration]
	else:
		output += "  Duration: [color=%s]Permanent[/color]\n" % color

	return output


func format_buff_duration_comparison(data: AbilityData, current: AbilityLevelData, next: AbilityLevelData) -> String:
	if not data.applies_buff or not data.buff_duration_formula:
		return ""
	
	var current_duration = data.buff_duration_formula.calculate(current.level)
	var next_duration = data.buff_duration_formula.calculate(next.level)
	
	if next_duration == current_duration:
		return ""
	
	var diff = next_duration - current_duration
	var color = COLOR_UPGRADE if diff > 0 else COLOR_DOWNGRADE
	
	return "Buff Duration: [color=%s]%.0fs[/color] [color=%s](%+.0fs)[/color]\n" % [COLOR_BASE, current_duration, color, diff]


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
	# PR 6: hide the upgrade panel when nothing is selected.
	if is_instance_valid(upgrades_container):
		upgrades_container.visible = false


## Handles the action button — context-sensitive in v2: levels/learns the
## selected ability, OR buys the selected upgrade node. UI refreshes via the
## ability_leveled_up / ability_learned / ability_upgrade_purchased signals.
func on_level_up_button_pressed():
	if not ability_component:
		return
	if _selected_kind == "upgrade":
		if selected_ability_id != "" and _selected_upgrade_id != "":
			ability_component.purchase_upgrade(selected_ability_id, _selected_upgrade_id)
		return
	if selected_ability_id.is_empty():
		return
	ability_component.level_up_ability(selected_ability_id)


## Selects an upgrade NODE: fills the right detail panel with the upgrade's info
## and turns the action button into BUY / OWNED / locked-reason.
func _select_upgrade(ability_id: String, upgrade_id: String) -> void:
	if not ability_component:
		return
	var data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if not data or data.upgrades == null:
		return
	var upgrade: AbilityUpgradeData = null
	for up in data.upgrades:
		if up != null and up.upgrade_id == upgrade_id:
			upgrade = up
			break
	if upgrade == null:
		return

	_selected_kind = "upgrade"
	selected_ability_id = ability_id
	_selected_upgrade_id = upgrade_id

	ability_icon.texture = data.ability_icon
	ability_name_label.text = upgrade.upgrade_name
	ability_level_label.text = "%s  ·  Tier %d upgrade" % [data.ability_name, upgrade.tier]
	description_text.text = upgrade.description
	mana_cost_label.text = "N/A"
	cooldown_label.text = "N/A"

	if ability_component.has_upgrade(ability_id, upgrade_id):
		cost_label.text = "Owned"
		cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE))
		level_up_button.text = "OWNED"
		level_up_button.disabled = true
	else:
		var can = ability_component.can_purchase_upgrade(ability_id, upgrade_id)
		var ok: bool = can is Dictionary and can.get("ok", false)
		level_up_button.text = "BUY UPGRADE"
		level_up_button.disabled = not ok
		if ok:
			cost_label.text = "Cost: %d SP" % upgrade.point_cost
			cost_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE))
		else:
			cost_label.text = _upgrade_reason_text(can.get("reason", "") if can is Dictionary else "")
			cost_label.add_theme_color_override("font_color", Color(COLOR_DOWNGRADE))

	if is_instance_valid(upgrades_container):
		upgrades_container.visible = false
	if is_instance_valid(skill_tree_canvas):
		skill_tree_canvas.select_node("upgrade", ability_id, upgrade_id)


## Human-readable reason for a blocked upgrade purchase.
func _upgrade_reason_text(reason: String) -> String:
	match reason:
		"not_learned": return "Learn the ability first"
		"not_maxed": return "Max the ability first"
		"tier_locked": return "Buy the previous tier first"
		"variant_taken": return "Another variant chosen"
		"no_points": return "Not enough SP"
		"already_owned": return "Owned"
		_: return "Locked"


## Re-applies the current selection (ability or upgrade) after a canvas rebuild.
func _reselect() -> void:
	if selected_ability_id == "":
		return
	if _selected_kind == "upgrade" and _selected_upgrade_id != "":
		_select_upgrade(selected_ability_id, _selected_upgrade_id)
	else:
		select_ability(selected_ability_id)


# ============================================================================
# PR 6: Upgrade panel
# ============================================================================

## Tier accent colors for the upgrade rows (T1 / T2 / T3-variant).
const UPGRADE_TIER_COLORS: Array[String] = ["#9fcaff", "#c9a0ff", "#e6c95c"]


## Rebuilds the upgrade tier rows for the selected ability. Hidden entirely
## for abilities that define no upgrades (pre-PR-6 abilities / passives
## without trees).
func _refresh_upgrades(_data: AbilityData, _current_level: int) -> void:
	# Skill-tree v2: upgrades render as nodes in the canvas (branching off each
	# ability), not as a right-panel list. Keep the legacy container hidden.
	if is_instance_valid(upgrades_container):
		upgrades_container.visible = false


## Builds one upgrade row: [Tn] Name ............ <Buy/Owned/Locked>.
func _make_upgrade_row(data: AbilityData, upgrade: AbilityUpgradeData, _current_level: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.tooltip_text = upgrade.get_tooltip_text(ability_component.has_upgrade(data.ability_id, upgrade.upgrade_id))

	var tier_color: String = UPGRADE_TIER_COLORS[clampi(upgrade.tier - 1, 0, UPGRADE_TIER_COLORS.size() - 1)]
	var tier_badge := Label.new()
	tier_badge.text = "T%d" % upgrade.tier
	tier_badge.add_theme_color_override("font_color", Color(tier_color))
	tier_badge.custom_minimum_size = Vector2(26, 0)
	row.add_child(tier_badge)

	var name_label := Label.new()
	name_label.text = upgrade.upgrade_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not upgrade.variant_group.is_empty():
		name_label.text += "  ◆"  # variant marker
	row.add_child(name_label)

	var owned: bool = ability_component.has_upgrade(data.ability_id, upgrade.upgrade_id)
	if owned:
		var owned_label := Label.new()
		owned_label.text = "✓ Owned"
		owned_label.add_theme_color_override("font_color", Color(COLOR_UPGRADE))
		owned_label.custom_minimum_size = Vector2(90, 0)
		owned_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(owned_label)
	else:
		var check: Dictionary = ability_component.can_purchase_upgrade(data.ability_id, upgrade.upgrade_id)
		var buy_btn := Button.new()
		buy_btn.custom_minimum_size = Vector2(90, 24)
		buy_btn.focus_mode = Control.FOCUS_NONE
		if check.ok:
			buy_btn.text = "Buy (%d)" % upgrade.point_cost
			buy_btn.disabled = false
		else:
			buy_btn.disabled = true
			match String(check.reason):
				"tier_locked": buy_btn.text = "Locked"
				"variant_taken": buy_btn.text = "—"
				"no_points": buy_btn.text = "Buy (%d)" % upgrade.point_cost
				"not_learned": buy_btn.text = "Learn first"
				"not_maxed": buy_btn.text = "Max first"
				_: buy_btn.text = "Locked"
		var ability_id := data.ability_id
		var upgrade_id := upgrade.upgrade_id
		buy_btn.pressed.connect(func(): _on_upgrade_buy_pressed(ability_id, upgrade_id))
		row.add_child(buy_btn)

	return row


func _on_upgrade_buy_pressed(ability_id: String, upgrade_id: String) -> void:
	if not ability_component:
		return
	# Server validates + applies; UI refreshes via ability_upgrade_purchased.
	ability_component.purchase_upgrade(ability_id, upgrade_id)


## Refresh the panel + list when an upgrade is purchased (or synced in).
func _on_ability_upgrade_changed(_ability_id: String, _upgrade_id: String) -> void:
	update_skill_points_display()
	load_ability_list()
	_reselect()


## Top-header respec — opens a small popup offering a quick respec of either
## the current weapon discipline (tree) or all weapons. The popup IS the
## confirmation (deliberate two-step: open menu → pick option).
func _on_respec_button_pressed() -> void:
	if not ability_component:
		return
	var menu := PopupMenu.new()
	menu.add_item("Respec %s Tree" % _current_discipline_tab_title(), 0)
	menu.add_item("Respec All Weapons", 1)
	add_child(menu)
	menu.id_pressed.connect(_on_respec_menu_selected)
	# Free the popup once it closes (covers both selection and dismissal).
	menu.popup_hide.connect(menu.queue_free)
	# Anchor just below the top Respec button.
	var anchor: Control = self
	if is_instance_valid(respec_menu_button):
		anchor = respec_menu_button
	menu.position = anchor.get_screen_position() + Vector2(0, anchor.size.y)
	menu.popup()


func _on_respec_menu_selected(id: int) -> void:
	if not ability_component:
		return
	if id == 0:
		ability_component.respec_discipline(_current_discipline_key)
	elif id == 1:
		ability_component.respec_all()
	_refresh_after_respec()


## Per-ability respec — refunds just the selected ability's levels + upgrades.
func _on_respec_ability_pressed() -> void:
	if not ability_component or selected_ability_id.is_empty():
		return
	ability_component.respec_ability(selected_ability_id)
	_refresh_after_respec()


## Shared post-respec UI refresh. Signals already drive most of it; this
## ensures the open panel + header update immediately.
func _refresh_after_respec() -> void:
	update_skill_points_display()
	load_ability_list()
	_reselect()


## Updates the SP display in the header.
## PR 4: reads the active discipline tab's pool, not the global total, so
## the header reflects what the player can actually spend in this tab.
func update_skill_points_display():
	if not ability_component:
		skill_points_label.text = "SP: 0"
		return

	var tab_label: String = _current_discipline_tab_title()
	var points = ability_component.get_available_points_for_discipline(_current_discipline_key)
	skill_points_label.text = "%s SP: %d" % [tab_label, points]
	update_mastery_display()


## PR 8: header readout of the active tab's weapon-mastery level + XP progress.
## Each mastery level grants one SP, so this shows the player how close they are
## to their next point. Reads the discipline matching the open tab (not the
## wielded weapon) so it stays consistent with the SP label beside it.
func update_mastery_display() -> void:
	if not is_instance_valid(mastery_label):
		return
	if not is_instance_valid(weapon_mastery_component):
		mastery_label.text = ""
		return
	var discipline: int = _discipline_key_to_class_type(_current_discipline_key)
	if discipline == -1:
		mastery_label.text = ""
		return
	var level: int = weapon_mastery_component.get_mastery_level(discipline)
	if level >= weapon_mastery_component.MASTERY_CAP:
		mastery_label.text = "Mastery Lv %d (MAX)" % level
		return
	var xp: int = weapon_mastery_component.get_mastery_xp(discipline)
	var xp_to_next: int = weapon_mastery_component._xp_to_next_level(level)
	mastery_label.text = "Mastery Lv %d (%d / %d XP)" % [level, xp, xp_to_next]


## PR 8: refresh the mastery readout when mastery level/XP changes for any
## discipline (cheap; only re-renders the single header label).
func _on_mastery_changed() -> void:
	update_mastery_display()


## Signal callback when ability levels up
func _on_ability_leveled_up(ability_id: String, _new_level: int):
	##print("AbilityWindow: Ability %s leveled up to %d" % [ability_id, new_level])
	
	# Update UI
	update_skill_points_display()
	_queue_load_ability_list()

	# Re-select if this was the selected ability
	if selected_ability_id == ability_id:
		select_ability(ability_id)


## Signal callback when ability is learned
func _on_ability_learned(ability_id: String):
	##print("AbilityWindow: Ability %s learned" % ability_id)

	# Update UI (coalesced — the join/map-transfer sync fires this ~80×/frame)
	_queue_load_ability_list()

	# Auto-select if no ability is selected
	if selected_ability_id.is_empty():
		select_ability(ability_id)


## PR 4: signal callback when ability points change for a single
## discipline. Updates the header only when the changed discipline matches
## the currently-open tab; refreshes button state regardless so the right
## panel reflects the new pool.
func _on_ability_points_changed(discipline_key: String, _new_total: int):
	##print("AbilityWindow: %s points changed to %d" % [discipline_key, _new_total])

	if discipline_key == _current_discipline_key:
		update_skill_points_display()

	# Refresh the detail panel (ability OR upgrade) so the action button updates.
	_reselect()


## PR 4: surface a denial when the player tries to spend a point with an
## empty pool (or on an unmapped ability). Lightweight UI ping only --
## the actual cost label is already painted red by `update_details`.
func _on_ability_points_spend_denied(_ability_id: String, _reason: String) -> void:
	# Trigger an unobtrusive UI feedback (color flash on cost label). The
	# existing red-coloured "Not Enough SP" text covers the empty-pool case
	# already; this is the hook for future audio/animation polish.
	if is_instance_valid(cost_label):
		var prior: Color = cost_label.get_theme_color("font_color")
		cost_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
		await get_tree().create_timer(0.15).timeout
		if is_instance_valid(cost_label):
			cost_label.add_theme_color_override("font_color", prior)


## PR 4: called by the TabBar when the player clicks a discipline tab.
## Switches the filter + SP label, rebuilds the list, and auto-selects the
## first ability in the new tab (if any).
func _on_discipline_tab_selected(tab_index: int) -> void:
	if tab_index < 0 or tab_index >= DISCIPLINE_TAB_KEYS.size():
		return
	_current_discipline_key = DISCIPLINE_TAB_KEYS[tab_index]
	selected_ability_id = ""
	update_skill_points_display()
	load_ability_list()
	var first_id := _first_ability_id_in_current_tab()
	if first_id != "":
		select_ability(first_id)
	else:
		clear_details()


## PR 4: maps an AbilityData to its primary discipline key by reading
## `required_class[0]`. Returns "" for abilities with no required_class --
## those don't fit in any tab and are hidden from the list.
func _ability_discipline_key(ability: AbilityData) -> String:
	if ability == null:
		return ""
	if ability.required_class == null or ability.required_class.is_empty():
		return ""
	return _class_type_to_discipline_key(ability.required_class[0])


## PR 4: maps a `Constants.ClassType` int (tier-1 or tier-2 advancement)
## to the lowercase discipline key. Mirrors `AbilityComponent`'s helper
## so the UI doesn't have to reach back across the component boundary.
func _class_type_to_discipline_key(class_type: int) -> String:
	match class_type:
		Constants.ClassType.SWORD, Constants.ClassType.CRUSADER:
			return "sword"
		Constants.ClassType.BOW, Constants.ClassType.RANGER:
			return "bow"
		Constants.ClassType.STAFF, Constants.ClassType.ARCHMAGE:
			return "staff"
		Constants.ClassType.DAGGER, Constants.ClassType.ASSASSIN:
			return "dagger"
	return ""


## PR 8: inverse of _class_type_to_discipline_key — maps a lowercase discipline
## key back to its tier-1 `Constants.ClassType` int. Returns -1 on an unknown
## key. Used by the header mastery readout to look up the open tab's discipline.
func _discipline_key_to_class_type(key: String) -> int:
	match key:
		"sword":
			return Constants.ClassType.SWORD
		"bow":
			return Constants.ClassType.BOW
		"staff":
			return Constants.ClassType.STAFF
		"dagger":
			return Constants.ClassType.DAGGER
	return -1


## PR 4: returns true if the given ability ID belongs to the active tab.
## Used on window-open to decide whether to keep the previously-selected
## ability or auto-pick the first ability in the new tab.
func _ability_in_current_tab(ability_id: String) -> bool:
	if ability_id.is_empty():
		return false
	var ability_data: AbilityData = ResourceManager.get_ability_data(ability_id)
	if ability_data == null:
		return false
	return _ability_discipline_key(ability_data) == _current_discipline_key


## PR 4: returns the first ability ID that belongs to the current discipline
## tab. Used to auto-select on tab change / window open.
##
## PR 4 fix (2026-05-27): iterate ResourceManager.ability_data (ALL abilities)
## instead of just the player's learned _ability_levels, so a fresh character
## can still auto-select something when they switch to a non-starting tab.
func _first_ability_id_in_current_tab() -> String:
	if not ability_component:
		return ""
	var matching_ids: Array[String] = []
	for ability_id in ResourceManager.ability_data.keys():
		var ability_data: AbilityData = ResourceManager.ability_data[ability_id]
		if ability_data == null:
			continue
		if _ability_discipline_key(ability_data) == _current_discipline_key:
			matching_ids.append(ability_id)
	matching_ids.sort()
	if not matching_ids.is_empty():
		return matching_ids[0]
	return ""


## PR 4: defaults the open tab to the player's currently-wielded
## discipline (driven by the equipped weapon, falling back to the
## starting class). Called on _ready and again on window open.
func _select_initial_discipline() -> void:
	var key: String = _resolve_active_discipline_key()
	var idx: int = DISCIPLINE_TAB_KEYS.find(key)
	if idx < 0:
		idx = 0
	_current_discipline_key = DISCIPLINE_TAB_KEYS[idx]
	if is_instance_valid(discipline_tab_bar):
		discipline_tab_bar.current_tab = idx


## PR 4: queries the player for its current active-discipline ClassType
## and translates that to a lowercase tab key. Falls back to the starting
## class when no weapon is equipped, then to "sword" on any failure.
func _resolve_active_discipline_key() -> String:
	if is_instance_valid(player):
		if player.has_method("get_active_discipline"):
			var disc: int = player.get_active_discipline()
			var key: String = _class_type_to_discipline_key(disc)
			if key != "":
				return key
		if is_instance_valid(player.weapon_mastery_component):
			var key2: String = _class_type_to_discipline_key(player.weapon_mastery_component.primary_discipline)
			if key2 != "":
				return key2
	return "sword"


## PR 4: tab title string for the current tab.
func _current_discipline_tab_title() -> String:
	var idx: int = DISCIPLINE_TAB_KEYS.find(_current_discipline_key)
	if idx < 0:
		return ""
	return DISCIPLINE_TAB_TITLES[idx]
