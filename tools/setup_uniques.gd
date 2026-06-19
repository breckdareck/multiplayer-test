extends SceneTree
## Author the boss uniques as .tres TEXT (no ItemData/WeaponData instantiation, so it
## runs headless without the ResourceManager autoload). Writes the unique ITEM and its
## DROP TABLE (@ boss rate), preserving existing UIDs / item_ids. Run on the 4.7 binary.
## After this, wire the new drop tables into the boss ED_*.tres (see printed UIDs).
const UidHeader = preload("res://tools/uid_header.gd")
const UNIQUE_DIR := "res://resources/Items/Unique/"
const DROP_DIR := "res://resources/DropTables/Generated/"
const STAT := "res://scripts/Resources/StatSystem/StatData.gd"
const WCLS := "res://scripts/Resources/ItemSystem/WeaponData.gd"
const ACLS := "res://scripts/Resources/ItemSystem/ArmorData.gd"
const DCLS := "res://scripts/Resources/ItemSystem/ItemDrop.gd"
const ICON := "res://assets/sprites/Items/generated_px/Unique/"
const UNIQUE_RATE := 0.1

# stat ints: STR0 INT1 DEX2 LUCK3 HEALTH4 MANA5 HPREGEN6 MPREGEN7 DEF8 MDEF9 CRITCH10 CRITDMG11 WATK12 MATK13
var SPECS := [
	# --- Eternal Warlord (Lv100): one weapon per type + chest + helm ---
	{"name":"Dawnbreaker","kind":"w","wt":0,"sp":5,"lv":100,"icon":"Dawnbreaker","boss":"warlord",
		"desc":"A radiant greatsword quenched in dawnlight — the Warlord's bane.","stats":{12:230,0:80,11:45,4:800}},
	{"name":"Stormpiercer","kind":"w","wt":1,"sp":6,"lv":100,"icon":"Stormpiercer","boss":"warlord",
		"desc":"A bow that looses arrows wreathed in screaming wind.","stats":{12:215,2:90,10:32,11:60}},
	{"name":"Staff of Eternity","kind":"w","wt":2,"sp":4,"lv":100,"icon":"Staff_of_Eternity","boss":"warlord",
		"desc":"An ancient staff humming with limitless arcane reserves.","stats":{13:270,1:100,5:1400,7:50}},
	{"name":"Shadowfang","kind":"w","wt":3,"sp":9,"lv":100,"icon":"Shadowfang","boss":"warlord",
		"desc":"A blackened fang that drinks the light around it.","stats":{12:175,3:95,10:40,11:80}},
	{"name":"Aegis of the Vanguard","kind":"a","at":1,"lv":100,"icon":"Aegis_of_the_Vanguard","boss":"warlord",
		"desc":"An impregnable bulwark that has turned a hundred embers.","stats":{8:180,9:120,4:1600,0:60}},
	{"name":"Ironwill Helm","kind":"a","at":0,"lv":100,"icon":"Ironwill_Helm","boss":"warlord",
		"desc":"A crown-helm that has never once been split.","stats":{8:110,4:1000,0:40,6:40}},
	# --- Thornroot Warchief (Lv30): one weapon per type (reuse weapon-type icons) ---
	{"name":"Thornroot Cleaver","kind":"w","wt":0,"sp":5,"lv":30,"icon":"Dawnbreaker","boss":"warchief",
		"desc":"A jagged greatblade grown from the Hollow's deepest root.","stats":{12:82,0:26,11:20,4:200}},
	{"name":"Bramblefang Bow","kind":"w","wt":1,"sp":6,"lv":30,"icon":"Stormpiercer","boss":"warchief",
		"desc":"A living bow strung with barbed bramble.","stats":{12:76,2:28,10:16,11:22}},
	{"name":"Hollowroot Staff","kind":"w","wt":2,"sp":4,"lv":30,"icon":"Staff_of_Eternity","boss":"warchief",
		"desc":"A gnarled staff that channels the Hollow's hungry sap.","stats":{13:92,1:30,5:360,7:16}},
	{"name":"Thorn Fang","kind":"w","wt":3,"sp":9,"lv":30,"icon":"Shadowfang","boss":"warchief",
		"desc":"A thorn honed to a venomous edge.","stats":{12:62,3:30,10:20,11:30}},
]

func _fname(n: String) -> String:
	return n.replace(" ", "_")

func _read_field(path: String, field: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var txt := FileAccess.get_file_as_string(path)
	var re := RegEx.create_from_string('%s = "([^"]+)"' % field)
	var m := re.search(txt)
	return m.get_string(1) if m else ""

func _build_item(spec: Dictionary, item_id: String) -> String:
	var is_w: bool = spec.kind == "w"
	var cls: String = WCLS if is_w else ACLS
	var sc: String = "WeaponData" if is_w else "ArmorData"
	var stats: Dictionary = spec.stats
	var keys: Array = stats.keys(); keys.sort()
	var load_steps := 3 + keys.size() + 1
	var s := '[gd_resource type="Resource" script_class="%s" load_steps=%d format=3]\n\n' % [sc, load_steps]
	s += '[ext_resource type="Script" path="%s" id="1_stat"]\n' % STAT
	s += '[ext_resource type="Texture2D" path="%s%s.png" id="2_icon"]\n' % [ICON, spec.icon]
	s += '[ext_resource type="Script" path="%s" id="3_cls"]\n\n' % cls
	var dict_lines: Array = []
	for i in keys.size():
		var t: int = keys[i]
		s += '[sub_resource type="Resource" id="Resource_s%d"]\n' % i
		s += 'script = ExtResource("1_stat")\n'
		s += 'stat_type = %d\n' % t
		s += 'base_value = 0\n'
		s += 'flat_bonus_value = %d\n\n' % int(stats[t])
		dict_lines.append('%d: SubResource("Resource_s%d")' % [t, i])
	s += '[resource]\n'
	s += 'script = ExtResource("3_cls")\n'
	if is_w:
		s += 'weapon_type = %d\n' % int(spec.wt)
		s += 'weapon_attack_speed = %d\n' % int(spec.sp)
	else:
		s += 'armor_type = %d\n' % int(spec.at)
	s += 'equipment_type = 1\n'
	s += 'bonus_stats = Dictionary[int, ExtResource("1_stat")]({\n'
	s += ',\n'.join(dict_lines) + '\n'
	s += '})\n'
	s += 'item_id = "%s"\n' % item_id
	s += 'name = "%s"\n' % spec.name
	s += 'rarity = 4\n'
	s += 'icon = ExtResource("2_icon")\n'
	s += 'description = "%s"\n' % spec.desc
	s += 'item_type = 1\n'
	s += 'item_level = %d\n' % int(spec.lv)
	s += 'custom_item_value = 0\n'
	return s

func _build_drop(name: String) -> String:
	var s := '[gd_resource type="Resource" script_class="ItemDropResource" load_steps=2 format=3]\n\n'
	s += '[ext_resource type="Script" path="%s" id="1_drop"]\n\n' % DCLS
	s += '[resource]\n'
	s += 'script = ExtResource("1_drop")\n'
	s += 'item_name = "%s"\n' % name
	s += 'drop_chance = %s\n' % str(UNIQUE_RATE)
	return s

func _write(path: String, text: String) -> void:
	var prev_uid := UidHeader.read_header_uid(path)
	var w := FileAccess.open(path, FileAccess.WRITE)
	w.store_string(text); w.close()
	UidHeader.ensure_header_uid(path, prev_uid)

func _initialize() -> void:
	for spec in SPECS:
		var fn: String = _fname(spec.name)
		var item_path := UNIQUE_DIR + fn + ".tres"
		var drop_path := DROP_DIR + fn + ".tres"
		var item_id := _read_field(item_path, "item_id")
		if item_id == "":
			item_id = "u_" + fn.to_lower()
		_write(item_path, _build_item(spec, item_id))
		_write(drop_path, _build_drop(spec.name))
	print("=== boss unique drop tables (wire these UIDs into the ED_*.tres) ===")
	for spec in SPECS:
		var fn: String = _fname(spec.name)
		var uid := UidHeader.read_header_uid(DROP_DIR + fn + ".tres")
		print("  [%s] %-22s -> %s  (Generated/%s.tres)" % [spec.boss, spec.name, uid, fn])
	quit()
