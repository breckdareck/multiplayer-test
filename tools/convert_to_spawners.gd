extends SceneTree
## Convert maps from hard-placed enemy instances to the new pool-based EnemySpawner
## method: one EnemySpawner node per enemy type, a Marker2D per original enemy placed
## LIFT px above its old spot, pool_size = that type's original count, plus the
## MultiplayerSpawner child. Bosses (instances that set respawn_delay) and friendly
## NPCs (training_dummy / merchant / quest_giver) are left exactly where they are.
##
## Idempotent: a converted map has no hard-placed instances left under "Enemies", so a
## re-run finds nothing to convert and skips it.
##
## Run: Godot --headless --path <overhaul> --script res://tools/convert_to_spawners.gd

const MAPS := [
	"old_battlefield", "mustering_fields", "cinderwaste",
]
const SKIP_PATHS := ["training_dummy", "merchant", "quest_giver", "village_elder"]
const LIFT := 10   # px above the original enemy spot ("10px above the ground")

func _init() -> void:
	for name in MAPS:
		_convert(name)
	quit()

func _convert(map: String) -> void:
	var path := "res://scenes/Levels/%s.tscn" % map
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		print(map, ": MISSING"); return
	var text := fa.get_as_text(); fa.close()

	# ext_resources: id -> {path, uid}; locate the two spawner scripts if already present.
	var ext := {}
	var spw_id := ""; var msp_id := ""
	var ere := RegEx.new(); ere.compile('\\[ext_resource[^\\]]*\\]')
	for m in ere.search_all(text):
		var line := m.get_string(0)
		var id := _attr(line, "id")
		var p := _attr(line, "path")
		ext[id] = {"path": p, "uid": _attr(line, "uid")}
		if p == "res://scripts/Enemy/enemy_spawner.gd": spw_id = id
		if p == "res://scripts/Gameplay/enemy_multiplayer_spawner.gd": msp_id = id

	var nodes := _nodes(text)
	var enemies_off := Vector2.ZERO
	var used_names := {}
	for n in nodes:
		used_names[n["name"]] = true
		if n["name"] == "Enemies" and n["parent"] == ".":
			enemies_off = _vec(n["body"], "position")

	# Group convertible enemy instances (children of Enemies) by ext id.
	var groups := {}   # ext_id -> {positions:[Vector2], spans:[[start,end]]}
	for n in nodes:
		if n["parent"] != "Enemies" or not n["is_instance"]:
			continue
		var ep: String = ext.get(n["instance_id"], {}).get("path", "")
		if ep == "":
			continue
		var skip := false
		for s in SKIP_PATHS:
			if ep.findn(s) != -1: skip = true; break
		if skip:
			continue
		if n["body"].find("respawn_delay") != -1:
			continue   # boss: leave in place
		var g = groups.get(n["instance_id"])
		if g == null:
			g = {"positions": [], "spans": []}; groups[n["instance_id"]] = g
		g["positions"].append(enemies_off + _vec(n["body"], "position"))
		g["spans"].append([n["header_start"], n["block_end"]])

	if groups.is_empty():
		print(map, ": no convertible enemies — left as-is")
		return

	# Add the spawner scripts as ext_resources if missing.
	var added := ""
	if spw_id == "":
		spw_id = "conv_spw"
		added += '\n[ext_resource type="Script" path="res://scripts/Enemy/enemy_spawner.gd" id="conv_spw"]'
	if msp_id == "":
		msp_id = "conv_msp"
		added += '\n[ext_resource type="Script" path="res://scripts/Gameplay/enemy_multiplayer_spawner.gd" id="conv_msp"]'

	# Build one spawner block per enemy type.
	var blocks := ""; var total := 0; var summary := []
	for eid in groups:
		var g = groups[eid]
		var epath: String = ext[eid]["path"]
		var uid: String = ext[eid]["uid"]
		var tname := _type_name(epath)
		var sname := tname + "Spawner"
		var k := 1
		while used_names.has(sname):
			sname = "%sSpawner%d" % [tname, k]; k += 1
		used_names[sname] = true
		var count: int = g["positions"].size()
		total += count
		summary.append("%s×%d" % [tname, count])
		var locs := []; var markers := ""
		for i in count:
			locs.append('NodePath("M%d")' % i)
			var wp: Vector2 = g["positions"][i]
			markers += '\n\n[node name="M%d" type="Marker2D" parent="%s"]\nposition = Vector2(%d, %d)' % [i, sname, int(round(wp.x)), int(round(wp.y)) - LIFT]
		blocks += '\n\n[node name="%s" type="Node2D" parent="." node_paths=PackedStringArray("spawn_locations", "spawn_container")]' % sname
		blocks += '\nscript = ExtResource("%s")' % spw_id
		blocks += '\nenemy_scene = ExtResource("%s")' % eid
		blocks += '\nspawn_locations = [%s]' % ", ".join(locs)
		blocks += '\nspawn_container = NodePath("../Enemies")'
		blocks += '\npool_size = %d' % count
		blocks += markers
		blocks += '\n\n[node name="MultiplayerSpawner" type="MultiplayerSpawner" parent="%s" node_paths=PackedStringArray("enemy_spawner")]' % sname
		blocks += '\n_spawnable_scenes = PackedStringArray("%s")' % (uid if uid != "" else epath)
		blocks += '\nspawn_path = NodePath("../../Enemies")'
		blocks += '\nscript = ExtResource("%s")' % msp_id
		blocks += '\nenemy_spawner = NodePath("..")'

	# Remove the converted instance blocks (descending so indices stay valid).
	var spans := []
	for eid in groups:
		for s in groups[eid]["spans"]: spans.append(s)
	spans.sort_custom(func(a, b): return a[0] > b[0])
	for s in spans:
		text = text.substr(0, s[0]) + text.substr(s[1])

	# Insert new ext_resources after the last existing one + bump load_steps.
	if added != "":
		var ins := text.find("\n", text.rfind("[ext_resource"))
		text = text.substr(0, ins) + added + text.substr(ins)
		var lsre := RegEx.new(); lsre.compile("load_steps=(\\d+)")
		var lm := lsre.search(text)
		if lm:
			var newls := int(lm.get_string(1)) + added.count("[ext_resource")
			text = text.substr(0, lm.get_start()) + "load_steps=%d" % newls + text.substr(lm.get_end())

	text = text + blocks + "\n"
	var w := FileAccess.open(path, FileAccess.WRITE); w.store_string(text); w.close()
	print(map, ": ", " ".join(summary), "  (", total, " markers, ", groups.size(), " spawners)")

# --- helpers ------------------------------------------------------------------

func _nodes(text: String) -> Array:
	var res := []
	var nre := RegEx.new(); nre.compile('\\[node name="([^"]+)"([^\\n]*)\\]')
	var ire := RegEx.new(); ire.compile('instance=ExtResource\\("([^"]+)"\\)')
	var ms := nre.search_all(text)
	for i in ms.size():
		var m = ms[i]
		var attrs := m.get_string(2)
		var bend := text.length() if i + 1 >= ms.size() else ms[i + 1].get_start()
		var inst := ire.search(attrs)
		res.append({
			"name": m.get_string(1),
			"parent": _attr(attrs, "parent"),
			"header_start": m.get_start(),
			"block_end": bend,
			"body": text.substr(m.get_end(), bend - m.get_end()),
			"is_instance": inst != null,
			"instance_id": inst.get_string(1) if inst else "",
		})
	return res

func _attr(s: String, key: String) -> String:
	var re := RegEx.new(); re.compile('(?:^|[^A-Za-z_])%s="([^"]*)"' % key)
	var m := re.search(s)
	return m.get_string(1) if m else ""

func _vec(body: String, key: String) -> Vector2:
	var re := RegEx.new(); re.compile('%s = Vector2\\((-?[0-9.]+), (-?[0-9.]+)\\)' % key)
	var m := re.search(body)
	return Vector2(float(m.get_string(1)), float(m.get_string(2))) if m else Vector2.ZERO

func _type_name(epath: String) -> String:
	var parts := epath.get_file().get_basename().replace("_", " ").split(" ")
	var out := []
	for p in parts:
		if p.length() > 0: out.append(p[0].to_upper() + p.substr(1))
	return "".join(out)
