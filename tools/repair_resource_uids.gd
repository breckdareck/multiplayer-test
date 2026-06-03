# One-time repair for missing / mismatched resource UIDs.
#
# Background: the bulk content generators (generate_item_content.gd,
# assign_enemy_drops.gd) save .tres via ResourceSaver.save(), which — run
# headless — does NOT write a `uid="uid://..."` header. Every generated drop
# table / consumable / item therefore has no persistent UID, yet consumers
# (enemy ED_*.tres, town.tscn) reference them BY uid. Godot can't resolve the
# uid, warns "invalid UID - using text path instead", and falls back to the
# path. Hundreds of these warnings flood the log.
#
# This tool makes every resource carry a stable header UID and makes every
# ext_resource reference agree with its target's header UID:
#   Pass 0  collect, per target path, which uid(s) consumers reference it by.
#   Pass 1  give every .tres/.tscn a header uid. Files that already have one
#           keep it. Uid-less files ADOPT the uid their consumers already use
#           (so those references need no edit); if none, a fresh uid is minted.
#   Pass 2  rewrite any ext_resource reference whose uid disagrees with the
#           target's header uid (fixes genuine mismatches, e.g. a renamed scene).
#   Pass 3  verify zero mismatches remain.
#
# Run once:
#   godot --headless --path . --script res://tools/repair_resource_uids.gd
# Then rebuild the UID cache: godot --headless --editor --quit --path .
extends SceneTree

const ROOTS := ["res://resources/", "res://scenes/"]

var _re_uid := RegEx.new()
var _re_path := RegEx.new()


func _initialize() -> void:
	_re_uid.compile('uid="(uid://[^"]+)"')
	_re_path.compile('path="(res://[^"]+)"')

	var files: Array[String] = []
	for r in ROOTS:
		_collect(r, files)
	print("=== Resource UID repair ===")
	print("Scanning %d resource files..." % files.size())

	# Pass 0 — per target path, tally the uids that consumers reference it by.
	var ref_uids := {}  # path -> { uid: count }
	for f in files:
		for line in _read(f).split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			var mu := _re_uid.search(line)
			var mp := _re_path.search(line)
			if mu == null or mp == null:
				continue
			var p := mp.get_string(1)
			var u := mu.get_string(1)
			if not ref_uids.has(p):
				ref_uids[p] = {}
			ref_uids[p][u] = int(ref_uids[p].get(u, 0)) + 1

	# Pass 1 — ensure a header uid on every file; build path -> uid.
	var path_uid := {}
	var used_uids := {}   # uid -> owning path (guards against duplicate uids)
	var pending: Array[String] = []
	# Lock files that already declare a header uid first — never reassign those.
	for f in files:
		var mh := _re_uid.search(_read_first_line(f))
		if mh != null:
			var u := mh.get_string(1)
			path_uid[f] = u
			used_uids[u] = f
		else:
			pending.append(f)
	# Assign uids to the remainder: adopt a free consumer-referenced uid, else mint.
	var adopted := 0
	var minted := 0
	for f in pending:
		var chosen := ""
		if ref_uids.has(f):
			var best := ""
			var best_n := -1
			for u in ref_uids[f]:
				if used_uids.has(u):
					continue  # already owned by another file — can't adopt
				var n := int(ref_uids[f][u])
				if n > best_n:
					best = u
					best_n = n
			if best != "":
				chosen = best
				adopted += 1
		if chosen == "":
			chosen = ResourceUID.id_to_text(ResourceUID.create_id())
			minted += 1
		path_uid[f] = chosen
		used_uids[chosen] = f
		_write(f, _inject_header_uid(_read(f), chosen))
		var id := ResourceUID.text_to_id(chosen)
		if ResourceUID.has_id(id):
			ResourceUID.set_id(id, f)
		else:
			ResourceUID.add_id(id, f)
	print("Pass 1 headers: %d already had uid, %d adopted, %d minted." % [
		files.size() - pending.size(), adopted, minted])

	# Pass 2 — make every ext_resource reference match its target's header uid.
	var fixed_refs := 0
	var fixed_files := 0
	for f in files:
		var lines := _read(f).split("\n")
		var changed := false
		for i in lines.size():
			var line: String = lines[i]
			if not line.begins_with("[ext_resource"):
				continue
			var mp := _re_path.search(line)
			var mu := _re_uid.search(line)
			if mp == null or mu == null:
				continue
			var p := mp.get_string(1)
			if not path_uid.has(p):
				continue  # target is a .gd / outside our roots — leave untouched
			var want: String = path_uid[p]
			var have := mu.get_string(1)
			if want != have:
				lines[i] = line.replace('uid="%s"' % have, 'uid="%s"' % want)
				changed = true
				fixed_refs += 1
		if changed:
			_write(f, "\n".join(lines))
			fixed_files += 1
	print("Pass 2 refs: fixed %d references across %d files." % [fixed_refs, fixed_files])

	# Pass 3 — verify.
	var bad := 0
	for f in files:
		for line in _read(f).split("\n"):
			if not line.begins_with("[ext_resource"):
				continue
			var mp := _re_path.search(line)
			var mu := _re_uid.search(line)
			if mp == null or mu == null:
				continue
			var p := mp.get_string(1)
			if path_uid.has(p) and path_uid[p] != mu.get_string(1):
				bad += 1
				push_warning("STILL MISMATCH in %s -> %s" % [f, p])
	print("Pass 3 verify: %d remaining mismatches." % bad)
	print("=== done ===")
	quit()


func _inject_header_uid(txt: String, uid: String) -> String:
	var nl := txt.find("\n")
	var header := txt.substr(0, nl) if nl != -1 else txt
	var rest := txt.substr(nl) if nl != -1 else ""
	if _re_uid.search(header) != null:
		return txt
	var close := header.rfind("]")
	if close == -1:
		return txt
	return header.substr(0, close) + ' uid="%s"' % uid + header.substr(close) + rest


func _read_first_line(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var line := fa.get_line()
	fa.close()
	return line


func _read(path: String) -> String:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return ""
	var s := fa.get_as_text()
	fa.close()
	return s


func _write(path: String, content: String) -> void:
	var fa := FileAccess.open(path, FileAccess.WRITE)
	if fa == null:
		printerr("cannot write %s" % path)
		return
	fa.store_string(content)
	fa.close()


func _collect(dir_path: String, out: Array) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var e := d.get_next()
	while e != "":
		var full := dir_path + e
		if d.current_is_dir():
			if not e.begins_with("."):
				_collect(full + "/", out)
		elif e.ends_with(".tres") or e.ends_with(".tscn"):
			out.append(full)
		e = d.get_next()
	d.list_dir_end()
