class_name InventoryComponent
extends Node


@onready var inventory_grid: GridContainer = $"../../CanvasLayer/MoveableWindows/InventoryWindow/InventoryPanel/ScrollContainer/InventoryGrid"
@onready var slots = inventory_grid.get_children()

func _ready() -> void:
	await get_tree().process_frame
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))
	add_item(load("res://resources/Items/Potion.tres"))


func add_item(item: Item):
	for slot in slots:
		if slot.item == null:
			slot.item = item
			return
	print("Can't add any more items")
		

func remove_item(item: Item):
	for slot in slots:
		if slot.item == item:
			slot.item = null
			return
	print("Item not found")
