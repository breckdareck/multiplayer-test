@tool
class_name AbilityScalingData
extends Resource

## Instead of creating 30 AbilityLevelData resources,
## define formulas for how each stat scales with level

@export_group("Basic Stats")
@export var mana_cost_formula: AbilityScalingFormula
@export var cooldown_formula: AbilityScalingFormula
@export var damage_percent_formula: AbilityScalingFormula
@export var max_targets_formula: AbilityScalingFormula
@export var max_hits_formula: AbilityScalingFormula
@export var cast_time_formula: AbilityScalingFormula

@export_group("Additional Stats")
@export var status_effect_chance_formula: AbilityScalingFormula
@export var status_effect_duration_formula: AbilityScalingFormula
@export var range_multiplier_formula: AbilityScalingFormula
@export var knockback_force_formula: AbilityScalingFormula

@export_group("Passive Modifiers")
## For abilities that modify other abilities (Enhanced Basics)
## Key: ability_id, Value: formula for damage modifier
@export var ability_damage_modifier_formulas: Dictionary = {}
@export var ability_cooldown_modifier_formulas: Dictionary = {}
@export var ability_mana_modifier_formulas: Dictionary = {}

@export_group("Stat Bonuses")
## For passive abilities that give stat bonuses
## Key: StatType, Value: formula for bonus
@export var stat_bonus_formulas: Array[StatBonusFormula] = []

@export_group("Proc Effects")
## Instead of creating procs per level, define how proc stats scale
@export var proc_chance_formula: AbilityScalingFormula
@export var proc_damage_formula: AbilityScalingFormula
@export var proc_cooldown_formula: AbilityScalingFormula

## Which proc type to use (on_hit, on_crit, etc.)
@export var proc_event_type: String = ""

## Static proc data that doesn't scale
@export var proc_execute_ability: AbilityData = null
@export var proc_apply_buff: BuffData = null
@export var proc_animation: String = ""
@export var proc_sfx: String = ""

@export_group("Aura Effects")
@export var aura_radius_formula: AbilityScalingFormula
@export var aura_buff: BuffData = null
@export var aura_affects_allies: bool = true
@export var aura_affects_enemies: bool = false


## Generate an AbilityLevelData for a specific level using the formulas
func generate_level_data(level: int) -> AbilityLevelData:
	var level_data = AbilityLevelData.new(level)
	
	# Apply formulas to basic stats
	if mana_cost_formula:
		level_data.mana_cost = int(mana_cost_formula.calculate(level))
	
	if cooldown_formula:
		level_data.cooldown_time = cooldown_formula.calculate(level)
	
	if damage_percent_formula:
		level_data.damage_percent = int(damage_percent_formula.calculate(level))
	
	if max_targets_formula:
		level_data.max_targets = int(max_targets_formula.calculate(level))
	
	if max_hits_formula:
		level_data.max_hits = int(max_hits_formula.calculate(level))
	
	if cast_time_formula:
		level_data.cast_time = cast_time_formula.calculate(level)
	
	# Apply additional stat formulas
	if status_effect_chance_formula:
		level_data.status_effect_chance = status_effect_chance_formula.calculate(level)
	
	if status_effect_duration_formula:
		level_data.status_effect_duration = status_effect_duration_formula.calculate(level)
	
	if range_multiplier_formula:
		level_data.range_multiplier = range_multiplier_formula.calculate(level)
	
	if knockback_force_formula:
		level_data.knockback_force = knockback_force_formula.calculate(level)
	
	# Generate ability modifiers
	for ability_id in ability_damage_modifier_formulas:
		var formula: AbilityScalingFormula = ability_damage_modifier_formulas[ability_id]
		level_data.ability_damage_modifiers[ability_id] = formula.calculate(level)
	
	for ability_id in ability_cooldown_modifier_formulas:
		var formula: AbilityScalingFormula = ability_cooldown_modifier_formulas[ability_id]
		level_data.ability_cooldown_modifiers[ability_id] = formula.calculate(level)
	
	for ability_id in ability_mana_modifier_formulas:
		var formula: AbilityScalingFormula = ability_mana_modifier_formulas[ability_id]
		level_data.ability_mana_modifiers[ability_id] = formula.calculate(level)
	
	# Generate stat bonuses for passive abilities (NOW SUPPORTS FLAT + PERCENT)
	for stat_bonus_formula in stat_bonus_formulas:
		if stat_bonus_formula:
			var stat_data = stat_bonus_formula.generate_stat_data(level)
			level_data.stat_bonuses[stat_bonus_formula.stat_type] = stat_data
	
	# Generate proc effect if configured
	if not proc_event_type.is_empty() and (proc_chance_formula or proc_damage_formula):
		var proc = ProcEffectData.new()
		
		if proc_chance_formula:
			proc.proc_chance = proc_chance_formula.calculate(level)
		
		if proc_damage_formula:
			proc.damage_percent = int(proc_damage_formula.calculate(level))
		
		if proc_cooldown_formula:
			proc.cooldown = proc_cooldown_formula.calculate(level)
		
		# Static proc data
		proc.execute_ability = proc_execute_ability
		proc.apply_buff = proc_apply_buff
		proc.animation_name = proc_animation
		proc.sfx_path = proc_sfx
		
		# Assign to the correct event type
		match proc_event_type:
			"on_hit":
				level_data.on_hit_proc = proc
			"on_crit":
				level_data.on_crit_proc = proc
			"on_kill":
				level_data.on_kill_proc = proc
			"on_damaged":
				level_data.on_damaged_proc = proc
			"on_dodge":
				level_data.on_dodge_proc = proc
			"on_ability_cast":
				level_data.on_ability_cast_proc = proc
	
	# Generate aura data
	if aura_radius_formula:
		level_data.aura_radius = aura_radius_formula.calculate(level)
		level_data.aura_buff = aura_buff
		level_data.aura_affects_allies = aura_affects_allies
		level_data.aura_affects_enemies = aura_affects_enemies
	
	return level_data
