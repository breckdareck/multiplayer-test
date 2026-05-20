# Bulk content generator for levelled weapons, armor, consumables and their
# drop tables. Emits .tres resources under resources/Items/.../Generated/ and
# resources/DropTables/Generated/.
#
# Run headlessly from the project root:
#   godot --headless --path . --script res://tools/generate_item_content.gd
#
# Re-runnable: it clears the Generated/ folders first, so tweaking the scaling
# tables below and re-running fully rebalances the item set.
extends SceneTree

const LEVELS: Array = [1, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
const TIERS: Array = ["Worn", "Bronze", "Iron", "Steel", "Mithril", "Adamant",
	"Runic", "Dragonbone", "Celestial", "Astral", "Eternal"]

# StatType ids — mirror of Constants.StatType, kept local for terse tables.
const STR := 0
const INT := 1
const DEX := 2
const LUCK := 3
const HEALTH := 4
const MANA := 5
const HPREGEN := 6
const MPREGEN := 7
const DEF := 8
const MDEF := 9
const CRITCHANCE := 10
const CRITDMG := 11
const WEAPONATK := 12
const MAGICATK := 13

const WEAPON_DIR := "res://resources/Items/Weapons/Generated/"
const ARMOR_DIR := "res://resources/Items/Armor/Generated/"
const CONSUMABLE_DIR := "res://resources/Items/Consumables/Generated/"
const UNIQUE_DIR := "res://resources/Items/Unique/"
const DROP_DIR := "res://resources/DropTables/Generated/"

const EFFECT_HEAL := "res://scripts/Resources/ItemSystem/Effects/Effect_RestoreHealth.gd"
const EFFECT_MANA := "res://scripts/Resources/ItemSystem/Effects/Effect_RestoreMana.gd"

const ICON_SOURCES := {
	"sword": "res://resources/Items/Weapons/Iron_Sword.tres",
	"bow": "res://resources/Items/Weapons/Iron_Sword.tres",
	"staff": "res://resources/Items/Weapons/Oak_Staff.tres",
	"dagger": "res://resources/Items/Weapons/Bronze_Dagger.tres",
	"armor0": "res://resources/Items/Armor/Leather_Cap.tres",
	"armor1": "res://resources/Items/Armor/Leather_Vest.tres",
	"armor2": "res://resources/Items/Armor/Blue_Jean_Shorts.tres",
	"armor3": "res://resources/Items/Armor/Leather_Sandals.tres",
	"hp": "res://resources/Items/Consumables/Grape_Potion.tres",
	"mp": "res://resources/Items/Consumables/Mana_Potion.tres",
}

var _icon_cache: Dictionary = {}
var _counts: Dictionary = {"weapons": 0, "armor": 0, "consumables": 0, "uniques": 0, "drops": 0}


func _initialize() -> void:
	print("=== Item content generator ===")
	for d in [WEAPON_DIR, ARMOR_DIR, CONSUMABLE_DIR, UNIQUE_DIR, DROP_DIR]:
		DirAccess.make_dir_recursive_absolute(d)
		_clear_dir(d)
	_generate_weapons()
	_generate_armor()
	_generate_consumables()
	_generate_uniques()
	print("Generated %d weapons, %d armor, %d consumables, %d uniques, %d drop tables." % [
		_counts["weapons"], _counts["armor"], _counts["consumables"],
		_counts["uniques"], _counts["drops"]])
	quit()


# --- Weapons: 4 class lines (Sword/Bow/Staff/Dagger) x 11 level tiers ---------
func _generate_weapons() -> void:
	var defs := [
		{"noun": "Longsword", "wtype": 0, "speed": 4, "icon": "sword",
		 "desc": "A balanced blade — the Swordsman's trusted companion.",
		 "stats": [[WEAPONATK, 7.0, 1.5], [STR, 2.0, 0.35]]},
		{"noun": "Warbow", "wtype": 1, "speed": 5, "icon": "bow",
		 "desc": "A finely strung bow built for an Archer's precision.",
		 "stats": [[WEAPONATK, 6.0, 1.35], [DEX, 2.0, 0.4], [CRITCHANCE, 1.0, 0.06]]},
		{"noun": "Spellstaff", "wtype": 2, "speed": 3, "icon": "staff",
		 "desc": "A conduit of arcane power wielded by Mages.",
		 "stats": [[MAGICATK, 7.0, 1.5], [INT, 2.0, 0.4], [MANA, 6.0, 1.2]]},
		{"noun": "Dirk", "wtype": 3, "speed": 8, "icon": "dagger",
		 "desc": "A swift, wickedly sharp blade prized by Rogues.",
		 "stats": [[WEAPONATK, 4.0, 0.95], [LUCK, 2.0, 0.35], [CRITCHANCE, 2.0, 0.12]]},
	]
	for d in defs:
		for i in LEVELS.size():
			var lv: int = LEVELS[i]
			var w := WeaponData.new()
			w.name = "%s %s" % [TIERS[i], d["noun"]]
			w.item_type = Constants.ItemType.EQUIPMENT
			w.equipment_type = Constants.EquipmentType.WEAPON
			w.weapon_type = d["wtype"]
			w.weapon_attack_speed = d["speed"]
			w.item_level = lv
			w.rarity = Constants.ItemRarity.COMMON
			w.description = d["desc"]
			w.icon = _get_icon(d["icon"])
			for st in d["stats"]:
				w.bonus_stats[st[0]] = _stat(st[0], maxi(1, roundi(st[1] + lv * st[2])))
			_save(w, WEAPON_DIR + _fname(w.name) + ".tres")
			_counts["weapons"] += 1
			_make_drop_table(w, _equip_drop_chance(lv), true)


# --- Armor: 4 class-themed sets x 4 slots x 11 level tiers --------------------
func _generate_armor() -> void:
	var sets := [
		{"name": "Vanguard", "desc": "Heavy plate forged for front-line Swordsmen.",
		 "theme": [[STR, 1.0, 0.25], [HEALTH, 8.0, 1.8]]},
		{"name": "Pathfinder", "desc": "Light, flexible armour suited to an Archer's mobility.",
		 "theme": [[DEX, 1.0, 0.3], [CRITCHANCE, 1.0, 0.05]]},
		{"name": "Arcanist", "desc": "Enchanted vestments that channel a Mage's power.",
		 "theme": [[INT, 1.0, 0.3], [MANA, 6.0, 1.5]]},
		{"name": "Nightshade", "desc": "Shadowy garb tailored for a Rogue's deadly craft.",
		 "theme": [[LUCK, 1.0, 0.3], [CRITDMG, 1.0, 0.08]]},
	]
	var slots := [
		{"atype": 0, "noun": "Helm", "weight": 0.6, "icon": "armor0"},
		{"atype": 1, "noun": "Mail", "weight": 1.0, "icon": "armor1"},
		{"atype": 2, "noun": "Legguards", "weight": 0.8, "icon": "armor2"},
		{"atype": 3, "noun": "Boots", "weight": 0.5, "icon": "armor3"},
	]
	for s in sets:
		for slot in slots:
			for i in LEVELS.size():
				var lv: int = LEVELS[i]
				var wgt: float = slot["weight"]
				var a := ArmorData.new()
				a.name = "%s %s %s" % [TIERS[i], s["name"], slot["noun"]]
				a.item_type = Constants.ItemType.EQUIPMENT
				a.equipment_type = Constants.EquipmentType.ARMOR
				a.armor_type = slot["atype"]
				a.item_level = lv
				a.rarity = Constants.ItemRarity.COMMON
				a.description = s["desc"]
				a.icon = _get_icon(slot["icon"])
				a.bonus_stats[DEF] = _stat(DEF, maxi(1, roundi((3.0 + lv * 0.7) * wgt)))
				a.bonus_stats[MDEF] = _stat(MDEF, maxi(1, roundi((2.0 + lv * 0.4) * wgt)))
				for t in s["theme"]:
					a.bonus_stats[t[0]] = _stat(t[0], maxi(1, roundi((t[1] + lv * t[2]) * wgt)))
				_save(a, ARMOR_DIR + _fname(a.name) + ".tres")
				_counts["armor"] += 1
				_make_drop_table(a, _equip_drop_chance(lv), true)


# --- Consumables: HP / MP restoratives, 6 tiers each -------------------------
func _generate_consumables() -> void:
	var heal_script: Script = load(EFFECT_HEAL)
	var mana_script: Script = load(EFFECT_MANA)
	var values := [40, 110, 260, 520, 920, 1600]
	var hp_names := ["Lesser Healing Draught", "Healing Draught", "Greater Healing Draught",
		"Grand Healing Draught", "Superior Healing Draught", "Supreme Healing Draught"]
	var hp_amounts := [60, 150, 320, 600, 1050, 1800]
	var mp_names := ["Lesser Mana Draught", "Mana Draught", "Greater Mana Draught",
		"Grand Mana Draught", "Superior Mana Draught", "Supreme Mana Draught"]
	var mp_amounts := [40, 100, 220, 420, 720, 1200]
	for i in hp_names.size():
		_make_consumable(hp_names[i], "hp", heal_script, "heal_amount", hp_amounts[i],
			values[i], "Restores %d HP when consumed." % hp_amounts[i], 0.26 - i * 0.02)
		_make_consumable(mp_names[i], "mp", mana_script, "regain_amount", mp_amounts[i],
			values[i], "Restores %d MP when consumed." % mp_amounts[i], 0.26 - i * 0.02)


func _make_consumable(cname: String, icon: String, effect: Script, prop: String,
		amount: int, value: int, desc: String, drop: float) -> void:
	var c := ConsumableData.new()
	c.name = cname
	c.item_level = -1
	c.custom_item_value = value
	c.rarity = Constants.ItemRarity.COMMON
	c.description = desc
	c.icon = _get_icon(icon)
	c.effect_script = effect
	c.effect_properties = {prop: amount}
	c.can_stack = true
	c.max_stack_amount = 99
	_save(c, CONSUMABLE_DIR + _fname(cname) + ".tres")
	_counts["consumables"] += 1
	_make_drop_table(c, drop, false, 1, 3)


# --- Unique items: hand-tuned legendaries, one set per class -----------------
func _generate_uniques() -> void:
	_make_unique_weapon("Dawnbreaker", 0, 5, 50, "sword",
		"A radiant greatsword said to have been quenched in dawnlight.",
		{WEAPONATK: 95, STR: 30, CRITDMG: 25, HEALTH: 200})
	_make_unique_weapon("Stormpiercer", 1, 6, 55, "bow",
		"A bow that looses arrows wreathed in crackling wind.",
		{WEAPONATK: 88, DEX: 35, CRITCHANCE: 22, CRITDMG: 30})
	_make_unique_weapon("Staff of Eternity", 2, 4, 60, "staff",
		"An ancient staff humming with limitless arcane reserves.",
		{MAGICATK: 110, INT: 40, MANA: 500, MPREGEN: 20})
	_make_unique_weapon("Shadowfang", 3, 9, 55, "dagger",
		"A blackened fang that seems to drink the light around it.",
		{WEAPONATK: 70, LUCK: 38, CRITCHANCE: 28, CRITDMG: 40})
	_make_unique_armor("Aegis of the Vanguard", 1, 60, "armor1",
		"An impregnable bulwark worn by legendary Swordsmen.",
		{DEF: 70, MDEF: 45, HEALTH: 600, STR: 25})
	_make_unique_armor("Ironwill Helm", 0, 40, "armor0",
		"A battered helm that has never once been split.",
		{DEF: 35, HEALTH: 300, STR: 15, HPREGEN: 12})
	_make_unique_armor("Windrunner's Garb", 1, 50, "armor1",
		"Featherlight armour that never slows its wearer.",
		{DEF: 48, DEX: 30, CRITCHANCE: 15, HEALTH: 350})
	_make_unique_armor("Falcon Boots", 3, 45, "armor3",
		"Boots that carry an Archer as swift as a stooping falcon.",
		{DEF: 22, DEX: 22, CRITCHANCE: 12})
	_make_unique_armor("Robes of the Archmagus", 1, 55, "armor1",
		"Robes layered with centuries of protective enchantment.",
		{DEF: 38, MDEF: 60, INT: 35, MANA: 450})
	_make_unique_armor("Circlet of Insight", 0, 40, "armor0",
		"A silver circlet that sharpens every arcane thought.",
		{MDEF: 30, INT: 22, MANA: 250, MPREGEN: 15})
	_make_unique_armor("Cloak of the Nightshade", 1, 50, "armor1",
		"A living shadow worn as a cloak.",
		{DEF: 40, LUCK: 30, CRITCHANCE: 15, CRITDMG: 20})
	_make_unique_armor("Whisperstep Boots", 3, 45, "armor3",
		"Not even stone remembers the tread of these boots.",
		{DEF: 20, LUCK: 22, CRITCHANCE: 14})
	_make_unique_armor("Stoneward Greaves", 2, 55, "armor2",
		"Greaves so heavy the earth itself seems to anchor their wearer.",
		{DEF: 52, MDEF: 30, HEALTH: 440, STR: 20})
	_make_unique_armor("Trailblazer Leggings", 2, 48, "armor2",
		"Supple leggings that have crossed every frontier and worn none.",
		{DEF: 32, DEX: 26, CRITCHANCE: 13, HEALTH: 260})
	_make_unique_armor("Wovenstar Leggings", 2, 52, "armor2",
		"Leggings woven from threads of captured starlight.",
		{DEF: 26, MDEF: 42, INT: 28, MANA: 380})
	_make_unique_armor("Duskwalker Leggings", 2, 47, "armor2",
		"Leggings that fall silent the moment dusk takes the sky.",
		{DEF: 28, LUCK: 24, CRITCHANCE: 13, CRITDMG: 22})


func _make_unique_weapon(uname: String, wtype: int, speed: int, lv: int,
		icon: String, desc: String, stats: Dictionary) -> void:
	var w := WeaponData.new()
	w.name = uname
	w.item_type = Constants.ItemType.EQUIPMENT
	w.equipment_type = Constants.EquipmentType.WEAPON
	w.weapon_type = wtype
	w.weapon_attack_speed = speed
	w.item_level = lv
	w.rarity = Constants.ItemRarity.LEGENDARY
	w.description = desc
	w.icon = _get_icon(icon)
	for k in stats:
		w.bonus_stats[k] = _stat(k, stats[k])
	_save(w, UNIQUE_DIR + _fname(uname) + ".tres")
	_counts["uniques"] += 1
	_make_drop_table(w, _unique_drop_chance(lv), false)


func _make_unique_armor(uname: String, atype: int, lv: int, icon: String,
		desc: String, stats: Dictionary) -> void:
	var a := ArmorData.new()
	a.name = uname
	a.item_type = Constants.ItemType.EQUIPMENT
	a.equipment_type = Constants.EquipmentType.ARMOR
	a.armor_type = atype
	a.item_level = lv
	a.rarity = Constants.ItemRarity.LEGENDARY
	a.description = desc
	a.icon = _get_icon(icon)
	for k in stats:
		a.bonus_stats[k] = _stat(k, stats[k])
	_save(a, UNIQUE_DIR + _fname(uname) + ".tres")
	_counts["uniques"] += 1
	_make_drop_table(a, _unique_drop_chance(lv), false)


# --- Drop tables -------------------------------------------------------------
func _make_drop_table(item: ItemData, chance: float, randomize: bool,
		min_amt: int = 1, max_amt: int = 1) -> void:
	var dt := ItemDropResource.new()
	dt.item_name = item.name
	dt.drop_chance = snappedf(clampf(chance, 0.0, 1.0), 0.001)
	dt.min_amount = min_amt
	dt.max_amount = max_amt
	dt.randomize_stats = randomize
	if randomize and item is EquipmentData:
		var ps: Array[Constants.StatType] = []
		for k in (item as EquipmentData).bonus_stats.keys():
			ps.append(k)
		dt.possible_stats = ps
		dt.rarity_chances = {"COMMON": 100, "UNCOMMON": 30, "RARE": 10, "EPIC": 3, "LEGENDARY": 1}
	_save(dt, DROP_DIR + _fname(item.name) + ".tres")
	_counts["drops"] += 1


# Equipment drop chance falls off with item level: ~0.35 at lv1 -> ~0.03 at lv100.
func _equip_drop_chance(lv: int) -> float:
	return clampf(0.35 - lv * 0.0032, 0.03, 0.35)


# Uniques are rare everywhere and rarer the higher their level.
func _unique_drop_chance(lv: int) -> float:
	return clampf(0.015 - lv * 0.0001, 0.004, 0.015)


# --- Helpers -----------------------------------------------------------------
func _stat(stat_type: int, amount: int) -> StatData:
	var s := StatData.new()
	s.stat_type = stat_type
	s.base_value = 0
	s.flat_bonus_value = amount
	return s


func _get_icon(key: String) -> Texture2D:
	if not _icon_cache.has(key):
		var icon: Texture2D = null
		if ICON_SOURCES.has(key):
			var res = load(ICON_SOURCES[key])
			if res is ItemData and res.icon:
				icon = res.icon
		_icon_cache[key] = icon
	var cached: Texture2D = _icon_cache[key]
	# Duplicate so each .tres embeds its own copy rather than an external
	# reference back into the source item resource.
	return cached.duplicate() if cached else null


func _fname(item_name: String) -> String:
	return item_name.replace(" ", "_").replace("'", "")


func _save(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("Failed to save %s (error %d)" % [path, err])


func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tres") or f.ends_with(".res"):
			d.remove(f)
