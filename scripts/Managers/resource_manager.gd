# ResourceManager.gd - Autoload script
extends Node

# Emitted on the main thread once the deferred abilities + items scan has
# finished and the indexes below are fully populated. Listeners that want to
# react to readiness (rather than block on it) can connect to this; anything
# that must read the data right now should call ensure_loaded() instead.
signal content_ready

# Dictionary to store weapon-discipline data by ClassType enum value.
# (ClassType semantically means "weapon discipline" now — see Constants.gd.)
var class_data: Dictionary[Constants.ClassType, WeaponDisciplineData] = {}

var item_data: Dictionary[String, ItemData] = {}
var item_by_name: Dictionary[String, ItemData] = {}

var ability_data: Dictionary[String, AbilityData] = {}
var ability_by_name: Dictionary[String, AbilityData] = {}

var buff_data: Dictionary[String, BuffData] = {}
var buffs_by_name: Dictionary[String, BuffData] = {}

# Background loader for the heavy abilities + items scan (~800 .tres). See
# _ready() / ensure_loaded() for the loading strategy.
var _load_thread: Thread = null
var _content_loaded: bool = false

func _ready() -> void:
	# Disciplines (character-select portrait + base stats) and buffs (combat)
	# total ~23 .tres and have early consumers, so they load synchronously
	# before the first frame.
	_load_class_data()
	_load_buff_data()

	# Abilities + items (~800 .tres, each dragging icons / projectile scenes /
	# upgrade trees) are not needed until a player spawns into a map. They load
	# on a background thread so the login screen renders immediately instead of
	# blocking on a disk scan it never uses. Any consumer that needs them sooner
	# calls ensure_loaded(), which transparently blocks until the scan finishes;
	# the public ability/item getters do this automatically.
	_start_deferred_load()


func _start_deferred_load() -> void:
	_load_thread = Thread.new()
	var err: int = _load_thread.start(_load_deferred_content)
	if err != OK:
		# Threads unavailable on this platform — fall back to a synchronous load
		# so the indexes are still populated (just without the startup win).
		push_warning("ResourceManager: background load thread unavailable (err %d); loading synchronously." % err)
		_load_thread = null
		_load_item_data()
		_load_ability_data()
		_content_loaded = true
		content_ready.emit()


# Runs on the background thread. Must not emit signals or join itself here —
# both are marshalled back to the main thread via call_deferred.
func _load_deferred_content() -> void:
	_load_item_data()
	_load_ability_data()
	call_deferred("_finish_deferred_load")


# Main thread: the worker has signalled completion, so join it and announce.
func _finish_deferred_load() -> void:
	ensure_loaded()


## Blocks the calling (main) thread until the deferred abilities + items scan has
## finished, then returns. Idempotent and effectively free once loaded. The
## public ability/item getters call this for you; call it directly only where the
## indexes are read without going through a getter (e.g. iterating
## ability_data.values(), or a test harness that runs on the first frame).
func ensure_loaded() -> void:
	if _content_loaded:
		return
	if _load_thread != null:
		# No worse than the old synchronous _ready() for an early caller, and only
		# paid once by the first consumer that needs the data before it is ready.
		_load_thread.wait_to_finish()
		_load_thread = null
	_content_loaded = true
	content_ready.emit()


## True once the deferred abilities + items scan has completed.
func is_content_ready() -> bool:
	return _content_loaded


#region Item Data Functions

func _load_item_data() -> void:
	var item_folder: String = "res://resources/Items/"

	var process_item = func(resource, _path):
		if resource is ItemData:
			item_data[resource.item_id] = resource
			item_by_name[resource.name] = resource
			#print("Loaded item: %s from path: %s" % [resource.name, path])
			#print("DEBUG: ResourceManager loaded item icon: ", resource.icon)
			
	# Call the generic loader
	_load_resources_recursively(item_folder, process_item)
		

func get_item_data(item_id: String) -> ItemData:
	ensure_loaded()
	# If it's a UUID, look it up directly
	if item_data.has(item_id):
		return item_data[item_id]
	
	# If it's a name, try to find it by name
	if item_by_name.has(item_id):
		return item_by_name[item_id]
	
	# Nothing found
	#print("Item not found: %s" % item_id)
	return null
	
	
func get_item_by_name(item_name: String) -> ItemData:
	ensure_loaded()
	return item_by_name.get(item_name)
	
#endregion


#region Class Data Functions

func _load_class_data() -> void:
	var class_folder: String = "res://resources/Player/Disciplines/"

	var process_class = func(resource, _path):
		if resource is WeaponDisciplineData:
			class_data[resource.class_type] = resource
			#print("Loaded discipline: %s from path: %s" % [resource._discipline_name, path])

	_load_resources_recursively(class_folder, process_class)


func get_class_data(class_type: Constants.ClassType) -> WeaponDisciplineData:
	return class_data.get(class_type)


func get_class_name(class_type: Constants.ClassType) -> String:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data._discipline_name if data else "unknown"


func get_class_bonuses(class_type: Constants.ClassType) -> Dictionary:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.stat_bonuses if data else {}


func get_class_skills(class_type: Constants.ClassType) -> Array[AbilityData]:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.skills if data else []


func get_sprite_frames_for_class(class_type: Constants.ClassType) -> Dictionary:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.sprite_frames if data else {}


func get_sprite_for_level(class_type: Constants.ClassType, level: int) -> SpriteFrames:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.get_sprite_for_level(level) if data else null


func get_base_stats(class_type: Constants.ClassType) -> Dictionary:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.base_stats if data else {}


func get_primary_stat(class_type: Constants.ClassType) -> Constants.StatType:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.primary_stat


func get_secondary_stat(class_type: Constants.ClassType) -> Constants.StatType:
	var data: WeaponDisciplineData = get_class_data(class_type)
	return data.secondary_stat

# Utility function to get ClassType enum from string. Accepts the legacy
# starting-discipline names ("swordsman" / "mage" / "archer" / "rogue") as
# well as the new weapon-keyed names ("sword" / "staff" / "bow" / "dagger"),
# since saved characters and the bot_config.json still carry the legacy names.
func get_class_type_from_string(_class_name: String) -> Constants.ClassType:
	match _class_name.to_lower():
		"swordsman", "sword":
			return Constants.ClassType.SWORD
		"archer", "bow":
			return Constants.ClassType.BOW
		"mage", "staff":
			return Constants.ClassType.STAFF
		"rogue", "dagger":
			return Constants.ClassType.DAGGER
		"beginner":
			return Constants.ClassType.BEGINNER
		"crusader":
			return Constants.ClassType.CRUSADER
		"ranger":
			return Constants.ClassType.RANGER
		"archmage":
			return Constants.ClassType.ARCHMAGE
		"assassin":
			return Constants.ClassType.ASSASSIN
		_:
			return Constants.ClassType.BEGINNER  # Default fallback
#endregion


#region Ability Data Functions

func _load_ability_data() -> void:
	var ability_folder: String = "res://resources/Abilities/"
	
	var process_ability = func(resource, _path):
		if resource is AbilityData:
			ability_data[resource.ability_id] = resource 
			ability_by_name[resource.ability_name] = resource 
			#print("Loaded ability: %s from path: %s" % [resource.ability_name, path])

	_load_resources_recursively(ability_folder, process_ability)


func get_ability_data(ability_identifier: String) -> AbilityData:
	ensure_loaded()
	# First check by ID
	if ability_data.has(ability_identifier):
		return ability_data[ability_identifier]
	
	# Then check by name
	if ability_by_name.has(ability_identifier):
		return ability_by_name[ability_identifier]
	
	# Nothing found
	#print("Ability not found: %s" % ability_identifier)
	return null

func get_ability_by_name(ability_name: String) -> AbilityData:
	ensure_loaded()
	return ability_by_name.get(ability_name)

#endregion


#region Buff Data Functions

func _load_buff_data() -> void:
	var buff_folder: String = "res://resources/Buffs/"
	
	var process_buff = func(resource, _path):
		if resource is BuffData:
			buff_data[resource.buff_id] = resource 
			buffs_by_name[resource.buff_name] = resource 
			#print("Loaded buff: %s from path: %s" % [resource.buff_name, path])
			
	_load_resources_recursively(buff_folder, process_buff)
		
func get_buff_data(buff_identifier: String) -> BuffData:
	if buff_data.has(buff_identifier):
		return buff_data[buff_identifier]
		
	if buffs_by_name.has(buff_identifier):
		return buffs_by_name[buff_identifier]
		
	#print("Buff not found: %s" % buff_identifier)
	return null
	
func get_buff_by_name(buff_name: String) -> BuffData:
	return buffs_by_name.get(buff_name)

		
#endregion


func _load_resources_recursively(path: String, process_callable: Callable) -> void:
	# Get all items (files and directories) in the current path
	var items = ResourceLoader.list_directory(path)
	
	for item_name in items:
		var full_path = path + item_name
		
		# Check if the item is a directory (it will end with "/")
		if item_name.ends_with("/"):
			# It's a directory! Call this function again for the subdirectory.
			# This is the "recursive" step.
			_load_resources_recursively(full_path, process_callable)
			
		# Check if it's a resource file we want to load
		# This avoids trying to load ".import" files
		elif full_path.ends_with(".tres") or full_path.ends_with(".res"):
			# It's a file! Load it.
			var resource = ResourceLoader.load(full_path)
			
			if resource:
				# Call the provided 'Callable' and pass it the loaded resource
				process_callable.call(resource, full_path)
