extends RefCounted
# Shared UID-header helper for the headless content generators.
#
# ResourceSaver.save() run headless (no editor) does NOT write a
# `uid="uid://..."` into a .tres header. Resources saved that way have no
# persistent UID, so anything that references them BY uid (enemy ED_*.tres ->
# drop tables, town.tscn -> consumables) can't resolve the uid and Godot spams
# "invalid UID - using text path instead". After saving, call ensure_header_uid()
# to give the file a stable header uid (preserving one it already had across a
# re-save), which keeps the whole uid graph consistent.
#
# Preload it (no class_name, so it resolves under headless --script runs):
#   const UidHeader = preload("res://tools/uid_header.gd")


# Returns the `uid://...` declared in a file's first line, or "" if none.
static func read_header_uid(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var line := fa.get_line()
	fa.close()
	return _extract_uid(line)


# Ensures `path`'s header carries a uid. No-op if it already has one. Reuses
# `preferred` (e.g. the uid the file had before a re-save) when it's free,
# otherwise mints a fresh one. Registers the uid with ResourceUID either way.
static func ensure_header_uid(path: String, preferred: String = "") -> void:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return
	var txt := fa.get_as_text()
	fa.close()

	var nl := txt.find("\n")
	var header := txt.substr(0, nl) if nl != -1 else txt
	if _extract_uid(header) != "":
		return  # already has a header uid

	# Reuse the preferred uid unless it's empty or already owned by a DIFFERENT
	# file (a real collision). A uid that already maps to THIS path is fine to keep.
	var uid := preferred
	if uid == "":
		uid = ResourceUID.id_to_text(ResourceUID.create_id())
	else:
		var pid := ResourceUID.text_to_id(uid)
		if ResourceUID.has_id(pid) and ResourceUID.get_id_path(pid) != path:
			uid = ResourceUID.id_to_text(ResourceUID.create_id())

	var close := header.rfind("]")
	if close == -1:
		return
	var rest := txt.substr(nl) if nl != -1 else ""
	var new_txt := header.substr(0, close) + ' uid="%s"' % uid + header.substr(close) + rest

	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		return
	w.store_string(new_txt)
	w.close()

	var id := ResourceUID.text_to_id(uid)
	if ResourceUID.has_id(id):
		ResourceUID.set_id(id, path)
	else:
		ResourceUID.add_id(id, path)


static func _extract_uid(s: String) -> String:
	var k := s.find('uid="uid://')
	if k == -1:
		return ""
	var start := s.find('"', k) + 1
	var end := s.find('"', start)
	if end == -1:
		return ""
	return s.substr(start, end - start)
