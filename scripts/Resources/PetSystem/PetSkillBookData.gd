@tool
class_name PetSkillBookData
extends ConsumableData

## A consumable that, when used on a summoned pet, teaches it one command.
## Recorded per-pet as `learned_commands: []`. One-time consumption.
##
## command_id values used by the pet system:
##   "auto_pot"     - unlocks HP+MP autopot slots
##   "item_pouch"   - unlocks item autoloot
##   "meso_magnet"  - unlocks coin autoloot
##   "autobuff"     - unlocks the buff slot (player drags any owned buff ability in)

@export_group("Pet Skill Book")
## The command this book teaches. Must match a command id PetManager knows.
@export var command_id: String = ""
