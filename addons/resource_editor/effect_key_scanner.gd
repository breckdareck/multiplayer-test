@tool
class_name EffectKeyScanner
extends RefCounted

## Discovers the legal `AbilityUpgradeData.effect_key` strings by scanning game
## source — see docs/adr/0010-resource-editor-effect-key-discovery.md. There is
## deliberately no central registry; the AL_*.gd scripts (plus the two generic
## consumers in ability.gd / combat.gd) ARE the source of truth.
##
## A key is "consumed" iff it appears as the LAST string-literal argument to
## `get_ability_upgrade_magnitude(<id>, "key")` or
## `ability_has_upgrade_effect(<id>, "key")`. Keys built from a variable
## (combat.gd's generic dispatcher, ability.gd's sum_ wrapper) are indirection,
## not definitions, so the literal-only match skips them by construction.

const ABILITIES_DIR := "res://scripts/Abilities"
## Files whose keys are GENERIC (interpreted by shared systems, available to any
## ability) rather than tied to one ability's logic script.
const GENERIC_SOURCES := [
	"res://scripts/Components/ability.gd",
	"res://scripts/Components/combat.gd",
	"res://scripts/UI/ability_window.gd",
]

# Cached scan results. Call invalidate() to force a fresh scan (e.g. after the
# user edits an AL script and reopens the upgrade picker).
static var _all: PackedStringArray = []
static var _generic: PackedStringArray = []
static var _by_script: Dictionary = {}   # script_path -> PackedStringArray
static var _desc_by_key: Dictionary = {} # key -> human description (from `key → meaning` comments)
static var _scanned := false

## Matches the key in `…upgrade…(<first arg>, "the_key")`. The first arg is
## greedily-but-comma-free so a literal second arg is captured; a variable
## second arg (no quotes) simply doesn't match.
const KEY_REGEX := "(?:get_ability_upgrade_magnitude|ability_has_upgrade_effect)\\s*\\(\\s*[^,]+,\\s*\"([A-Za-z0-9_]+)\""


static func invalidate() -> void:
	_scanned = false
	_all = []
	_generic = []
	_by_script = {}


static func _ensure_scanned() -> void:
	if _scanned:
		return
	_scanned = true
	var re := RegEx.new()
	re.compile(KEY_REGEX)

	var generic_set := {}
	for path in GENERIC_SOURCES:
		for k in _scan_file(path, re):
			generic_set[k] = true
	_generic = _sorted(generic_set)

	var all_set := {}
	for k in _generic:
		all_set[k] = true
	_scan_dir(ABILITIES_DIR, re, all_set)
	_all = _sorted(all_set)


static func _scan_dir(dir_path: String, re: RegEx, all_set: Dictionary) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		var full := dir_path.path_join(name)
		if dir.current_is_dir():
			if not name.begins_with("."):
				_scan_dir(full, re, all_set)
		elif name.ends_with(".gd"):
			var keys := _scan_file(full, re)
			if not keys.is_empty():
				_by_script[full] = keys
				for k in keys:
					all_set[k] = true
		name = dir.get_next()
	dir.list_dir_end()


static func _scan_file(path: String, re: RegEx) -> PackedStringArray:
	var out: PackedStringArray = []
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var text := f.get_as_text()
	f.close()
	var seen := {}
	for m in re.search_all(text):
		var k := m.get_string(1)
		if not seen.has(k):
			seen[k] = true
			out.append(k)
	_harvest_descriptions(text)
	return out


## Best-effort: AL scripts document keys with a `key → meaning` (or `key -> meaning`)
## comment convention. Capture the text after the arrow as the magnitude hint.
## First description wins; later files don't clobber an existing one.
static func _harvest_descriptions(text: String) -> void:
	for raw_line in text.split("\n"):
		var line: String = raw_line.strip_edges()
		if not line.begins_with("#"):
			continue
		var arrow := -1
		var arrow_len := 0
		var uni := line.find("→")
		var ascii := line.find("->")
		if uni != -1:
			arrow = uni
			arrow_len = "→".length()
		elif ascii != -1:
			arrow = ascii
			arrow_len = 2
		if arrow == -1:
			continue
		var before: String = line.substr(0, arrow)
		var after: String = line.substr(arrow + arrow_len).strip_edges()
		if after.is_empty():
			continue
		# The key is the last snake_case token before the arrow.
		var key := ""
		for tok in before.split(" "):
			var t: String = tok.strip_edges().trim_prefix("#").strip_edges()
			if t.length() > 0 and t == t.to_lower() and "_" in t and not (" " in t):
				key = t
		if key.is_empty():
			continue
		if not _desc_by_key.has(key):
			_desc_by_key[key] = after


static func _sorted(d: Dictionary) -> PackedStringArray:
	var arr := PackedStringArray(d.keys())
	arr.sort()
	return arr


## Every effect_key found anywhere (generic + all AL scripts), sorted.
static func all_keys() -> PackedStringArray:
	_ensure_scanned()
	return _all


## Generic keys interpreted by shared systems (available to any ability), sorted.
static func generic_keys() -> PackedStringArray:
	_ensure_scanned()
	return _generic


## Keys read by a specific AL script (its `logic_script` path), sorted. Empty if
## the script defines none or the path is blank.
static func keys_for_script(script_path: String) -> PackedStringArray:
	_ensure_scanned()
	if script_path.is_empty():
		return PackedStringArray()
	return _by_script.get(script_path, PackedStringArray())


## True if any consumer reads this key. Drives the amber "no consumer" chip.
static func has_consumer(key: String) -> bool:
	if key.is_empty():
		return false
	_ensure_scanned()
	return _all.has(key)


## Human-readable meaning of a key's magnitude, harvested from `key → meaning`
## comments in the consuming script. Empty string if none documented.
static func describe_key(key: String) -> String:
	_ensure_scanned()
	return _desc_by_key.get(key, "")
