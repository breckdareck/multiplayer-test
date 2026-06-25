extends RefCounted

# No class_name on purpose: a global class identifier isn't resolvable when the
# game is launched headless via `--script` (the global-class cache isn't loaded),
# which would break the autoloads that use this. Consumers `preload()` it by path
# instead — see ResourceManager / QuestManager / PetManager.

## Shared content scanner for the eager-loading autoloads (ResourceManager,
## QuestManager, PetManager). Recursively walks `path`, loads every `.tres` /
## `.res` it finds, and hands each loaded resource to `on_resource` as
## `(resource: Resource, full_path: String)`. Type-guarding and indexing are the
## caller's job (do them in the callback). This is the single home for the
## recurse → list → load pattern that previously lived three times, once per
## autoload.
##
## Safe to call from a worker thread (ResourceLoader.load is thread-safe in
## Godot 4) — that is how ResourceManager runs it in the background for the heavy
## abilities + items categories. A path that doesn't exist yields no resources.
static func scan(path: String, on_resource: Callable) -> void:
	var items: PackedStringArray = ResourceLoader.list_directory(path)
	for item_name in items:
		var full_path: String = path + item_name
		if item_name.ends_with("/"):
			# Subdirectory — descend.
			scan(full_path, on_resource)
		elif full_path.ends_with(".tres") or full_path.ends_with(".res"):
			var res: Resource = ResourceLoader.load(full_path)
			if res != null:
				on_resource.call(res, full_path)
