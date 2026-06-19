extends SceneTree
## Retune drop_chance on GENERATED equip drop tables (text edit only — never touches
## items or item_id, preserves each .tres UID/format). Trash gear follows the reversed
## curve (6% @Lv1 -> 1% @Lv100); boss-exclusive tier tables get the generous boss rate.
## Keep in sync with generate_item_content.gd::_equip_drop_chance. Run on the 4.7 binary:
##   Godot_v4.7 --headless --path . --script res://tools/retune_drops.gd
const DROP_DIR := "res://resources/DropTables/Generated/"
const ITEM_DIRS := [
	"res://resources/Items/Weapons/Generated/",
	"res://resources/Items/Armor/Generated/",
]
const BOSS_RATE := 0.25
# Boss-exclusive tier tables (only the bosses drop these specific items) -> boss rate,
# decoupled from the trash curve. NOTE: Steel_Dirk is shared with field mobs, so it
# stays on the trash curve.
const BOSS_TABLES := [
	"Eternal_Longsword", "Eternal_Warbow", "Eternal_Spellstaff", "Eternal_Dirk",
	"Eternal_Vanguard_Mail", "Eternal_Arcanist_Mail", "Eternal_Nightshade_Mail", "Eternal_Pathfinder_Mail",
	"Steel_Longsword", "Steel_Warbow", "Steel_Spellstaff", "Steel_Vanguard_Mail",
]

func _curve(lv: int) -> float:
	return clampf(0.06 - lv * 0.0005, 0.01, 0.06)

func _initialize() -> void:
	var name_lvl := {}    # item display name -> item_level
	var re_name := RegEx.create_from_string('\\nname = "([^"]+)"')
	var re_lvl := RegEx.create_from_string('\\nitem_level = (\\d+)')
	for d in ITEM_DIRS:
		var da := DirAccess.open(d)
		if da == null:
			continue
		for fn in da.get_files():
			if not fn.ends_with(".tres"):
				continue
			var txt := FileAccess.get_file_as_string(d + fn)
			var mn := re_name.search(txt)
			var ml := re_lvl.search(txt)
			if mn and ml:
				name_lvl[mn.get_string(1)] = int(ml.get_string(1))

	var boss := {}
	for b in BOSS_TABLES:
		boss[b] = true

	var re_iname := RegEx.create_from_string('item_name = "([^"]+)"')
	var re_chance := RegEx.create_from_string('drop_chance = [0-9.]+')
	var changed := 0
	var missing := []
	var da2 := DirAccess.open(DROP_DIR)
	for fn in da2.get_files():
		if not fn.ends_with(".tres"):
			continue
		var path := DROP_DIR + fn
		var txt := FileAccess.get_file_as_string(path)
		if not ("randomize_stats = true" in txt):
			continue   # only equipment tables roll the curve
		var base := fn.get_basename()
		var new_chance: float
		if boss.has(base):
			new_chance = BOSS_RATE
		else:
			var im := re_iname.search(txt)
			var iname := im.get_string(1) if im else ""
			if not name_lvl.has(iname):
				missing.append(iname)
				continue
			new_chance = _curve(name_lvl[iname])
		new_chance = snappedf(new_chance, 0.001)
		var new_txt := re_chance.sub(txt, "drop_chance = %s" % str(new_chance))
		if new_txt != txt:
			var w := FileAccess.open(path, FileAccess.WRITE)
			w.store_string(new_txt)
			w.close()
			changed += 1
	print("Retuned %d equip drop tables (boss-exclusive @ %.2f)." % [changed, BOSS_RATE])
	if not missing.is_empty():
		print("WARNING: no item level for: ", missing)
	quit()
