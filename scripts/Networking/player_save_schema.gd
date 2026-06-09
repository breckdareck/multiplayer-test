class_name PlayerSaveSchema
extends RefCounted

## Single source of truth for the Player-save SHAPE: the default fields every
## loaded save must carry (legacy saves predate some keys), and the blob a
## brand-new character starts with.
##
## Before this module the default-fill was copy-pasted across PlayerManager's
## three load paths (file fallback + HTTP first-try + HTTP retry) and the
## new-character template lived separately in NetworkManager — four places that
## had to be kept in lockstep by hand. Now the shape lives here.
##
## NOTE: reading specific runtime VALUES out of a save (current_health, level,
## inventory, …) stays with each consumer — that is legitimately per-component.
## This module owns only the SHAPE: which keys exist, their defaults, and the
## new-character template.

## Fills the default fields a freshly-loaded save must always carry, in place,
## and returns it. Empty saves (no existing data) pass through untouched so the
## "brand-new character" path stays distinguishable from a populated load.
static func normalize_loaded(save: Dictionary) -> Dictionary:
	if save.is_empty():
		return save
	save["party_id"] = save.get("party_id", -1)
	save["last_map"] = save.get("last_map", "")
	# weapon_mastery (PR 2) — legacy saves without the key load with an empty
	# dict so the component picks up four zero-state disciplines on
	# _ensure_default_disciplines.
	save["weapon_mastery"] = save.get("weapon_mastery", {})
	return save


## The starting Player save for a newly-created character. Advanced (tier-2)
## classes start at level 30; everyone else at level 1.
static func new_character(char_name: String, class_id: int) -> Dictionary:
	var is_advanced: bool = class_id >= Constants.ClassType.CRUSADER
	var starting_level: int = 30 if is_advanced else 1
	return {
		"username": char_name,
		"level": starting_level,
		"experience": 0,
		"character_class": class_id,
		"current_health": 100,
		"max_health": 100,
		"current_mana": 100,
		"max_mana": 100,
		"monies": 0,
		"inventory": {},
		"equipment": {},
		# PR 4: per-discipline ability-point pools. All four tier-1 pools start at
		# zero — the starting point comes from
		# AbilityComponent.bootstrap_fresh_character_if_needed bumping the chosen
		# discipline to mastery 1 (which grants 1 point via mastery_level_changed).
		"abilities": {"available_points_per_discipline": _starter_ability_point_pools(class_id, starting_level)},
		# Empty mastery dict — WeaponMasteryComponent fills four zero-state
		# disciplines via _ensure_default_disciplines, same as normalize_loaded.
		"weapon_mastery": {},
		"buffs": {},
		"quests": {}
	}


## Empty per-discipline ability-point pools for a new character. All four tier-1
## pools start at zero — see new_character(). class_id / starting_level are kept
## for future use (e.g. advanced classes bootstrapping to a higher mastery).
static func _starter_ability_point_pools(_class_id: int, _starting_level: int) -> Dictionary:
	return {
		"sword": 0,
		"bow": 0,
		"staff": 0,
		"dagger": 0,
	}
