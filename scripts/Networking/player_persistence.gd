class_name PlayerPersistence
extends RefCounted
## Shared local-file persistence for player save data.
##
## Three autoloads (NetworkManager, PlayerManager, SaveManager) used to each
## carry their own copy of the local read-merge-write fallback, with the save
## directory / filename pattern hard-coded three different ways — including one
## bare `"player_%s.json"` that wrote to the process CWD instead of the saves
## folder. This consolidates the path convention and the read/merge/write logic
## into one place so the fallback behaves identically everywhere.
##
## Network HTTP itself stays in the individual autoloads (each owns its own
## HTTPRequest lifecycle and retry semantics); only the file fallback and the
## canonical path live here.

## Canonical saves directory (res:// so it works the same in editor and export).
const SAVE_DIR: String = "res://saves"


## The one true on-disk path for a character's save file.
static func save_path(username: String) -> String:
	return SAVE_DIR.path_join("player_%s.json" % username)


## Reads a character's save file. Returns the parsed Dictionary, or {} if the
## file is missing / unreadable / not a Dictionary. Callers layer their own
## default-field fill-ins on top of the returned dict.
static func read_save_file(username: String) -> Dictionary:
	if username.is_empty():
		return {}
	var file_path := save_path(username)
	if not FileAccess.file_exists(file_path):
		return {}
	var file := FileAccess.open(file_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed is Dictionary:
		return parsed
	return {}


## Read-merge-write fallback used when the backend is unavailable. Merges the
## supplied (possibly partial) data over whatever is already on disk so a
## category-scoped save doesn't clobber untouched fields. `data` must carry a
## non-empty "username". Ensures the saves directory exists first.
static func write_save_file_merged(data: Dictionary) -> void:
	var username: String = data.get("username", "")
	if username.is_empty():
		push_error("PlayerPersistence: Cannot save to file — no username in data.")
		return

	# Ensure the saves directory exists.
	var dir := DirAccess.open("res://")
	if dir and not dir.dir_exists("saves"):
		dir.make_dir("saves")

	var file_path := save_path(username)
	var existing_data: Dictionary = read_save_file(username)

	# Merge new data into existing (overwrite matching keys).
	existing_data.merge(data, true)

	var file_write := FileAccess.open(file_path, FileAccess.WRITE)
	if file_write:
		file_write.store_string(JSON.stringify(existing_data))
		file_write.close()
	else:
		push_error("PlayerPersistence: Failed to open file for writing: %s" % file_path)
