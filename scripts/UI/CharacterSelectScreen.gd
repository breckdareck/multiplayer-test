extends Control

@onready var character_list = $Panel/VBoxContainer/CharacterList
@onready var create_button = $Panel/VBoxContainer/CreateButton
@onready var delete_button = $Panel/VBoxContainer/DeleteButton
@onready var logout_button = $Panel/VBoxContainer/LogoutButton
@onready var host_button = $Panel/VBoxContainer/HostRow/HostButton
@onready var max_players_input = $Panel/VBoxContainer/HostRow/MaxPlayersInput
@onready var join_button = $Panel/VBoxContainer/JoinButton
@onready var ip_input = $Panel/VBoxContainer/IPInput
@onready var status_label = $Panel/VBoxContainer/StatusLabel

# Character card (right panel) — mirrors the creation screen: discipline
# sprite + name/level + weapons + stats for the selected character.
@onready var card_vbox = $CardPanel/CardVBox
@onready var char_sprite: TextureRect = $CardPanel/CardVBox/SpriteHolder/CharSprite
@onready var char_name_label: Label = $CardPanel/CardVBox/CharName
@onready var char_subtitle: Label = $CardPanel/CardVBox/CharSubtitle
@onready var weapon_primary_label: Label = $CardPanel/CardVBox/WeaponPrimary
@onready var weapon_secondary_label: Label = $CardPanel/CardVBox/WeaponSecondary
@onready var stats_grid: GridContainer = $CardPanel/CardVBox/StatsGrid
@onready var mastery_label: Label = $CardPanel/CardVBox/MasteryLabel
@onready var empty_hint: Label = $CardPanel/CardVBox/EmptyHint

# Idle bob for the card sprite (same cosmetic as the creation screen).
const _BOB_AMPLITUDE := 6.0
const _BOB_SPEED := 2.2
var _bob_t := 0.0

var characters = []
var selected_character_name = ""
var _server_info_label: Label = null
var _backend_status_label: Label = null
var _status_request: HTTPRequest = null
var _kick_received: bool = false

func _ready():
	create_button.pressed.connect(_on_create_pressed)
	delete_button.pressed.connect(_on_delete_pressed)
	logout_button.pressed.connect(_on_logout_pressed)
	host_button.pressed.connect(_on_host_pressed)
	join_button.pressed.connect(_on_join_pressed)
	character_list.item_selected.connect(_on_character_selected)

	NetworkManager.characters_received.connect(_on_characters_received)
	NetworkManager.character_deleted.connect(_on_character_deleted)
	NetworkManager.character_deletion_failed.connect(_on_character_deletion_failed)
	
	# Connect to connection signals
	MultiplayerManager.server_has_started.connect(_on_server_started)
	ClientManager.connection_succeeded.connect(_on_connection_succeeded)
	ClientManager.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_kicked_from_server)
	
	_setup_server_info_display()
	_setup_backend_info_display()
	_apply_default_join_ip()

	# Fetch characters on load
	NetworkManager.get_characters()


func _apply_default_join_ip():
	# Default Join Server IP to the host of the currently-selected backend API
	# (Local -> 127.0.0.1, Cloud -> the cloud host). The user can still override.
	var host = _extract_host_from_url(UserConfig.get_backend_api_url())
	if host != "":
		ip_input.text = host


func _extract_host_from_url(url: String) -> String:
	var s = url
	if s.begins_with("http://"):
		s = s.substr(7)
	elif s.begins_with("https://"):
		s = s.substr(8)
	var slash = s.find("/")
	if slash != -1:
		s = s.substr(0, slash)
	var colon = s.find(":")
	if colon != -1:
		s = s.substr(0, colon)
	return s


func _setup_server_info_display():
	# Create a label to show server info (hidden until host starts)
	_server_info_label = Label.new()
	_server_info_label.add_theme_color_override("font_color", Color.YELLOW)
	_server_info_label.text = "Share this IP with friends: (waiting...)"
	_server_info_label.visible = false
	# Wrap + center so a long IP/string can't force the panel column wider than
	# the panel (the API-URL overflow class of bug).
	_server_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_server_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Panel/VBoxContainer.add_child(_server_info_label)


func _setup_backend_info_display():
	var backend_url = UserConfig.get_backend_api_url()
	_backend_status_label = Label.new()
	_backend_status_label.add_theme_color_override("font_color", Color.GRAY)
	_backend_status_label.text = "Backend: %s (checking...)" % backend_url
	_backend_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_backend_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$Panel/VBoxContainer.add_child(_backend_status_label)

	_status_request = HTTPRequest.new()
	_status_request.request_completed.connect(_on_status_check_completed)
	add_child(_status_request)
	_check_server_status()


func _check_server_status():
	var api_url = UserConfig.get_backend_api_url().replace("/api", "")
	var error = _status_request.request(api_url + "/health")
	if error != OK:
		_update_server_status(false)


func _on_status_check_completed(_result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray):
	_update_server_status(response_code == 200)


func _update_server_status(online: bool):
	var backend_url = UserConfig.get_backend_api_url()
	if online:
		_backend_status_label.text = "Backend: %s (Online)" % backend_url
		_backend_status_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		_backend_status_label.text = "Backend: %s (Offline)" % backend_url
		_backend_status_label.add_theme_color_override("font_color", Color.RED)


func _on_characters_received(chars):
	characters = chars
	character_list.clear()
	for char_data in characters:
		var text = "%s (Lvl %d)" % [char_data.name, char_data.level]
		character_list.add_item(text)
	# Auto-select so the card is never empty when characters exist.
	if characters.size() > 0:
		character_list.select(0)
		_update_card(characters[0])
	else:
		_update_card({})


func _on_character_selected(index: int) -> void:
	if index >= 0 and index < characters.size():
		_update_card(characters[index])


func _process(delta: float) -> void:
	# Idle bob on the card sprite — its parent SpriteHolder is a plain Control
	# (not a container), so the offset isn't fought by layout.
	if not is_instance_valid(char_sprite) or not char_sprite.visible:
		return
	_bob_t += delta
	char_sprite.position.y = sin(_bob_t * _BOB_SPEED) * _BOB_AMPLITUDE


## Legacy advanced classes (CRUSADER..ASSASSIN) and BEGINNER normalize to a
## tier-1 weapon discipline, mirroring WeaponMasteryComponent's load shim.
func _normalize_discipline(cls: int) -> int:
	match cls:
		Constants.ClassType.CRUSADER: return Constants.ClassType.SWORD
		Constants.ClassType.RANGER: return Constants.ClassType.BOW
		Constants.ClassType.ARCHMAGE: return Constants.ClassType.STAFF
		Constants.ClassType.ASSASSIN: return Constants.ClassType.DAGGER
		Constants.ClassType.BEGINNER: return Constants.ClassType.SWORD
	return clampi(cls, 0, 3)


func _discipline_display_name(disc: int) -> String:
	return Constants.ClassType.keys()[disc].capitalize()


## Loads the equipped weapon ItemData for a slot ("WEAPON"/"SECONDARY_WEAPON").
## Returns null when the slot is empty or the path no longer resolves.
func _load_weapon(char_data: Dictionary, slot: String) -> ItemData:
	var weapons = char_data.get("weapons", {})
	if not weapons is Dictionary or not weapons.has(slot):
		return null
	var path: String = str(weapons[slot].get("item_path", ""))
	if path == "" or not ResourceLoader.exists(path):
		return null
	var item = load(path)
	return item if item is ItemData else null


func _weapon_line(prefix: String, weapon: ItemData) -> String:
	if weapon == null:
		return "%s  — empty —" % prefix
	var disc_str := ""
	if weapon is WeaponData:
		var disc: int = WeaponMasteryComponent.weapon_type_to_discipline(weapon.weapon_type)
		if disc >= 0:
			disc_str = "  (%s)" % _discipline_display_name(disc)
	return "%s %s%s" % [prefix, weapon.name, disc_str]


## Attribute display value = base 4 + allocated points. JSON dictionaries key
## stat types as strings; local saves may keep ints — accept both.
func _attribute_value(char_data: Dictionary, stat_type: int) -> int:
	var alloc = char_data.get("attribute_points", {})
	var points: int = 0
	if alloc is Dictionary:
		points = int(alloc.get(str(stat_type), alloc.get(stat_type, 0)))
	return StatsComponent.BASE_ATTRIBUTE_VALUE + points


func _add_stat_row(label_text: String, value_text: String) -> void:
	var name_l := Label.new()
	name_l.text = label_text
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.add_theme_color_override("font_color", Color(0.62, 0.68, 0.78))
	stats_grid.add_child(name_l)
	var value_l := Label.new()
	value_l.text = value_text
	value_l.add_theme_font_size_override("font_size", 15)
	value_l.add_theme_color_override("font_color", Color(0.95, 0.93, 0.88))
	value_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	stats_grid.add_child(value_l)


func _update_card(char_data: Dictionary) -> void:
	var has_char := not char_data.is_empty()
	for node in card_vbox.get_children():
		if node is Control and node != empty_hint:
			node.visible = has_char
	empty_hint.visible = not has_char
	if not has_char:
		return

	var primary_disc := _normalize_discipline(int(char_data.get("character_class", 0)))

	# Sprite + header — same discipline portrait the creation screen shows.
	var class_data = ResourceManager.get_class_data(primary_disc)
	char_sprite.texture = class_data.icon if class_data else null
	char_name_label.text = str(char_data.get("name", "?"))

	# Disciplines: primary from character_class, secondary from the off-hand
	# weapon (only when it's a different discipline).
	var primary_weapon := _load_weapon(char_data, "WEAPON")
	var secondary_weapon := _load_weapon(char_data, "SECONDARY_WEAPON")
	var subtitle := "Lv. %d   %s" % [int(char_data.get("level", 1)), _discipline_display_name(primary_disc)]
	if secondary_weapon is WeaponData:
		var sec_disc: int = WeaponMasteryComponent.weapon_type_to_discipline(secondary_weapon.weapon_type)
		if sec_disc >= 0 and sec_disc != primary_disc:
			subtitle += " / %s" % _discipline_display_name(sec_disc)
	char_subtitle.text = subtitle

	weapon_primary_label.text = _weapon_line("Primary:", primary_weapon)
	weapon_secondary_label.text = _weapon_line("Secondary:", secondary_weapon)

	# Stats grid: HP/MP + the five allocatable attributes.
	for child in stats_grid.get_children():
		child.queue_free()
	_add_stat_row("HP", str(int(char_data.get("max_health", 100))))
	_add_stat_row("MP", str(int(char_data.get("max_mana", 100))))
	_add_stat_row("STR", str(_attribute_value(char_data, Constants.StatType.STRENGTH)))
	_add_stat_row("DEX", str(_attribute_value(char_data, Constants.StatType.DEXTERITY)))
	_add_stat_row("INT", str(_attribute_value(char_data, Constants.StatType.INTELLIGENCE)))
	_add_stat_row("LUK", str(_attribute_value(char_data, Constants.StatType.LUCK)))
	_add_stat_row("CON", str(_attribute_value(char_data, Constants.StatType.CONSTITUTION)))
	_add_stat_row("Coins", str(int(char_data.get("monies", 0))))

	# Mastery summary — only disciplines with progress.
	var mastery = char_data.get("weapon_mastery", {})
	var parts: Array[String] = []
	if mastery is Dictionary:
		for key in ["sword", "bow", "staff", "dagger"]:
			var entry = mastery.get(key, {})
			if entry is Dictionary and int(entry.get("level", 0)) > 0:
				parts.append("%s %d" % [key.capitalize(), int(entry.get("level", 0))])
	mastery_label.text = "Mastery:  " + (" · ".join(parts) if parts.size() > 0 else "none yet")


func _get_selected_character_data() -> Dictionary:
	var selected = character_list.get_selected_items()
	if selected.size() == 0:
		return {}
	
	var index = selected[0]
	return characters[index]


func _on_host_pressed():
	var char_data = _get_selected_character_data()
	if char_data.is_empty():
		status_label.text = "Please select a character first."
		return
	
	var char_name = char_data.name
	var char_class = char_data.get("character_class", 0)
	
	# Store selected character name and class
	selected_character_name = char_name
	NetworkManager.set_meta("selected_character_name", char_name)
	NetworkManager.set_meta("selected_character_class", char_class)
	
	ServerManager.max_players = int(max_players_input.value)

	status_label.text = "Starting server (max %d players)..." % ServerManager.max_players
	_set_buttons_enabled(false)

	# Show server info (will display once we determine the IP)
	_display_server_info()

	# Host the game
	MultiplayerManager.host_game()


func _display_server_info():
	# Get local IP (show LAN address first)
	var local_ip = IP.get_local_addresses()[0] if IP.get_local_addresses().size() > 0 else "127.0.0.1"
	var game_port = UserConfig.game_server_port
	
	_server_info_label.visible = true
	_server_info_label.text = "🎮 Server Info:\n  LAN: %s:%d\n  ⏳ Finding public IP..." % [local_ip, game_port]
	
	# Try to get external IP (non-blocking, best effort)
	_fetch_external_ip.call_deferred()


func _fetch_external_ip():
	var http = HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(_on_external_ip_received.bind(http))
	
	# Use a public IP detection service
	var error = http.request("https://api.ipify.org?format=json")
	if error != OK:
		http.queue_free()


func _on_external_ip_received(_result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, http: HTTPRequest):
	if response_code == 200:
		var response = JSON.parse_string(body.get_string_from_utf8())
		if response != null and response.has("ip"):
			var external_ip = response["ip"]
			var game_port = UserConfig.game_server_port
			var local_ip = IP.get_local_addresses()[0] if IP.get_local_addresses().size() > 0 else "127.0.0.1"
			
			_server_info_label.text = "🎮 Server Info:\n  LAN: %s:%d\n  Internet: %s:%d\n  (Note: Port forwarding may be needed)" % [local_ip, game_port, external_ip, game_port]
	
	http.queue_free()

	
func _on_join_pressed():
	var char_data = _get_selected_character_data()
	if char_data.is_empty():
		status_label.text = "Please select a character first."
		return
	
	var char_name = char_data.name
	var char_class = char_data.get("character_class", 0)
	
	var ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	
	# Store selected character name and class
	selected_character_name = char_name
	NetworkManager.set_meta("selected_character_name", char_name)
	NetworkManager.set_meta("selected_character_class", char_class)
	
	status_label.text = "Connecting to %s..." % ip
	_set_buttons_enabled(false)
	
	# Join the game with IP
	MultiplayerManager.join_game(ip)

func _on_server_started():
	status_label.text = "Server started!"
	status_label.add_theme_color_override("font_color", Color.GREEN)
	# Give a moment for the user to see the success message? 
	# Or just switch immediately. Immediate switch is better for UX usually.
	queue_free()

func _on_connection_succeeded():
	status_label.text = "Connected! Entering game..."
	status_label.add_theme_color_override("font_color", Color.GREEN)
	await get_tree().create_timer(1.0).timeout
	if is_instance_valid(self) and not _kick_received:
		queue_free()

func _on_connection_failed():
	var ip = ip_input.text if ip_input.text != "" else "127.0.0.1"
	var port = MultiplayerManager.CONFIG.DEFAULT_PORT
	status_label.text = "Failed to connect to %s:%d\n(Server may be offline or full)" % [ip, port]
	status_label.add_theme_color_override("font_color", Color.RED)
	_set_buttons_enabled(true)

func _on_kicked_from_server():
	_kick_received = true
	var reason = MultiplayerManager._pending_shutdown_reason
	if reason.is_empty():
		reason = "Disconnected from server."
	MultiplayerManager._pending_shutdown_reason = ""
	status_label.text = reason
	status_label.add_theme_color_override("font_color", Color.RED)
	_set_buttons_enabled(true)

func _set_buttons_enabled(enabled: bool):
	host_button.disabled = !enabled
	join_button.disabled = !enabled
	create_button.disabled = !enabled
	delete_button.disabled = !enabled
	logout_button.disabled = !enabled

func _on_create_pressed():
	get_tree().change_scene_to_file("res://scenes/UI/CharacterCreationScreen.tscn")

func _on_delete_pressed():
	var char_data = _get_selected_character_data()
	if char_data.is_empty():
		status_label.text = "Please select a character to delete."
		status_label.add_theme_color_override("font_color", Color.RED)
		return

	var char_name = char_data.name
	var confirm = ConfirmationDialog.new()
	confirm.title = "Delete Character"
	confirm.dialog_text = "Permanently delete '%s'?\nThis cannot be undone." % char_name
	confirm.confirmed.connect(_on_delete_confirmed.bind(char_name, confirm))
	confirm.canceled.connect(confirm.queue_free)
	add_child(confirm)
	confirm.popup_centered()

func _on_delete_confirmed(char_name: String, dialog: ConfirmationDialog):
	dialog.queue_free()
	status_label.text = "Deleting %s..." % char_name
	status_label.add_theme_color_override("font_color", Color.WHITE)
	_set_buttons_enabled(false)
	NetworkManager.delete_character(char_name)

func _on_character_deleted(char_name: String):
	status_label.text = "Deleted '%s'." % char_name
	status_label.add_theme_color_override("font_color", Color.GREEN)
	_set_buttons_enabled(true)
	NetworkManager.get_characters()

func _on_character_deletion_failed(error: String):
	status_label.text = "Delete failed: %s" % error
	status_label.add_theme_color_override("font_color", Color.RED)
	_set_buttons_enabled(true)

func _on_logout_pressed():
	NetworkManager.account_id = -1
	get_tree().change_scene_to_file("res://scenes/UI/LoginScreen.tscn")
