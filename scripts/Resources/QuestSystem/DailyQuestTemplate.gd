class_name DailyQuestTemplate
extends Resource

## Defines a single daily-quest template that can be drawn into the day's
## rotating pool. A deterministic daily seed picks 3 of these each day, so the
## set is identical for every player and requires no server state to decide.

enum DailyObjectiveType {
	KILL_ENEMIES,      # Kill `amount` enemies (optionally a specific type)
	COLLECT_ITEMS,     # Collect `amount` items (optionally a specific item)
	COMPLETE_PARTY_QUEST,  # Complete a quest while in a party
}

## Stable identifier used in save data — must stay unique within the pool.
@export var template_id: String = ""
## Objective category this template tracks.
@export var objective_type: DailyObjectiveType = DailyObjectiveType.KILL_ENEMIES
## Display name shown in the UI.
@export var title: String = ""
## Longer description shown in the UI.
@export_multiline var description: String = ""
## How many of the objective must be done to complete the quest.
@export var amount: int = 1
## Optional filter — for KILL_ENEMIES the enemy monster_name, for
## COLLECT_ITEMS the item name. Empty string means "any".
@export var target: String = ""
## Optional zone/map id filter for KILL_ENEMIES. Empty means "any zone".
@export var zone: String = ""

# ── Rewards ──────────────────────────────────────────────────────────────────
@export var reward_exp: int = 0
@export var reward_coins: int = 0
