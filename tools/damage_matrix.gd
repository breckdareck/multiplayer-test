extends SceneTree

## Damage matrix harness — drives the REAL stat/ability pipeline headless and
## dumps JSON for tools/damage_matrix_report.py.
##
## Per discipline x character level (1/5/10):
##   - real LevelingComponent + WeaponMasteryComponent + StatsComponent,
##     attributes spent by the bot allocator (the game's canonical build)
##   - tier-appropriate generated weapon's flat stat bonuses added on read
##   - max_range computed with combat.gd's exact formula (weapon_multiplier x
##     (primary*4 + secondary) x attack_power / 100, spellblade supplement)
##   - every ACTIVE ability's level stats at ability level 1/5/10
##   - synergy / element / duo constants read off the real scripts
##
## Run: godot --headless --path . --script res://tools/damage_matrix.gd

# Loaded at runtime (first processed frame) — a const preload would compile
# these autoload-referencing scripts before the autoloads exist.
var BotCombat: GDScript
var CombatScript: GDScript
var StaffElement: GDScript
var PairSynergy: GDScript
var EnemyStatus: GDScript
var BowMomentum: GDScript
var SwordCombo: GDScript
var LevelingScript: GDScript
var MasteryScript: GDScript
var StatsScript: GDScript


func _load_scripts() -> void:
	BotCombat = load("res://scripts/Bot/bot_combat.gd")
	LevelingScript = load("res://scripts/Components/level.gd")
	MasteryScript = load("res://scripts/Components/weapon_mastery.gd")
	StatsScript = load("res://scripts/Components/stats.gd")
	CombatScript = load("res://scripts/Components/combat.gd")
	StaffElement = load("res://scripts/Components/staff_element.gd")
	PairSynergy = load("res://scripts/Components/weapon_pair_synergy.gd")
	EnemyStatus = load("res://scripts/Gameplay/enemy_status.gd")
	BowMomentum = load("res://scripts/Components/bow_momentum.gd")
	SwordCombo = load("res://scripts/Components/sword_combo.gd")

const DISCIPLINES := {
	"Sword": Constants.ClassType.SWORD,
	"Bow": Constants.ClassType.BOW,
	"Staff": Constants.ClassType.STAFF,
	"Dagger": Constants.ClassType.DAGGER,
}
const CHAR_LEVELS := [1, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 95, 100]
const WEAPON_NOUNS := {"Sword": "Longsword", "Bow": "Warbow", "Staff": "Spellstaff", "Dagger": "Dirk"}


## Highest-item_level generated weapon of the noun that a character of `level`
## can wear (fallback: the lowest tier). Replaces the old hand-picked table so
## the matrix can sweep every 5 levels.
func _pick_weapon(noun: String, level: int) -> Resource:
	var best: Resource = null
	var best_lv: int = -1
	var lowest: Resource = null
	var lowest_lv: int = 1 << 30
	for f in DirAccess.get_files_at("res://resources/Items/Weapons/Generated"):
		if not (f.ends_with("_%s.tres" % noun)):
			continue
		var w = load("res://resources/Items/Weapons/Generated/" + f)
		if w == null:
			continue
		if w.item_level < lowest_lv:
			lowest_lv = w.item_level
			lowest = w
		if w.item_level <= level and w.item_level > best_lv:
			best_lv = w.item_level
			best = w
	return best if best != null else lowest

var _ran := false


class _PlayerStub extends Node:
	var player_id: int = -1
	var stats_component = null
	var weapon_mastery_component = null


func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	_load_scripts()
	var out := {"meta": _constants(), "builds": {}, "abilities": {}}
	for disc_name in DISCIPLINES:
		out.abilities[disc_name] = _ability_table(disc_name)
		for lvl in CHAR_LEVELS:
			var key := "%s_L%d" % [disc_name, lvl]
			out.builds[key] = _build_stats(disc_name, DISCIPLINES[disc_name], lvl)
	var f = FileAccess.open("res://docs/damage_matrix_dump.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("WROTE docs/damage_matrix_dump.json")
	quit(0)
	return true


func _ensure_offline_peer() -> void:
	var mp := get_multiplayer()
	if not (mp.multiplayer_peer is OfflineMultiplayerPeer):
		mp.multiplayer_peer = OfflineMultiplayerPeer.new()


## Mount the real component stack at `level`, bot-spend attributes, recalc,
## and return the stat totals + the exact max_range per damage stat.
func _build_stats(disc_name: String, disc: int, level: int) -> Dictionary:
	_ensure_offline_peer()
	var player := _PlayerStub.new()
	player.player_id = -1

	var leveling = LevelingScript.new()
	leveling.name = "Leveling"
	leveling._is_loading_data = true
	player.add_child(leveling)

	var wm = MasteryScript.new()
	wm.name = "WeaponMastery"
	player.add_child(wm)
	player.weapon_mastery_component = wm

	var stats = StatsScript.new()
	stats.name = "Stats"
	player.add_child(stats)
	stats.owner = player
	stats._level_component = leveling
	stats._weapon_mastery_component = wm
	stats._loading_mode = true
	player.stats_component = stats

	root.add_child(player)
	leveling.level = level
	wm.primary_discipline = disc

	BotCombat.new(null)._auto_spend_attribute_points(player)
	stats._loading_mode = false
	stats._recalculate_stats()

	# Weapon: flat bonus_stats added on read (the equipment pipeline's effect).
	var weapon = _pick_weapon(WEAPON_NOUNS[disc_name], level)
	var wfile: String = weapon.name
	var wflats := {}
	for stype in weapon.bonus_stats:
		var sd = weapon.bonus_stats[stype]
		wflats[int(stype)] = int(sd.flat_bonus_value) + int(sd.base_value)

	var totals := {}
	for stype in stats.stats:
		totals[int(stype)] = int(stats.stats[stype].total_value) + int(wflats.get(int(stype), 0))

	# combat.gd _calculate_max_range, replicated with these inputs (the
	# component itself needs the full equipment/owner graph to run live).
	var combat = CombatScript.new()
	var wmult: float = combat.weapon_multiplier
	var mastery: float = combat.mastery
	combat.free()
	var rm = root.get_node("/root/ResourceManager")
	var p_type: int = rm.get_primary_stat(disc)
	var s_type: int = rm.get_secondary_stat(disc)
	var primary: int = totals.get(p_type, 0)
	var secondary: int = totals.get(s_type, 0)
	if disc == Constants.ClassType.STAFF:
		primary += int(CombatScript.SPELLBLADE_PHYS_RATE * maxi(
			totals.get(int(Constants.StatType.STRENGTH), 0),
			totals.get(int(Constants.StatType.DEXTERITY), 0)))

	var ranges := {}
	for atk_stat in [int(Constants.StatType.WEAPONATTACK), int(Constants.StatType.MAGICATTACK)]:
		var atk: int = totals.get(atk_stat, 0)
		ranges[str(atk_stat)] = roundi(wmult * (primary * 4 + secondary) * atk / 100.0)

	player.queue_free()
	return {
		"level": level, "weapon": wfile, "weapon_flats": wflats,
		"primary_stat": p_type, "primary": primary,
		"secondary_stat": s_type, "secondary": secondary,
		"mastery_floor": mastery,
		"max_range_by_stat": ranges, "totals": totals,
	}


## Per active ability: level stats at ability level 1/5/10 (clamped to max_level).
func _ability_table(disc_name: String) -> Array:
	var rows := []
	for f in DirAccess.get_files_at("res://resources/Abilities/%s" % disc_name):
		if not f.ends_with(".tres"):
			continue
		var a = load("res://resources/Abilities/%s/%s" % [disc_name, f])
		if a == null or a.ability_type != Constants.AbilityType.ACTIVE:
			continue
		if a.upgrades == null or a.upgrades.is_empty():
			continue  # basic-attack stubs (Snap Shot)
		var levels := {}
		for al in [1, 5, 10]:
			var clamped: int = mini(al, a.max_level)
			var ls = a.get_level_stats(clamped)
			levels[str(al)] = {
				"ability_level": clamped,
				"damage_percent": ls.damage_percent,
				"cooldown": ls.cooldown_time,
				"mana": ls.mana_cost,
				"targets": ls.max_targets,
				"hits": ls.max_hits,
			}
		rows.append({
			"name": a.ability_name, "file": f, "max_level": a.max_level,
			"damage_stat": int(a.damage_stat), "levels": levels,
		})
	return rows


## Numeric/bool constants of a script, for the report's compensator math.
func _consts_of(path: String) -> Dictionary:
	var out := {}
	var cmap: Dictionary = load(path).get_script_constant_map()
	for k in cmap:
		var v = cmap[k]
		if v is int or v is float or v is bool:
			out[k] = v
	return out


func _constants() -> Dictionary:
	var stat_names := {}
	for n in Constants.StatType.keys():
		stat_names[str(int(Constants.StatType[n]))] = n
	return {
		"stat_names": stat_names,
		"script_constants": {
			"frost_patch": _consts_of("res://scripts/Abilities/AL_FrostPatch.gd"),
			"caltrops": _consts_of("res://scripts/Abilities/AL_Caltrops.gd"),
			"stormcall": _consts_of("res://scripts/Abilities/AL_Stormcall.gd"),
			"sky_volley": _consts_of("res://scripts/Abilities/AL_SkyVolley.gd"),
			"shadowmeld": _consts_of("res://scripts/Components/shadowmeld.gd"),
			"sword_combo": _consts_of("res://scripts/Components/sword_combo.gd"),
			"stats": _consts_of("res://scripts/Components/stats.gd"),
			"eviscerate": _consts_of("res://scripts/Abilities/AL_Eviscerate.gd"),
			"hemorrhage": _consts_of("res://scripts/Abilities/AL_Hemorrhage.gd"),
			"bow_momentum": _consts_of("res://scripts/Components/bow_momentum.gd"),
		},
		"element": {
			"burn_hit_pct": StaffElement.BURN_HIT_PCT,
			"burn_min_per_tick": StaffElement.BURN_MIN_PER_TICK,
			"burn_duration": StaffElement.BURN_DURATION,
			"burn_max_stacks": StaffElement.BURN_MAX_STACKS,
			"slow_pct": StaffElement.SLOW_PCT,
			"slow_duration": StaffElement.SLOW_DURATION,
			"lightning_bonus_mult": StaffElement.LIGHTNING_BONUS_MULT,
			"lightning_chain_mult": StaffElement.LIGHTNING_CHAIN_MULT,
			"lightning_chain_max_hops": StaffElement.LIGHTNING_CHAIN_MAX_HOPS,
		},
		"pair": {
			"sword_dagger_combo_mult": PairSynergy.SWORD_DAGGER_COMBO_MULT,
			"staff_sword_combo_mult": PairSynergy.STAFF_SWORD_COMBO_MULT,
			"bow_dagger_charge_mult": PairSynergy.BOW_DAGGER_CHARGE_MULT,
			"bd_charge_cap": PairSynergy.BD_CHARGE_CAP,
			"poison_per_tick_frac": PairSynergy.POISON_PER_TICK_FRAC,
			"poison_max_stacks": PairSynergy.POISON_MAX_STACKS,
			"poison_duration": PairSynergy.POISON_DURATION,
			"duo_threshold_points": PairSynergy.DUO_THRESHOLD_POINTS,
			"duo_sword_dagger_combo_mult": PairSynergy.DUO_SWORD_DAGGER_COMBO_MULT,
			"duo_bd_charge_cap": PairSynergy.DUO_BD_CHARGE_CAP,
			"duo_poison_max_stacks": PairSynergy.DUO_POISON_MAX_STACKS,
			"duo_momentum_ride_mult": PairSynergy.DUO_MOMENTUM_RIDE_MULT,
		},
		"gauges": {
			"combo_cap": SwordCombo.COMBO_CAP,
			"momentum_max_stacks": BowMomentum.MAX_STACKS,
			"momentum_damage_per_stack": BowMomentum.DAMAGE_PER_STACK,
		},
		"escalation": {
			"thermal_shock_ticks": EnemyStatus.THERMAL_SHOCK_TICKS,
			"septic_mult": EnemyStatus.SEPTIC_MULT,
			"brittle_bleed_stacks": EnemyStatus.BRITTLE_BLEED_STACKS,
		},
	}
