extends SceneTree
## One-shot migration: AUTHOR the runtime-injected enemy states as visible nodes under
## each enemy scene's StateMachine, so every state shows in the editor instead of being
## added in code. Non-destructive — it only APPENDS the missing state nodes + their
## script ext_resources to the .tscn text; everything already in the scene is left
## byte-for-byte. EnemyBase still injects as a fallback (its has_node guards skip any
## state already authored), so a missed/partial scene keeps working.
##
## Run:  godot --headless --path . --script res://tools/author_enemy_states.gd
##   add --dry to only report (no writes), or --only=<substr> to limit to matching paths.

const ENEMY_DIR := "res://scenes/NPC"
const ENEMY_BASE := "res://scripts/Enemy/enemy_base.gd"

# state name -> {script path, uid, animation_name, extra property lines}
const STATES := {
	"chase":          {"path": "res://scripts/Enemy/StateMachine/enemy_chase.gd",            "uid": "uid://c1yixl28217fi", "anim": "patrol", "props": []},
	"hit":            {"path": "res://scripts/Enemy/StateMachine/enemy_hit.gd",              "uid": "uid://c8hrwsi8wt4sv", "anim": "hit",    "props": []},
	"ranged_attack":  {"path": "res://scripts/Enemy/StateMachine/enemy_projectile_attack.gd","uid": "uid://x4f6ec0l486x",  "anim": "",       "props": ["config = 0"]},
	"secondary_proj": {"path": "res://scripts/Enemy/StateMachine/enemy_projectile_attack.gd","uid": "uid://x4f6ec0l486x",  "anim": "",       "props": ["config = 1"], "node": "secondary_attack"},
	"secondary_breath":{"path": "res://scripts/Enemy/StateMachine/enemy_hitbox_attack.gd",   "uid": "uid://drv5e8c7d80jv", "anim": "",       "props": ["config = 1", "windup = 0.12", "active = 0.55", "recover = 0.0"], "node": "secondary_attack"},
	"block":          {"path": "res://scripts/Enemy/StateMachine/enemy_block.gd",            "uid": "uid://bgfdfaahnikg3", "anim": "block",  "props": []},
	"boss_special":   {"path": "res://scripts/Enemy/StateMachine/enemy_boss_special.gd",     "uid": "uid://ccrh8avjq5lj2", "anim": "",       "props": []},
}

var _dry := false
var _only := ""


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--dry": _dry = true
		elif a.begins_with("--only="): _only = a.substr(7)
	var files: Array[String] = []
	_collect(ENEMY_DIR, files)
	var changed := 0
	for path in files:
		if _only != "" and not path.contains(_only):
			continue
		if _migrate(path):
			changed += 1
	print("\n=== %s: %d/%d enemy scenes %s ===" % ["author_enemy_states", changed, files.size(), ("would change" if _dry else "updated")])
	quit()


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir() and not n.begins_with("."):
			_collect(dir_path + "/" + n, out)
		elif n.ends_with(".tscn"):
			out.append(dir_path + "/" + n)
		n = d.get_next()
	d.list_dir_end()


## Returns true if the scene was (or would be) changed.
func _migrate(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	# Enemy scenes only: must use enemy_base.gd and have a StateMachine node.
	if not text.contains(ENEMY_BASE) or not text.contains('parent="StateMachine"') and not text.contains('name="StateMachine"'):
		return false

	var existing := _statemachine_child_names(text)
	var needed := _needed_states(text)
	var to_add: Array[String] = []
	for key in needed:
		var node_name: String = STATES[key].get("node", key)
		if node_name in existing or node_name in to_add.map(func(k): return STATES[k].get("node", k)):
			continue
		to_add.append(key)
	if to_add.is_empty():
		return false

	var added_names: Array[String] = []
	for key in to_add:
		added_names.append(STATES[key].get("node", key))
	print("%s  +[%s]" % [path.replace("res://scenes/NPC/", ""), ", ".join(added_names)])
	if _dry:
		return true

	var ext_block := ""
	var node_block := ""
	var idx := 0
	for key in to_add:
		var info: Dictionary = STATES[key]
		var node_name: String = info.get("node", key)
		var ext_id := "mig_%s" % key
		ext_block += '[ext_resource type="Script" uid="%s" path="%s" id="%s"]\n' % [info["uid"], info["path"], ext_id]
		node_block += '\n[node name="%s" type="Node" parent="StateMachine"]\n' % node_name
		node_block += 'script = ExtResource("%s")\n' % ext_id
		if info["anim"] != "":
			node_block += 'animation_name = "%s"\n' % info["anim"]
		for p in info["props"]:
			node_block += p + "\n"
		idx += 1

	# Insert the ext_resources right after the LAST existing [ext_resource ...] line,
	# and append the node blocks at the end of the file (parent path resolves them).
	var lines := text.split("\n")
	var last_ext := -1
	for i in lines.size():
		if lines[i].begins_with("[ext_resource "):
			last_ext = i
	if last_ext < 0:
		return false
	var head := "\n".join(lines.slice(0, last_ext + 1))
	var tail := "\n".join(lines.slice(last_ext + 1))
	var out_text := head + "\n" + ext_block.strip_edges(false, true) + "\n" + tail
	if not out_text.ends_with("\n"):
		out_text += "\n"
	out_text += node_block

	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		return false
	w.store_string(out_text)
	w.close()
	return true


## Names of nodes whose parent is StateMachine, parsed from the .tscn text.
func _statemachine_child_names(text: String) -> Array[String]:
	var names: Array[String] = []
	var re := RegEx.new()
	re.compile('\\[node name="([^"]+)" type="[^"]*" parent="StateMachine"')
	for m in re.search_all(text):
		names.append(m.get_string(1))
	return names


## Which states this enemy needs, from its EnemyData flags (chase/hit always).
func _needed_states(text: String) -> Array[String]:
	var out: Array[String] = ["chase", "hit"]
	var ed: EnemyData = _load_enemy_data(text)
	if ed == null:
		return out
	if ed.attack_type != Constants.AttackType.MELEE:
		out.append("ranged_attack")
	if ed.secondary_attack_anim != "" and (not ed.secondary_breath_sprite.is_empty() or ed.secondary_projectile_scene != null):
		out.append("secondary_breath" if not ed.secondary_breath_sprite.is_empty() else "secondary_proj")
	if ed.is_blocker:
		out.append("block")
	if ed.is_boss and not ed.get_special_attacks().is_empty():
		out.append("boss_special")
	return out


## Loads the enemy's EnemyData by finding the Resource ext_resource under /Enemies/.
func _load_enemy_data(text: String):
	var re := RegEx.new()
	re.compile('\\[ext_resource type="Resource"[^\\]]*path="(res://resources/Enemies/[^"]+)"')
	var m := re.search(text)
	if m == null:
		return null
	return load(m.get_string(1))
