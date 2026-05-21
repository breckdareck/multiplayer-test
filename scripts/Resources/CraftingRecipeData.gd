@tool
class_name CraftingRecipeData
extends Resource

## A crafting recipe: combine a set of ingredient items (in fixed counts) into
## a result item. Recipes are data-driven .tres files in resources/Crafting/,
## auto-loaded by ResourceManager. Crafting is gated only by having the
## materials — there is no crafting skill or level.

## Display name shown in the crafting UI.
@export var recipe_name: String = ""

## The items required to craft. Index-matched with [member ingredient_counts].
@export var ingredients: Array[ItemData] = []

## How many of each ingredient is required. Index-matched with [member ingredients].
@export var ingredient_counts: Array[int] = []

## The item produced by the recipe.
@export var result: ItemData

## How many copies of [member result] are produced per craft.
@export var result_count: int = 1


## Returns true when the recipe is well-formed (has a result and at least one
## valid ingredient with a positive count).
func is_valid() -> bool:
	if result == null:
		return false
	if ingredients.is_empty():
		return false
	if ingredients.size() != ingredient_counts.size():
		return false
	for i in ingredients.size():
		if ingredients[i] == null or ingredient_counts[i] <= 0:
			return false
	return result_count > 0


## Aggregates ingredients into a {item_id: total_required} dictionary, summing
## counts when the same item appears more than once in the ingredient list.
func get_required_counts() -> Dictionary:
	var required: Dictionary = {}
	for i in ingredients.size():
		var ingredient: ItemData = ingredients[i]
		if ingredient == null:
			continue
		var count: int = ingredient_counts[i] if i < ingredient_counts.size() else 0
		required[ingredient.item_id] = required.get(ingredient.item_id, 0) + count
	return required
