class_name CheatIntegration
extends Node

# This script should be added to the main game scene to initialize the cheat manager
# and make it available for use.

@export var cheat_ui_scene: PackedScene
var cheat_ui_instance: CheatUI = null

func _ready() -> void:
	# Create the cheat manager if it doesn't exist
	if not CheatManager.instance:
		var cheat_manager = CheatManager.new()
		get_tree().root.add_child.call_deferred(cheat_manager)
		print("CheatManager created and added to scene tree")
	
	# Create the cheat UI if a scene is provided
	if cheat_ui_scene:
		cheat_ui_instance = cheat_ui_scene.instantiate()
		get_tree().root.add_child.call_deferred(cheat_ui_instance)
		print("CheatUI created and added to scene tree")
		
		# Wait a frame for the UI to be ready, then connect it to the cheat manager
		await get_tree().process_frame
		if CheatManager.instance and cheat_ui_instance:
			CheatManager.instance.set_cheat_ui(cheat_ui_instance)
			print("CheatUI connected to CheatManager")
	
	# Remove input handling from here since CheatManager handles it
	# set_process_input(true)

# Public method to get the cheat manager instance
func get_cheat_manager() -> CheatManager:
	return CheatManager.instance

# Public method to get the cheat UI instance
func get_cheat_ui() -> CheatUI:
	return cheat_ui_instance

# Public method to show the cheat UI
func show_cheat_ui() -> void:
	if cheat_ui_instance:
		cheat_ui_instance.visible = true

# Public method to hide the cheat UI
func hide_cheat_ui() -> void:
	if cheat_ui_instance:
		cheat_ui_instance.visible = false
