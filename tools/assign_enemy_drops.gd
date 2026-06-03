# Retiers every enemy's equipment drops to the gear tier matching its
# monster_level, so each enemy drops level-appropriate loot. Run AFTER
# tools/generate_item_content.gd (which defines the tier ladder + drop tables):
#
#   godot --headless --path . --script res://tools/assign_enemy_drops.gd
#
# Re-runnable and idempotent. It PRESERVES each enemy's curated family+slot
# choices (and Coin / unique / non-tier drops) — only the TIER prefix of an
# equipment drop changes to match the enemy's level. The LEVELS/TIERS ladder
# below must mirror generate_item_content.gd.
extends SceneTree

const LEVELS: Array = [1, 8, 13, 20, 27, 35, 43, 50, 60, 68, 77, 85, 93, 100]
const TIERS: Array = ["Worn", "Rough", "Bronze", "Fine", "Iron", "Steel",
	"Mithril", "Adamant", "Pristine", "Runic", "Dragonbone", "Celestial",
	"Astral", "Eternal"]

const ENEMY_DIR := "res://resources/Enemies/"
const DROP_DIR := "res://resources/DropTables/Generated/"


func _initialize() -> void:
	print("=== Enemy drop retiering ===")
	var tier_set := {}
	for t in TIERS:
		tier_set[t] = true
	var paths := _find_enemies(ENEMY_DIR)
	var changed := 0
	for path in paths:
		if _retier_enemy(path, tier_set):
			changed += 1
	print("Retiered %d / %d enemies." % [changed, paths.size()])
	quit()


# Highest tier whose item_level is <= the enemy's level (clamped to Worn).
func _tier_for_level(level: int) -> String:
	var tier: String = TIERS[0]
	for i in LEVELS.size():
		if level >= int(LEVELS[i]):
			tier = TIERS[i]
		else:
			break
	return tier


func _retier_enemy(path: String, tier_set: Dictionary) -> bool:
	var ed = load(path)
	if ed == null or not (ed is EnemyData):
		return false
	var level: int = maxi(1, ed.monster_level)
	var target_tier: String = _tier_for_level(level)

	var changed := false
	var new_drops: Array[ItemDropResource] = []
	for drop in ed.item_drops:
		if drop == null:
			continue
		var nm: String = drop.item_name
		var space: int = nm.find(" ")
		var first: String = nm.substr(0, space) if space != -1 else nm
		# Keep Coin / uniques / potions / anything not tier-prefixed untouched.
		if space == -1 or not tier_set.has(first):
			new_drops.append(drop)
			continue
		if first == target_tier:
			new_drops.append(drop)
			continue
		var rest: String = nm.substr(space + 1)
		var new_name: String = "%s %s" % [target_tier, rest]
		var new_path: String = DROP_DIR + new_name.replace(" ", "_").replace("'", "") + ".tres"
		if not ResourceLoader.exists(new_path):
			push_warning("No drop table '%s' (%s) — kept original on %s" % [new_name, new_path, path])
			new_drops.append(drop)
			continue
		var new_dt = load(new_path)
		if new_dt == null:
			new_drops.append(drop)
			continue
		new_drops.append(new_dt as ItemDropResource)
		changed = true

	if changed:
		ed.item_drops = new_drops
		var err := ResourceSaver.save(ed, path)
		if err != OK:
			printerr("Failed to save %s (err %d)" % [path, err])
			return false
		print("  %-18s L%-3d -> %s" % [ed.monster_name, level, target_tier])
	return changed


func _find_enemies(dir_path: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var entry := d.get_next()
	while entry != "":
		var full := dir_path + entry
		if d.current_is_dir() and not entry.begins_with("."):
			out.append_array(_find_enemies(full + "/"))
		elif entry.begins_with("ED_") and entry.ends_with(".tres"):
			out.append(full)
		entry = d.get_next()
	d.list_dir_end()
	return out
