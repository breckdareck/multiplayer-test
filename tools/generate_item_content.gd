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

# Gear tiers on an IRREGULAR, MapleStory-style ladder — NOT a clean every-5/10
# grid. Real equip req-levels are organic: denser early (fast leveling = frequent
# upgrades), wider and varied gaps later, never a tidy multiple. 14 tiers = 11
# material names + 3 quality interleaves (Rough/Fine/Pristine). Per-tier stats are
# smooth (def = base + item_level * slope), so irregular item_levels just produce
# irregular-but-monotone steps. tools/assign_enemy_drops.gd snaps every enemy's
# drops to the tier at-or-below its monster_level, so ANY breakpoints work — tune
# LEVELS freely. Re-run BOTH tools (generator then assigner) after editing this.
# LEVELS and TIERS must stay index-aligned and mirror assign_enemy_drops.gd.
const LEVELS: Array = [1, 8, 13, 20, 27, 35, 43, 50, 60, 68, 77, 85, 93, 100]
const TIERS: Array = ["Worn", "Rough", "Bronze", "Fine", "Iron", "Steel",
	"Mithril", "Adamant", "Pristine", "Runic", "Dragonbone", "Celestial",
	"Astral", "Eternal"]

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
const CON := 15
const ACCURACY := 16
const EVASION := 17

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
	"armor1": "res://resources/Items/Armor/Trappers_Vest.tres",
	"armor2": "res://resources/Items/Armor/Travelers_Breeches.tres",
	"armor3": "res://resources/Items/Armor/Trailworn_Sandals.tres",
	"hp": "res://resources/Items/Consumables/Grape_Potion.tres",
	"mp": "res://resources/Items/Consumables/Mana_Potion.tres",
}

const UidHeader = preload("res://tools/uid_header.gd")

var _icon_cache: Dictionary = {}
var _counts: Dictionary = {"weapons": 0, "armor": 0, "consumables": 0, "uniques": 0, "drops": 0}
# res://path -> the uid it had before this run, so re-running the generator keeps
# uids stable (consumers that reference generated content by uid don't break).
var _existing_uids: Dictionary = {}


func _initialize() -> void:
	print("=== Item content generator ===")
	for d in [WEAPON_DIR, ARMOR_DIR, CONSUMABLE_DIR, UNIQUE_DIR, DROP_DIR]:
		DirAccess.make_dir_recursive_absolute(d)
		_harvest_uids(d)
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
			w.icon = _item_icon(w.name, "Weapons/Generated", d["icon"])
			for st in d["stats"]:
				w.bonus_stats[st[0]] = _stat(st[0], maxi(1, roundi(st[1] + lv * st[2])))
			_save(w, WEAPON_DIR + _fname(w.name) + ".tres")
			_counts["weapons"] += 1
			_make_drop_table(w, _equip_drop_chance(lv), true)


# --- Armor: 4 class-themed sets x 4 slots x 11 level tiers --------------------
func _generate_armor() -> void:
	# Defensive identity (MapleStory / Spirit Vale spirit): each family favours
	# one defense type. `def` / `mdef` are [base, per_level] slopes — a STRONG
	# defense uses [3.0, 0.7] (matches the old physical DEF curve), a WEAK one
	# [2.0, 0.45], and BALANCED (light armour) [2.5, 0.55]. Magic defense is
	# bumped across the board (old MDEF was a flat 0.4 slope, now 0.45-0.7) and
	# Arcanist robes now give magic defense on par with Vanguard plate's armour,
	# so the magic-defense axis actually matters and scales.
	# COMMON spread on EVERY piece (dual-discipline support, 2026-06-08): a splash of
	# all attributes + CON + a little crit/accuracy, so a player running two weapons
	# (e.g. Staff + Dagger) is never stuck with single-stat gear. Each set then layers
	# its SIGNATURE on top (its primary attribute heavier + flavour stats incl. EVASION
	# on light armour). Duplicate stats are summed. [stat, base, per_level].
	var common := [
		[STR, 0.4, 0.09], [DEX, 0.4, 0.09], [INT, 0.4, 0.09], [LUCK, 0.4, 0.09],
		[CON, 0.5, 0.10], [CRITCHANCE, 0.3, 0.025], [CRITDMG, 0.25, 0.025], [ACCURACY, 0.3, 0.03],
	]
	var sets := [
		{"name": "Vanguard", "desc": "Heavy plate forged for front-line Swordsmen.",
		 "def": [3.0, 0.7], "mdef": [2.0, 0.45],
		 "sig": [[STR, 0.6, 0.16], [HEALTH, 8.0, 1.8], [CON, 0.5, 0.12]]},      # plate: tanky STR
		{"name": "Pathfinder", "desc": "Light, flexible armour suited to an Archer's mobility.",
		 "def": [2.5, 0.55], "mdef": [2.5, 0.55],
		 "sig": [[DEX, 0.6, 0.16], [CRITCHANCE, 0.6, 0.04], [CRITDMG, 0.4, 0.035], [EVASION, 0.5, 0.04], [ACCURACY, 0.5, 0.06]]},  # light: agile crit
		{"name": "Arcanist", "desc": "Enchanted vestments that channel a Mage's power.",
		 "def": [2.0, 0.45], "mdef": [3.0, 0.7],
		 "sig": [[INT, 0.6, 0.16], [MANA, 6.0, 1.5], [MPREGEN, 0.3, 0.06]]},     # robes: caster
		{"name": "Nightshade", "desc": "Shadowy garb tailored for a Rogue's deadly craft.",
		 "def": [2.5, 0.55], "mdef": [2.5, 0.55],
		 "sig": [[LUCK, 0.6, 0.16], [CRITDMG, 1.0, 0.08], [CRITCHANCE, 0.4, 0.03], [EVASION, 0.5, 0.04]]},  # light: evasive crit
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
				a.icon = _item_icon(a.name, "Armor/Generated", slot["icon"])
				a.bonus_stats[DEF] = _stat(DEF, maxi(1, roundi((s["def"][0] + lv * s["def"][1]) * wgt)))
				a.bonus_stats[MDEF] = _stat(MDEF, maxi(1, roundi((s["mdef"][0] + lv * s["mdef"][1]) * wgt)))
				# Accumulate COMMON + this set's SIGNATURE, summing any stat in both,
				# then write each as a flat bonus scaled by the slot weight.
				var acc := {}
				for t in common:
					acc[t[0]] = float(acc.get(t[0], 0.0)) + (t[1] + lv * t[2])
				for t in s["sig"]:
					acc[t[0]] = float(acc.get(t[0], 0.0)) + (t[1] + lv * t[2])
				for stat_id in acc:
					a.bonus_stats[stat_id] = _stat(stat_id, maxi(1, roundi(acc[stat_id] * wgt)))
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
	c.icon = _item_icon(c.name, "Consumables/Generated", icon)
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
	w.icon = _item_icon(w.name, "Unique", icon)
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
	a.icon = _item_icon(a.name, "Unique", icon)
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


# Equipment drop chance falls off with item level: ~0.035 at lv1 -> ~0.011 at lv100.
func _equip_drop_chance(lv: int) -> float:
	return clampf(0.035 - lv * 0.00024, 0.01, 0.035)


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


## Per-item icon: load the item's matching generated_px PNG by name as a PATH
## reference (which survives re-runs and serialises as an ext_resource), falling
## back to the generic source icon only if that item has no PNG yet. Replaces the
## old behaviour where every regen embedded a generic DUPLICATE texture and so
## clobbered the wired per-item sprites.
func _item_icon(item_name: String, subdir: String, fallback_key: String) -> Texture2D:
	var png := "res://assets/sprites/Items/generated_px/%s/%s.png" % [subdir, _fname(item_name)]
	if ResourceLoader.exists(png):
		var tex = load(png)
		if tex is Texture2D:
			return tex
	return _get_icon(fallback_key)


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
		return
	# ResourceSaver headless doesn't write a uid header — add one (reusing the
	# file's previous uid if it had one) so uid references stay resolvable.
	UidHeader.ensure_header_uid(path, _existing_uids.get(path, ""))


func _harvest_uids(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tres") or f.ends_with(".res"):
			var p := dir + f
			var u := UidHeader.read_header_uid(p)
			if u != "":
				_existing_uids[p] = u


func _clear_dir(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".tres") or f.ends_with(".res"):
			d.remove(f)
