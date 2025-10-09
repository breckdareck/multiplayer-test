extends Node
class_name MyDebugComponent 

@onready var debug_panel: Panel = $"."
@onready var debug_heal: Button = $VBoxContainer/DebugHeal
@onready var debug_damage: Button = $VBoxContainer/DebugDamage
@onready var debug_revive: Button = $VBoxContainer/DebugRevive
@onready var debug_level: Button = $VBoxContainer/DebugLevel

@onready var debug_item_dropdown: OptionButton = $VBoxContainer/HBoxContainer/ItemDropdown
@onready var debug_item: Button = $VBoxContainer/HBoxContainer/DebugItem

var health_component: HealthComponent
var player

func _ready() -> void:
	debug_heal.pressed.connect(_on_debug_heal_pressed)
	debug_damage.pressed.connect(_on_debug_damage_pressed)
	debug_revive.pressed.connect(_on_debug_revive_pressed)
	debug_level.pressed.connect(_on_debug_level_pressed)
	debug_item.pressed.connect(_on_debug_item_pressed)
	
	for item in ResourceManager.item_by_name:
		debug_item_dropdown.add_item(item)

func set_health_component(component: HealthComponent) -> void:
	health_component = component

func set_player(player_node) -> void:
	if player_node is MultiplayerPlayer:
		player = player_node as MultiplayerPlayer
	elif player_node is MultiplayerPlayerV2:
		player = player_node as MultiplayerPlayerV2

func _on_debug_heal_pressed() -> void:
	if health_component:
		health_component.heal_damage.rpc(5)

func _on_debug_damage_pressed() -> void:
	if health_component:
		health_component.take_damage.rpc(10, null, true)
		
func _on_debug_revive_pressed() -> void:
	player.respawn.rpc()

func _on_debug_level_pressed() -> void:
	if player.level_component:
		player.level_component.add_exp.rpc(
			player.level_component.get_exp_to_next_level() -
			player.level_component.experience
			)

func _on_debug_item_pressed() -> void:
	if debug_item_dropdown.selected == -1:
		return
		
	if player.inventory_component:
		var item: ItemData = ResourceManager.get_item_by_name(debug_item_dropdown.get_item_text(debug_item_dropdown.selected))
		if item == null:
			return
		player.inventory_component.add_item(item.item_id)
