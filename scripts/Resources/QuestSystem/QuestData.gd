class_name QuestData
extends Resource

## Defines a quest with objectives, rewards, and prerequisites.

enum ObjectiveType {
	KILL,       # Kill N of a specific enemy
	COLLECT,    # Collect N of a specific item
	REACH_LEVEL, # Reach a certain level
}

@export var quest_id: String = ""
@export var quest_name: String = ""
@export_multiline var description: String = ""
@export var required_level: int = 1
@export var prerequisite_quest_id: String = ""  # Must complete this quest first

# Objectives — each is a dictionary: { "type": ObjectiveType, "target": String, "amount": int }
@export var objectives: Array[Dictionary] = []

# Rewards
@export var reward_exp: int = 0
@export var reward_coins: int = 0
@export var reward_items: Array[String] = []  # Item names from ResourceManager

## When true, this quest is hidden from the Quest Log's "Available" tab and can
## only be accepted via a QuestGiverNPC whose `offered_quest_ids` includes it.
## Use for NPC-locked chains (e.g. the Village Elder's Endless Hunt 15/50/99/999)
## so the journal doesn't spoil quests the player is meant to discover through
## an NPC. Once accepted, the quest behaves normally — it shows up in the
## Active tab, persists, and grants rewards the same way.
@export var npc_only: bool = false
