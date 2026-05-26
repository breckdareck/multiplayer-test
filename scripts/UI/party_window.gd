extends Panel

# --- Node References ---
@onready var close_button: Button = %CloseButton
@onready var online_count: Label = %OnlineCount
@onready var online_tree: Tree = %OnlineTree
@onready var offline_count: Label = %OfflineCount
@onready var offline_tree: Tree = %OfflineTree
@onready var create_button: Button = %CreateButton
@onready var show_hp_button: Button = %ShowHPButton
@onready var kick_button: Button = %KickButton
@onready var whisper_button: Button = %WhisperButton
@onready var search_button: Button = %SearchButton
@onready var party_leader_button: Button = %PartyLeaderButton
@onready var leave_button: Button = %LeaveButton
@onready var chat_button: Button = %ChatButton
@onready var invite_button: Button = %InviteButton
@onready var invite_line_edit: LineEdit = %InviteLineEdit

var target_frame_scene = preload("res://scenes/UI/target_frame.tscn")
var _single_target_frame: Panel = null # Changed to single instance
var _hp_frames_shown = false # Still useful for toggle state
var dragging = false 
var drag_offset = Vector2()

# --- Lifecycle Methods ---
func _ready():
	close_button.pressed.connect(hide)
	# Button Connections
	create_button.pressed.connect(_on_create_party_button_pressed)
	invite_button.pressed.connect(_on_invite_player_button_pressed)
	leave_button.pressed.connect(_on_leave_party_button_pressed)
	kick_button.pressed.connect(_on_kick_button_pressed)
	party_leader_button.pressed.connect(_on_party_leader_button_pressed)
	show_hp_button.pressed.connect(_on_show_hp_button_pressed)

	invite_line_edit.focus_entered.connect(func(): InputManager.set_input_locked(true))
	invite_line_edit.focus_exited.connect(func(): InputManager.set_input_locked(false))

	# PartyManager Signal Connections
	PartyManager.party_created.connect(_on_party_created)
	PartyManager.party_joined.connect(_on_party_joined)
	PartyManager.party_left.connect(_on_party_left)
	PartyManager.member_added.connect(_on_member_added)
	PartyManager.member_removed.connect(_on_member_removed)
	PartyManager.leader_changed.connect(_on_leader_changed)

	# Host-specific connection
	if multiplayer.is_server():
		PartyManager.host_party_data_updated.connect(_update_party_display)

	_initialize_trees()
	_update_party_display()

# --- Initialization ---
func _initialize_trees():
	online_tree.set_column_titles_visible(true)
	online_tree.set_column_title(0, "Name")
	online_tree.set_column_title(1, "Job")
	online_tree.set_column_title(2, "Level")

	offline_tree.set_column_titles_visible(true)
	offline_tree.set_column_title(0, "Name")
	offline_tree.set_column_title(1, "Job")
	offline_tree.set_column_title(2, "Level")

# --- Button Callbacks ---
func _on_create_party_button_pressed():
	PartyManager.rpc_id(1, "rpc_create_party")

func _on_invite_player_button_pressed():
	var invitee_name = invite_line_edit.text
	if invitee_name.is_empty():
		#print("Player name is empty.")
		return

	# Send the name to the server for resolution
	PartyManager.rpc("rpc_send_invite", invitee_name)

func _on_leave_party_button_pressed():
	PartyManager.rpc_id(1, "rpc_leave_party")

func _on_kick_button_pressed():
	var selected = online_tree.get_selected()
	if not selected:
		selected = offline_tree.get_selected()
	
	if not selected:
		#print("No player selected to kick.")
		return
	
	var player_id_to_kick = selected.get_metadata(0)
	if player_id_to_kick == multiplayer.get_unique_id():
		#print("You can't kick yourself.")
		return

	PartyManager.rpc("rpc_kick_player", player_id_to_kick)

func _on_party_leader_button_pressed():
	var selected = online_tree.get_selected()
	if not selected:
		#print("No player selected to make leader.")
		return
	
	var new_leader_id = selected.get_metadata(0)
	PartyManager.rpc("rpc_change_leader", new_leader_id)


func _on_show_hp_button_pressed():
	if _hp_frames_shown:
		# Hide and free the single frame
		if is_instance_valid(_single_target_frame):
			_single_target_frame.queue_free()
		_single_target_frame = null
		_hp_frames_shown = false
		show_hp_button.text = "Show HP"
	else:
		# Create and show the single frame
		var my_id = multiplayer.get_unique_id()
		var members = PartyManager.get_party_members(my_id)
		
		if members.is_empty():
			return

		_single_target_frame = target_frame_scene.instantiate()
		self.get_parent_control().add_child(_single_target_frame)
		_single_target_frame.set_party_members(members) # NEW call
		
		_hp_frames_shown = true
		show_hp_button.text = "Hide HP"


# --- PartyManager Signal Handlers ---
func _is_my_party(party_id: int) -> bool:
	var my_id := multiplayer.get_unique_id()
	return PartyManager.get_player_party_id(my_id) == party_id

func _on_party_created(_party_id: int):
	if not _is_my_party(_party_id):
		return
	_update_party_display()
	if not _hp_frames_shown:
		_on_show_hp_button_pressed()

func _on_party_joined(_player_id: int, _party_id: int):
	if not _is_my_party(_party_id):
		return
	_update_party_display()

func _on_party_left(_player_id: int, _party_id: int):
	if _player_id != multiplayer.get_unique_id() and not _is_my_party(_party_id):
		return
	_update_party_display()
	if _hp_frames_shown and is_instance_valid(_single_target_frame):
		_single_target_frame.queue_free()
		_single_target_frame = null
		_hp_frames_shown = false
		show_hp_button.text = "Show HP"

func _on_member_added(_party_id: int, _player_id: int):
	if not _is_my_party(_party_id):
		return
	_update_party_display()

func _on_member_removed(_party_id: int, _player_id: int):
	if not _is_my_party(_party_id):
		return
	_update_party_display()

func _on_leader_changed(_party_id: int, _new_leader_id: int):
	if not _is_my_party(_party_id):
		return
	_update_party_display()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if _hp_frames_shown and is_instance_valid(_single_target_frame):
			_single_target_frame.queue_free()
			_single_target_frame = null
			_hp_frames_shown = false
			show_hp_button.text = "Show HP"

func _process(_delta: float) -> void:
	if dragging:
		var new_position = get_global_mouse_position() - drag_offset
		var viewport_size = get_viewport_rect().size
		var window_size = size
		
		new_position.x = clamp(new_position.x, 0, viewport_size.x - window_size.x)
		new_position.y = clamp(new_position.y, 0, viewport_size.y - window_size.y)
		
		global_position = new_position

func _gui_input(event: InputEvent):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.is_pressed():
			dragging = true
			drag_offset = get_global_mouse_position() - global_position
			self.move_to_front()
		else:
			dragging = false

# --- UI Update Logic ---
func _update_party_display():
	var my_id = multiplayer.get_unique_id()
	var my_party_id = PartyManager.get_player_party_id(my_id)

	online_tree.clear()
	offline_tree.clear()
	var root_online = online_tree.create_item()
	var root_offline = offline_tree.create_item()

	if my_party_id != -1:
		var members = PartyManager.get_party_members(my_id)
		var leader_id = PartyManager.get_party_leader(my_party_id)
		
		var online_members_count = 0
		
		for member_id in members:
			var player_node = PlayerManager.get_player_node(member_id)
			var member_is_leader = (member_id == leader_id)
			var username = PartyManager.get_player_username(member_id)
			
			var level: int
			var player_class: String

			if multiplayer.is_server(): # HOST PATH
				# Host gets data directly from the player node
				level = 1
				player_class = "N/A"
				if player_node:
					if player_node.level_component:
						level = player_node.level_component.level
					if player_node.class_component:
						player_class = player_node.class_component.get_class_name()
			else: # CLIENT PATH
				# Client gets data from the cache
				var member_info = PartyManager.get_party_member_info(member_id)
				level = member_info.get("level", 1)
				player_class = member_info.get("class_name", "N/A")

			if player_node: # Player is online
				var item = online_tree.create_item(root_online)
				var display_name = username
				if member_is_leader:
					display_name += " (Leader)"
				item.set_text(0, display_name)
				item.set_text(1, player_class)
				item.set_text(2, str(level))
				item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
				item.set_metadata(0, member_id)
				online_members_count += 1
			else: # Player is offline or not visible
				var item = offline_tree.create_item(root_offline)
				# Offline players still use cached data on client, or direct data on host
				var display_name = username
				if member_is_leader:
					display_name += " (Leader)"
				item.set_text(0, display_name)
				item.set_text(1, player_class)
				item.set_text(2, str(level))
				item.set_text_alignment(2, HORIZONTAL_ALIGNMENT_CENTER)
				item.set_metadata(0, member_id)

		online_count.text = "%d/%d" % [online_members_count, members.size()]
		offline_count.text = "%d/%d" % [members.size() - online_members_count, members.size()]
	else:
		online_count.text = "0/0"
		offline_count.text = "0/0"
		var item = online_tree.create_item(root_online)
		item.set_text(0, "Not in a party.")

	# NEW: Update the single TargetFrame if it's currently shown
	if _hp_frames_shown and is_instance_valid(_single_target_frame):
		var members = PartyManager.get_party_members(my_id)
		_single_target_frame.set_party_members(members)

	# Enable/disable buttons
	var is_in_party = my_party_id != -1
	create_button.disabled = is_in_party
	leave_button.disabled = not is_in_party
	
	var is_leader = is_in_party and (PartyManager.get_party_leader(my_party_id) == my_id)
	invite_button.disabled = not is_leader
	invite_line_edit.editable = is_leader
	kick_button.disabled = not is_leader
	party_leader_button.disabled = not is_leader
	
	show_hp_button.disabled = not is_in_party
	whisper_button.disabled = not is_in_party
	chat_button.disabled = not is_in_party
	search_button.disabled = is_in_party
