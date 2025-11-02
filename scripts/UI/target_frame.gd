extends Panel

@onready var members_vbox: VBoxContainer = %MembersVBox

var _member_display_scene = preload("res://scenes/UI/target_member_display.tscn")
var _active_member_displays = {} # {player_id: TargetMemberDisplay}

var dragging = false


func _gui_input(event: InputEvent):
	# Dragging should be on the root panel
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.is_pressed()
	elif event is InputEventMouseMotion and dragging:
		position += event.relative

func set_party_members(member_ids: Array[int]):
	# Clear existing displays
	for child in members_vbox.get_children():
		child.queue_free()
	_active_member_displays.clear()

	if member_ids.is_empty():
		hide()
		return

	for member_id in member_ids:
		var player_node = PlayerManager.get_player_node(member_id)
		if player_node:
			var member_display_instance = _member_display_scene.instantiate()
			members_vbox.add_child(member_display_instance)
			member_display_instance.set_player_node(player_node)
			_active_member_displays[member_id] = member_display_instance
	
	show()
	call_deferred("update_size_after_layout")
	
	
func update_size_after_layout():
	await get_tree().process_frame
	self.size.y = members_vbox.size.y
