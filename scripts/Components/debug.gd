extends Node
class_name MyDebugComponent 

@onready var debug_panel: Panel = $"."
@onready var debug_heal: Button = $VBoxContainer/DebugHeal
@onready var debug_damage: Button = $VBoxContainer/DebugDamage
@onready var debug_revive: Button = $VBoxContainer/DebugRevive
@onready var debug_level: Button = $VBoxContainer/DebugLevel

var health_component: HealthComponent
var player

func _ready() -> void:
	debug_heal.pressed.connect(_on_debug_heal_pressed)
	debug_damage.pressed.connect(_on_debug_damage_pressed)
	debug_revive.pressed.connect(_on_debug_revive_pressed)
	debug_level.pressed.connect(_on_debug_level_pressed)

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
	player._respawn.rpc()

func _on_debug_level_pressed() -> void:
	if player.level_component:
		player.level_component.add_exp.rpc(
			player.level_component.get_exp_to_next_level() -
			player.level_component.experience
			)
