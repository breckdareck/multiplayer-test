## crafting_window.gd
## Draggable crafting UI. Lists every recipe loaded from resources/Crafting/,
## shows each recipe's ingredients with the player's owned count, and enables
## the Craft button only when the player has enough materials. Crafting itself
## is performed by the server (CraftingStation); this window only displays
## state and sends "craft" intents.
extends Panel

@export var crafting_station: CraftingStation

@onready var recipe_list: VBoxContainer = $ContentPanel/RecipeScroll/RecipeList
@onready var status_label: Label = $FooterPanel/StatusLabel
@onready var window_title: Label = $HeaderPanel/Title

var player_inventory: PlayerInventory
var player_inv_component: InventoryComponent

var _is_dragging: bool = false
var _drag_offset: Vector2 = Vector2()


func _ready() -> void:
	add_to_group("ui_window")
	visible = false


func _process(_delta: float) -> void:
	if _is_dragging:
		var new_position: Vector2 = get_global_mouse_position() - _drag_offset
		var viewport_size: Vector2 = get_viewport_rect().size
		new_position.x = clamp(new_position.x, 0, viewport_size.x - size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - size.y)
		global_position = new_position


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if window_title and window_title.get_global_rect().has_point(get_global_mouse_position()):
				_is_dragging = true
				_drag_offset = get_global_mouse_position() - global_position
				move_to_front()
		else:
			_is_dragging = false


## Opens the crafting window for the given player. Called by the crafting
## station NPC on the local client.
func open_crafting(player_inv: PlayerInventory, station: CraftingStation) -> void:
	player_inventory = player_inv
	player_inv_component = player_inv.inventory_component
	crafting_station = station
	crafting_station.crafting_window = self

	status_label.text = "Select a recipe to craft."
	_refresh_recipes()
	visible = true
	move_to_front()


func close_crafting() -> void:
	visible = false


## Rebuilds the recipe list from ResourceManager, computing craftability
## against the local player's inventory.
func _refresh_recipes() -> void:
	for child in recipe_list.get_children():
		child.queue_free()

	var recipes: Array = ResourceManager.get_crafting_recipes()
	if recipes.is_empty():
		var empty := Label.new()
		empty.text = "No recipes available."
		empty.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75, 1))
		recipe_list.add_child(empty)
		return

	for recipe in recipes:
		if recipe.is_valid():
			_add_recipe_row(recipe)


## Returns how many of an item the local player owns.
func _get_owned_count(item_id: String) -> int:
	if player_inv_component == null:
		return 0
	return player_inv_component.get_item_count(item_id)


## Builds a single recipe entry: result name, ingredient lines (owned/required),
## and a Craft button enabled only when every ingredient requirement is met.
func _add_recipe_row(recipe: CraftingRecipeData) -> void:
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.13, 1)
	panel_style.content_margin_left = 8
	panel_style.content_margin_right = 8
	panel_style.content_margin_top = 6
	panel_style.content_margin_bottom = 6
	panel_style.corner_radius_top_left = 4
	panel_style.corner_radius_top_right = 4
	panel_style.corner_radius_bottom_left = 4
	panel_style.corner_radius_bottom_right = 4
	panel_style.border_width_left = 1
	panel_style.border_width_top = 1
	panel_style.border_width_right = 1
	panel_style.border_width_bottom = 1
	panel_style.border_color = Color(0.25, 0.25, 0.3, 1)
	panel.add_theme_stylebox_override("panel", panel_style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	# Result icon.
	var icon := TextureRect.new()
	icon.texture = recipe.result.icon
	icon.custom_minimum_size = Vector2(36, 36)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)

	# Result name + ingredient breakdown.
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)

	var name_label := Label.new()
	var result_text: String = recipe.result.name
	if recipe.result_count > 1:
		result_text += " x" + str(recipe.result_count)
	name_label.text = result_text
	name_label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.5, 1))
	name_label.add_theme_font_size_override("font_size", 12)
	info.add_child(name_label)

	# Determine craftability while building the ingredient lines.
	var can_craft: bool = true
	for i in recipe.ingredients.size():
		var ingredient: ItemData = recipe.ingredients[i]
		if ingredient == null:
			can_craft = false
			continue
		var needed: int = recipe.ingredient_counts[i] if i < recipe.ingredient_counts.size() else 0
		var owned: int = _get_owned_count(ingredient.item_id)
		var has_enough: bool = owned >= needed
		if not has_enough:
			can_craft = false

		var ing_label := Label.new()
		ing_label.text = "%s  %d/%d" % [ingredient.name, owned, needed]
		ing_label.add_theme_font_size_override("font_size", 10)
		if has_enough:
			ing_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6, 1))
		else:
			ing_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.5, 1))
		info.add_child(ing_label)

	row.add_child(info)

	# Craft button.
	var craft_button := Button.new()
	craft_button.text = "Craft"
	craft_button.focus_mode = Control.FOCUS_NONE
	craft_button.custom_minimum_size = Vector2(70, 32)
	craft_button.disabled = not can_craft
	craft_button.pressed.connect(_on_craft_pressed.bind(recipe.recipe_name))
	row.add_child(craft_button)

	panel.add_child(row)
	recipe_list.add_child(panel)


## Sends a craft intent to the server. The server validates and mutates the
## inventory; the result comes back via receive_craft_result.
func _on_craft_pressed(recipe_name: String) -> void:
	if crafting_station == null:
		return
	status_label.text = "Crafting %s..." % recipe_name
	if multiplayer.is_server():
		crafting_station.request_craft(recipe_name)
	else:
		crafting_station.request_craft.rpc_id(1, recipe_name)


## Server -> client: the outcome of a craft attempt.
@rpc("authority", "call_local", "reliable")
func receive_craft_result(_recipe_name: String, success: bool, message: String) -> void:
	status_label.text = message
	if success:
		status_label.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6, 1))
	else:
		status_label.add_theme_color_override("font_color", Color(0.85, 0.5, 0.5, 1))
	_refresh_recipes()
