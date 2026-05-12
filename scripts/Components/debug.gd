extends Control
class_name MyDebugComponent 

@onready var show_hide_button: Button = $HBoxContainer/Panel/ShowHideButton

@onready var debug_panel: Panel = $"."
@onready var debug_heal: Button = $HBoxContainer/VBoxContainer/DebugHeal
@onready var debug_damage: Button = $HBoxContainer/VBoxContainer/DebugDamage
@onready var debug_revive: Button = $HBoxContainer/VBoxContainer/DebugRevive
@onready var debug_level: Button = $HBoxContainer/VBoxContainer/DebugLevel

@onready var debug_item_dropdown: OptionButton = $HBoxContainer/VBoxContainer/HBoxContainer/ItemDropdown
@onready var debug_item: Button = $HBoxContainer/VBoxContainer/HBoxContainer/DebugItem

@onready var animation_player: AnimationPlayer = $AnimationPlayer

var health_component: HealthComponent
var player
var window_open: bool = false

func _ready() -> void:
	debug_heal.pressed.connect(_on_debug_heal_pressed)
	debug_damage.pressed.connect(_on_debug_damage_pressed)
	debug_revive.pressed.connect(_on_debug_revive_pressed)
	debug_level.pressed.connect(_on_debug_level_pressed)
	debug_item.pressed.connect(_on_debug_item_pressed)
	show_hide_button.pressed.connect(_on_show_hide_pressed)
	
	for item in ResourceManager.item_by_name:
		debug_item_dropdown.add_item(item)

func set_health_component(component: HealthComponent) -> void:
	health_component = component

func set_player(player_node) -> void:
	if player_node is MultiplayerPlayerV2:
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

func _on_show_hide_pressed() -> void:
	if window_open:
		animation_player.play("slide")
		window_open = false
	else:
		animation_player.play_backwards("slide")
		window_open = true
		
