class_name CheatManager
extends Node

# Singleton pattern for easy access
static var instance: CheatManager

# Debug/Cheat flags
var cheats_enabled: bool = false
var god_mode: bool = false
var infinite_jump: bool = false
var show_debug_info: bool = false

# Available items for spawning
var available_items: Array[ItemData] = []
var item_paths: Array[String] = [
	"res://resources/Items/Coin.tres",
	"res://resources/Items/Sword.tres", 
	"res://resources/Items/Potion.tres"
]

# References
var current_player: MultiplayerPlayerV2 = null
var cheat_ui: CanvasLayer = null

var player_check_timer: Timer = null

# Signals
signal cheats_toggled(enabled: bool)
signal item_added(item: ItemData, success: bool)
signal player_stats_modified

func _ready() -> void:
	# Singleton pattern
	if instance == null:
		instance = self
		# Don't free when changing scenes
		process_mode = Node.PROCESS_MODE_ALWAYS
	else:
		queue_free()
		return
	
	# Load available items
	_load_available_items()
	
	# Start a timer to periodically check for players
	player_check_timer = Timer.new()
	player_check_timer.wait_time = 1.0
	player_check_timer.timeout.connect(_check_for_players)
	player_check_timer.autostart = true
	add_child(player_check_timer)
	
	# Enable cheats by default for testing (you can remove this later)
	cheats_enabled = true
	print("CheatManager initialized - Cheats enabled by default for testing")
	print("Press F1 to toggle cheat UI")

func _load_available_items() -> void:
	available_items.clear()
	for item_path in item_paths:
		var item = load(item_path) as ItemData
		if item:
			available_items.append(item)
			print("Loaded item: ", item.name)
		else:
			push_warning("Failed to load item from path: ", item_path)

var is_checking_for_players: bool = false

func _check_for_players() -> void:
	# Prevent infinite recursion
	if current_player != null:
		player_check_timer.stop()
		return
	else:
		player_check_timer.start()

	if is_checking_for_players:
		return
	
	is_checking_for_players = true
	
	print("CheatManager: Checking for players...")
	print("Current multiplayer ID: ", multiplayer.get_unique_id())
	
	# Look for players in the scene - check both groups
	var players = get_tree().get_nodes_in_group("players")
	print("Players in 'players' group: ", players.size())
	
	if players.is_empty():
		# If no players in "players" group, check "networked_entities" group
		var networked_entities = get_tree().get_nodes_in_group("networked_entities")
		print("Entities in 'networked_entities' group: ", networked_entities.size())
		
		for entity in networked_entities:
			print("Entity: ", entity.name, " (Type: ", entity.get_class(), ")")
			if entity is MultiplayerPlayerV2:
				# Add to players group for easier access
				entity.add_to_group("players")
				players.append(entity)
				print("Added player to 'players' group: ", entity.name)
	
	if not players.is_empty():
		print("Total players found: ", players.size())
		# Find the local player (the one we control)
		for player in players:
			print("Checking player: ", player.name, " (ID: ", player.player_id, ")")
			if player is MultiplayerPlayerV2 and player.player_id == multiplayer.get_unique_id():
				current_player = player
				print("CheatManager: Local player found, ready for cheats")
				print("Player ID: ", player.player_id, ", Multiplayer ID: ", multiplayer.get_unique_id())
				break
		
		# If still no player found, try to find any player with required components
		if not current_player:
			for player in players:
				if player is MultiplayerPlayerV2 and player.has_method("get_inventory_component"):
					current_player = player
					print("CheatManager: Player found, ready for cheats")
					print("Player ID: ", player.player_id, ", Multiplayer ID: ", multiplayer.get_unique_id())
					break
	else:
		print("CheatManager: No players found in scene")
	
	is_checking_for_players = false

# Manual player detection function for debugging
func force_find_player() -> bool:
	print("CheatManager: Force finding player...")
	_check_for_players()
	return current_player != null

func toggle_cheats() -> void:
	cheats_enabled = !cheats_enabled
	cheats_toggled.emit(cheats_enabled)
	print("Cheats ", "enabled" if cheats_enabled else "disabled")

func add_item_to_inventory(item_name: String, amount: int = 1) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.inventory_component:
		print("No player or inventory found!")
		return false
	
	# Find the item by name
	var target_item: ItemData = null
	for item in available_items:
		if item.name.to_lower() == item_name.to_lower():
			target_item = item
			break
	
	if not target_item:
		print("Item not found: ", item_name)
		return false
	
	# Create the item with the specified amount
	var item_to_add = target_item.duplicate_with_path()
	item_to_add.current_stack_amount = amount
	
	# Add to inventory
	current_player.inventory_component.add_item(item_to_add)
	
	print("Added ", amount, "x ", item_name, " to inventory")
	item_added.emit(item_to_add, true)
	return true

func add_item_by_type(item_type: Constants.ItemType, amount: int = 1) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.inventory_component:
		print("No player or inventory found!")
		return false
	
	# Find items of the specified type
	var items_of_type: Array[ItemData] = []
	for item in available_items:
		if item.item_type == item_type:
			items_of_type.append(item)
	
	if items_of_type.is_empty():
		print("No items found of type: ", item_type)
		return false
	
	# Add a random item of that type
	var random_item = items_of_type[randi() % items_of_type.size()]
	var item_to_add = random_item.duplicate_with_path()
	item_to_add.current_stack_amount = amount
	
	current_player.inventory_component.add_item(item_to_add)
	
	print("Added ", amount, "x ", random_item.name, " (", item_type, ") to inventory")
	item_added.emit(item_to_add, true)
	return true

func fill_inventory_with_items() -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.inventory_component:
		print("No player or inventory found!")
		return false
	
	var empty_slots = current_player.inventory_component.get_empty_slots()
	if empty_slots.is_empty():
		print("Inventory is full!")
		return false
	
	var items_added = 0
	for i in range(min(empty_slots.size(), available_items.size())):
		var item = available_items[i]
		var amount = randi_range(1, item.max_stack_amount)
		var item_to_add = item.duplicate_with_path()
		item_to_add.current_stack_amount = amount
		
		current_player.inventory_component.add_item(item_to_add)
		items_added += 1
	
	print("Filled inventory with ", items_added, " items")
	return true

func clear_inventory() -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.inventory_component:
		print("No player or inventory found!")
		return false
	
	# Clear all slots
	for slot in current_player.inventory_component.slots:
		slot.item = null
		slot.update_display()
	
	# Rebuild tracking
	current_player.inventory_component._rebuild_item_tracking()
	
	print("Inventory cleared")
	return true

func modify_player_health(amount: int) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.health_component:
		print("No player or health component found!")
		return false
	
	var new_health = current_player.health_component.current_health + amount
	new_health = clamp(new_health, 0, current_player.health_component.max_health)
	
	current_player.health_component.current_health = new_health
	current_player.health_component.health_changed.emit(new_health, current_player.health_component.max_health)
	
	print("Player health modified to: ", new_health)
	player_stats_modified.emit()
	return true

func set_player_health(health: int) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.health_component:
		print("No player or health component found!")
		return false
	
	health = clamp(health, 0, current_player.health_component.max_health)
	current_player.health_component.current_health = health
	current_player.health_component.health_changed.emit(health, current_player.health_component.max_health)
	
	print("Player health set to: ", health)
	player_stats_modified.emit()
	return true

func modify_player_experience(amount: int) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.level_component:
		print("No player or level component found!")
		return false
	
	current_player.level_component.add_exp(amount)
	
	print("Player experience modified by: ", amount)
	player_stats_modified.emit()
	return true

func set_player_level(level: int) -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player or not current_player.level_component:
		print("No player or level component found!")
		return false
	
	# Set level and adjust experience accordingly
	current_player.level_component.level = level
	current_player.level_component.experience = 0
	current_player.level_component.leveled_up.emit(level)
	
	print("Player level set to: ", level)
	player_stats_modified.emit()
	return true

func toggle_god_mode() -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	god_mode = !god_mode
	
	if current_player and current_player.health_component:
		if god_mode:
			current_player.health_component.max_health = 999999
			current_player.health_component.current_health = 999999
			print("God mode enabled - infinite health")
		else:
			current_player.health_component.max_health = 100
			current_player.health_component.current_health = 100
			print("God mode disabled - normal health")
		
		current_player.health_component.health_changed.emit(
			current_player.health_component.current_health, 
			current_player.health_component.max_health
		)
	
	return god_mode

func teleport_player_to_spawn() -> bool:
	if not cheats_enabled:
		print("Cheats are disabled!")
		return false
	
	if not current_player:
		print("No player found!")
		return false
	
	if multiplayer.is_server():
		current_player.position = MultiplayerManager.respawn_point
		print("Player teleported to spawn")
		return true
	else:
		print("Only server can teleport players")
		return false

func get_available_item_names() -> Array[String]:
	var names: Array[String] = []
	for item in available_items:
		names.append(item.name)
	return names

func get_available_item_types() -> Array[String]:
	var types: Array[String] = []
	for item_type in Constants.ItemType.values():
		types.append(Constants.ItemType.keys()[item_type])
	return types

func get_player_info() -> Dictionary:
	if not current_player:
		return {}
	
	var info = {
		"player_id": current_player.player_id,
		"username": current_player.username,
		"position": current_player.position,
		"health": 0,
		"max_health": 0,
		"level": 0,
		"experience": 0,
		"inventory_slots": 0,
		"inventory_items": 0
	}
	
	if current_player.health_component:
		info.health = current_player.health_component.current_health
		info.max_health = current_player.health_component.max_health
	
	if current_player.level_component:
		info.level = current_player.level_component.level
		info.experience = current_player.level_component.experience
	
	if current_player.inventory_component:
		info.inventory_slots = current_player.inventory_component.slots.size()
		info.inventory_items = current_player.inventory_component.get_total_items()
	
	return info

# Console command interface
func execute_cheat_command(command: String, args: Array = []) -> String:
	if not cheats_enabled:
		return "Cheats are disabled!"
	
	match command.to_lower():
		"add_item":
			if args.size() < 1:
				return "Usage: add_item <item_name> [amount]"
			var amount = 1 if args.size() < 2 else int(args[1])
			var success = add_item_to_inventory(args[0], amount)
			return "Item added successfully!" if success else "Failed to add item"
		
		"add_type":
			if args.size() < 1:
				return "Usage: add_type <item_type> [amount]"
			var amount = 1 if args.size() < 2 else int(args[1])
			var item_type = Constants.ItemType[args[0].to_upper()]
			var success = add_item_by_type(item_type, amount)
			return "Item added successfully!" if success else "Failed to add item"
		
		"fill_inv":
			var success = fill_inventory_with_items()
			return "Inventory filled!" if success else "Failed to fill inventory"
		
		"clear_inv":
			var success = clear_inventory()
			return "Inventory cleared!" if success else "Failed to clear inventory"
		
		"set_health":
			if args.size() < 1:
				return "Usage: set_health <amount>"
			var success = set_player_health(int(args[0]))
			return "Health set!" if success else "Failed to set health"
		
		"set_level":
			if args.size() < 1:
				return "Usage: set_level <level>"
			var success = set_player_level(int(args[0]))
			return "Level set!" if success else "Failed to set level"
		
		"god_mode":
			var enabled = toggle_god_mode()
			return "God mode " + ("enabled" if enabled else "disabled")
		
		"teleport":
			var success = teleport_player_to_spawn()
			return "Teleported!" if success else "Failed to teleport"
		
		"info":
			var player_info = get_player_info()
			return "Player Info: " + str(player_info)
		
		"help":
			return """Available commands:
add_item <name> [amount] - Add specific item
add_type <type> [amount] - Add item by type
fill_inv - Fill inventory with random items
clear_inv - Clear inventory
set_health <amount> - Set player health
set_level <level> - Set player level
god_mode - Toggle god mode
teleport - Teleport to spawn
info - Show player info
help - Show this help"""
		
		_:
			return "Unknown command: " + command + ". Type 'help' for available commands."

# Input handling for quick cheat activation
func _input(event: InputEvent) -> void:
	# F1 - Toggle cheat UI (always works, regardless of cheat state)
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		print("F1 key detected - toggling cheat UI")
		toggle_cheat_ui()
		return
	
	# Only process other cheat keys if cheats are enabled
	if not cheats_enabled:
		return
	
	# F2 - Quick item add
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		add_item_to_inventory("Coin", 10)
	
	# F3 - Quick health restore
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		set_player_health(100)

func toggle_cheat_ui() -> void:
	if cheat_ui:
		cheat_ui.visible = !cheat_ui.visible
		print("Cheat UI toggled: ", cheat_ui.visible)
	else:
		print("Warning: No cheat UI reference found!")
		print("Make sure the CheatIntegration script is properly set up")
		print("CheatManager instance: ", instance)
		print("Current cheat_ui reference: ", cheat_ui)

func set_cheat_ui(ui: CanvasLayer) -> void:
	cheat_ui = ui
