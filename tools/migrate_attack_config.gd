extends SceneTree
## One-shot, TEXT-based migration for the presence-based attack poll: a RANGED enemy
## (EnemyData.attack_type != MELEE) must NOT carry a melee_attack node, or the poll
## would make a caster melee. This strips the dead melee_attack node + its idle/patrol
## references from every ranged enemy scene. (Instantiate-based editing is impossible
## headless — enemy scripts reference autoloads that don't load under --script — so we
## edit the .tscn text directly; EnemyData itself loads fine for the attack_type read.)
##
## The ~3 secondary/breath enemies + 3 blockers are hand-migrated (node exports +
## block-before-melee order). Run:
##   godot --headless --path . --script res://tools/migrate_attack_config.gd  [--dry]

const ENEMY_DIR := "res://scenes/NPC"
const ENEMY_BASE := "res://scripts/Enemy/enemy_base.gd"

var _dry := false


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--dry": _dry = true
	var files: Array[String] = []
	_collect(ENEMY_DIR, files)
	var changed := 0
	for path in files:
		if _migrate(path):
			changed += 1
	print("\n=== migrate_attack_config: %d/%d ranged scenes de-meleed %s ===" % [changed, files.size(), ("(dry)" if _dry else "")])
	quit()


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null: return
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if d.current_is_dir() and not n.begins_with("."):
			_collect(dir_path + "/" + n, out)
		elif n.ends_with(".tscn"):
			out.append(dir_path + "/" + n)
		n = d.get_next()
	d.list_dir_end()


func _migrate(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return false
	var text := f.get_as_text()
	f.close()
	if not text.contains(ENEMY_BASE) or not text.contains('name="melee_attack"'):
		return false
	# Ranged only — read attack_type off the EnemyData (loads fine; no autoload deps).
	var ed = _load_enemy_data(text)
	if ed == null or ed.attack_type == Constants.AttackType.MELEE:
		return false

	var lines := text.split("\n")
	var out: Array[String] = []
	var i := 0
	var removed_node := false
	while i < lines.size():
		var line: String = lines[i]
		# Drop the whole melee_attack node block (header → trailing blank line).
		if line.begins_with('[node name="melee_attack" '):
			removed_node = true
			i += 1
			while i < lines.size() and lines[i] != "" and not lines[i].begins_with("["):
				i += 1
			if i < lines.size() and lines[i] == "":
				i += 1  # eat the trailing blank
			continue
		# Drop idle/patrol references to the now-gone melee node.
		if line.begins_with("melee_attack_state = "):
			i += 1
			continue
		line = line.replace('PackedStringArray("patrol_state", "melee_attack_state")', 'PackedStringArray("patrol_state")')
		line = line.replace('PackedStringArray("idle_state", "melee_attack_state")', 'PackedStringArray("idle_state")')
		out.append(line)
		i += 1

	if not removed_node:
		return false
	print(path.replace("res://scenes/NPC/", ""), "  -melee")
	if _dry:
		return true
	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null: return false
	w.store_string("\n".join(out))
	w.close()
	return true


func _load_enemy_data(text: String):
	var re := RegEx.new()
	re.compile('\\[ext_resource type="Resource"[^\\]]*path="(res://resources/Enemies/[^"]+)"')
	var m := re.search(text)
	if m == null:
		return null
	return load(m.get_string(1))
