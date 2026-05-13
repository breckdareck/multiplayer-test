class_name SlashBlastLogic
extends RefCounted

func execute(caster: Node, ability: AbilityData, stats: AbilityLevelData):
	# Retrieve the caster's stats component
	var player = (caster as MultiplayerPlayerV2)
	var health = player.health_component
	
	# Custom Logic: Deduct HP
	var hp_cost = stats.mana_cost
	health.current_health -= hp_cost 
	
	# Attack logic (using max_targets and max_hits from stats)
	# player.combat_component.perform_attack(ability, stats, target_team: Constants.TeamType.HOSTILE, max_targets: stats.max_targets)
