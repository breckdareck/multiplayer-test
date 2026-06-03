extends SceneTree

# Headless dumper for the Ability Reference report.
#
# Loads every weapon-discipline AbilityData .tres, evaluates its scaling
# formulas through the GAME'S OWN code (AbilityScalingData.generate_level_data /
# AbilityScalingFormula.calculate), reads every attached AbilityUpgradeData, and
# writes the whole roster to docs/ability_data_dump.json. The numbers are
# therefore exactly what the game produces — no Python re-implementation drift.
#
# Run:
#   "C:\Program Files\Godot\Godot.exe" --headless --path . \
#       --script res://tools/dump_ability_data.gd --log-file tools/dump.log
# Then render the HTML:
#   python tools/gen_ability_reference.py

const WEAPONS := ["Sword", "Bow", "Staff", "Dagger"]
const OUT_PATH := "res://docs/ability_data_dump.json"

const STAT_NAMES := {
	0: "STR", 1: "INT", 2: "DEX", 3: "LUCK", 4: "HEALTH", 5: "MANA",
	6: "HPREGEN", 7: "MPREGEN", 8: "DEFENSE", 9: "MAGICDEFENSE",
	10: "CRITCHANCE", 11: "CRITDAMAGE", 12: "WEAPONATTACK", 13: "MAGICATTACK",
	14: "KNOCKBACKRESIST", 15: "CON", 16: "ACCURACY", 17: "EVASIONCHANCE",
}


func _initialize() -> void:
	var roster := {}
	var total_abilities := 0
	var total_upgrades := 0

	for weapon in WEAPONS:
		var dir_path := "res://resources/Abilities/%s" % weapon
		var abilities := []
		var dir := DirAccess.open(dir_path)
		if dir == null:
			push_error("Cannot open %s" % dir_path)
			continue
		var files := dir.get_files()
		files.sort()
		for fname in files:
			if not fname.ends_with(".tres"):
				continue
			var path := "%s/%s" % [dir_path, fname]
			var res = load(path)
			if res == null or not (res is AbilityData):
				continue
			var entry := _dump_ability(res, path, weapon)
			abilities.append(entry)
			total_abilities += 1
			total_upgrades += entry["upgrades"].size()
		roster[weapon] = abilities

	var payload := {
		"generated_note": "Auto-dumped from .tres via dump_ability_data.gd. Numbers come from the live game formulas.",
		"weapons": WEAPONS,
		"total_abilities": total_abilities,
		"total_upgrades": total_upgrades,
		"roster": roster,
	}

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Cannot write %s" % OUT_PATH)
		quit(1)
		return
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	print("Dumped %d abilities + %d upgrades -> %s" % [total_abilities, total_upgrades, OUT_PATH])
	quit(0)


func _dump_ability(ab: AbilityData, path: String, weapon: String) -> Dictionary:
	var sd: AbilityScalingData = ab.scaling_data
	var is_passive := ab.ability_type == Constants.AbilityType.PASSIVE
	var is_magic := ab.damage_stat == Constants.StatType.MAGICATTACK

	# Which scaling fields are actually authored (so the report only shows
	# columns that mean something for this ability).
	var present := {
		"mana": sd != null and sd.mana_cost_formula != null,
		"cooldown": sd != null and sd.cooldown_formula != null,
		"damage": sd != null and sd.damage_percent_formula != null,
		"targets": sd != null and sd.max_targets_formula != null,
		"hits": sd != null and sd.max_hits_formula != null,
		"cast": sd != null and sd.cast_time_formula != null,
		"status_chance": sd != null and sd.status_effect_chance_formula != null,
		"status_duration": sd != null and sd.status_effect_duration_formula != null,
		"range": sd != null and sd.range_multiplier_formula != null,
		"knockback": sd != null and sd.knockback_force_formula != null,
	}

	var custom_keys := []
	if sd != null:
		for k in sd.custom_value_formulas.keys():
			custom_keys.append(str(k))
		custom_keys.sort()

	var stat_bonus_types := []
	if sd != null:
		for sbf in sd.stat_bonus_formulas:
			if sbf != null:
				stat_bonus_types.append(STAT_NAMES.get(int(sbf.stat_type), str(sbf.stat_type)))

	var max_level: int = max(1, ab.max_level)
	var levels := []
	for lvl in range(1, max_level + 1):
		var row := {"level": lvl}
		if sd != null:
			if present["mana"]:
				row["mana"] = int(sd.mana_cost_formula.calculate(lvl))
			if present["cooldown"]:
				row["cooldown"] = snappedf(sd.cooldown_formula.calculate(lvl), 0.01)
			if present["damage"]:
				row["damage"] = int(sd.damage_percent_formula.calculate(lvl))
			if present["targets"]:
				row["targets"] = int(sd.max_targets_formula.calculate(lvl))
			if present["hits"]:
				row["hits"] = int(sd.max_hits_formula.calculate(lvl))
			if present["cast"]:
				row["cast"] = snappedf(sd.cast_time_formula.calculate(lvl), 0.01)
			if present["status_chance"]:
				row["status_chance"] = snappedf(sd.status_effect_chance_formula.calculate(lvl), 0.1)
			if present["status_duration"]:
				row["status_duration"] = snappedf(sd.status_effect_duration_formula.calculate(lvl), 0.1)
			if present["range"]:
				row["range"] = snappedf(sd.range_multiplier_formula.calculate(lvl), 0.01)
			if present["knockback"]:
				row["knockback"] = snappedf(sd.knockback_force_formula.calculate(lvl), 0.1)

			# Named custom display values (Bulwark Defense, Banner regen, etc.)
			if not custom_keys.is_empty():
				var customs := {}
				for k in custom_keys:
					var ff: AbilityScalingFormula = sd.custom_value_formulas.get(k)
					if ff != null:
						customs[k] = snappedf(ff.calculate(lvl), 0.1)
				row["custom"] = customs

			# Passive stat bonuses (flat + percent)
			if not sd.stat_bonus_formulas.is_empty():
				var bonuses := []
				for sbf in sd.stat_bonus_formulas:
					if sbf == null:
						continue
					var flat := 0.0
					var pct := 0.0
					if sbf.flat_bonus_formula != null:
						flat = sbf.flat_bonus_formula.calculate(lvl)
					if sbf.percent_bonus_formula != null:
						pct = sbf.percent_bonus_formula.calculate(lvl)
					bonuses.append({
						"stat": STAT_NAMES.get(int(sbf.stat_type), str(sbf.stat_type)),
						"flat": snappedf(flat, 0.1),
						"percent": snappedf(pct, 0.1),
					})
				row["stat_bonuses"] = bonuses

			# Buff / debuff durations per level
			if ab.applies_buff != null and ab.buff_duration_formula != null:
				row["buff_duration"] = snappedf(ab.buff_duration_formula.calculate(lvl), 0.1)
			if ab.applies_target_debuff != null and ab.debuff_duration_formula != null:
				row["debuff_duration"] = snappedf(ab.debuff_duration_formula.calculate(lvl), 0.1)
		levels.append(row)

	# Proc info (static-ish)
	var proc := {}
	if sd != null and not sd.proc_event_type.is_empty():
		proc["event"] = sd.proc_event_type
		if sd.proc_chance_formula != null:
			proc["chance_l1"] = snappedf(sd.proc_chance_formula.calculate(1), 0.1)
			proc["chance_max"] = snappedf(sd.proc_chance_formula.calculate(max_level), 0.1)
		if sd.proc_damage_formula != null:
			proc["damage_l1"] = int(sd.proc_damage_formula.calculate(1))
			proc["damage_max"] = int(sd.proc_damage_formula.calculate(max_level))

	# Logic script backing the ability
	var al_script := ""
	if ab.active_behavior != null and ab.active_behavior.logic_script != null:
		al_script = ab.active_behavior.logic_script.resource_path.get_file()
	var target_type := -1
	if ab.active_behavior != null:
		target_type = int(ab.active_behavior.target_type)

	# Upgrades, sorted by tier then name
	var upgrades := []
	for up in ab.upgrades:
		if up == null:
			continue
		upgrades.append({
			"id": up.upgrade_id,
			"name": up.upgrade_name,
			"description": up.description,
			"point_cost": up.point_cost,
			"tier": up.tier,
			"variant_group": up.variant_group,
			"effect_key": up.effect_key,
			"magnitude": snappedf(up.magnitude, 0.01),
		})
	upgrades.sort_custom(func(a, b):
		if a["tier"] != b["tier"]:
			return a["tier"] < b["tier"]
		return a["name"] < b["name"])

	var buff_name := ""
	if ab.applies_buff != null:
		buff_name = ab.applies_buff.resource_path.get_file()
	var debuff_name := ""
	if ab.applies_target_debuff != null:
		debuff_name = ab.applies_target_debuff.resource_path.get_file()

	return {
		"id": ab.ability_id,
		"name": ab.ability_name,
		"weapon": weapon,
		"type": "Passive" if is_passive else "Active",
		"damage_stat": "MAGICATTACK" if is_magic else "WEAPONATTACK",
		"max_level": max_level,
		"description": ab.description,
		"tree_path": ab.tree_path,
		"tree_depth": ab.tree_depth,
		"al_script": al_script,
		"target_type": target_type,
		"file": path.get_file(),
		"present": present,
		"custom_keys": custom_keys,
		"stat_bonus_types": stat_bonus_types,
		"applies_buff": buff_name,
		"applies_debuff": debuff_name,
		"proc": proc,
		"levels": levels,
		"upgrades": upgrades,
	}
