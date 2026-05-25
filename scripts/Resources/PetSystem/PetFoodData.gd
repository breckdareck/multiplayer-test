@tool
class_name PetFoodData
extends ConsumableData

## A consumable that restores a summoned pet's hunger when fed to it.
## Distinct from a player potion: cannot be consumed by the player; cannot
## be auto-consumed by autopot. Fed to a pet through the Pet management UI.

@export_group("Pet Food")
## How much fullness to restore on feed.
@export var fullness_restore: float = 25.0
