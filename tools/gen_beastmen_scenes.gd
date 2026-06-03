# One-off: generates enemy scenes for the MiniBeastmens set by cloning the
# goblin attacker template (goblin.tscn) and repointing it at each Beastman's
# EnemyData + SpriteFrames. Text-clone (not instantiate) so no runtime state is
# baked in; each scene gets a freshly-minted uid; the enemy_data/SF ext_resources
# are rewritten PATH-ONLY (the source uid is dropped — uid resolves BEFORE path,
# so leaving Goblin's uid would load Goblin's data). The attack state's
# animation_name is switched slash_attack -> attack_1 to match the sheets.
#
#   godot --headless --path . --script res://tools/gen_beastmen_scenes.gd
extends SceneTree

const TEMPLATE := "res://scenes/NPC/goblin.tscn"
const OUT_DIR := "res://scenes/NPC/Beastmen/"

# node_name, out_file, ED path, SF path
const ENEMIES := [
	["BearWarrior", "bear_warrior", "res://resources/Enemies/BearWarrior/ED_BearWarrior.tres", "res://resources/Enemies/BearWarrior/SF_BearWarrior.tres"],
	["CatRobber", "cat_robber", "res://resources/Enemies/CatRobber/ED_CatRobber.tres", "res://resources/Enemies/CatRobber/SF_CatRobber.tres"],
	["DeerDruid", "deer_druid", "res://resources/Enemies/DeerDruid/ED_DeerDruid.tres", "res://resources/Enemies/DeerDruid/SF_DeerDruid.tres"],
	["FoxSwordsman", "fox_swordsman", "res://resources/Enemies/FoxSwordsman/ED_FoxSwordsman.tres", "res://resources/Enemies/FoxSwordsman/SF_FoxSwordsman.tres"],
	["LionKnight", "lion_knight", "res://resources/Enemies/LionKnight/ED_LionKnight.tres", "res://resources/Enemies/LionKnight/SF_LionKnight.tres"],
	["PandaWarrior", "panda_warrior", "res://resources/Enemies/PandaWarrior/ED_PandaWarrior.tres", "res://resources/Enemies/PandaWarrior/SF_PandaWarrior.tres"],
	["RabbitWizard", "rabbit_wizard", "res://resources/Enemies/RabbitWizard/ED_RabbitWizard.tres", "res://resources/Enemies/RabbitWizard/SF_RabbitWizard.tres"],
	["WolfPathfinder", "wolf_pathfinder", "res://resources/Enemies/WolfPathfinder/ED_WolfPathfinder.tres", "res://resources/Enemies/WolfPathfinder/SF_WolfPathfinder.tres"],
]

# Lines from goblin.tscn we rewrite (kept exact so a template change fails loudly).
const SCENE_UID := 'uid="uid://c0fdrl7mq5ou7"'
const ED_LINE := '[ext_resource type="Resource" uid="uid://cvctd6i3vmgiy" path="res://resources/Enemies/Goblin/ED_Goblin.tres" id="2_vbub7"]'
const SF_LINE := '[ext_resource type="SpriteFrames" uid="uid://ckcbsuhp72f5i" path="res://resources/Enemies/Goblin/SF_Goblin.tres" id="9_7f1la"]'
const ROOT_LINE := '[node name="Goblin" type="CharacterBody2D"'
const ATTACK_ANIM := 'animation_name = "slash_attack"'


func _initialize() -> void:
	var f := FileAccess.open(TEMPLATE, FileAccess.READ)
	if f == null:
		printerr("Cannot read template %s" % TEMPLATE)
		quit(1); return
	var template := f.get_as_text()
	f.close()

	# Guard: every anchor must be present, or the template drifted.
	for anchor in [SCENE_UID, ED_LINE, SF_LINE, ROOT_LINE, ATTACK_ANIM]:
		if not template.contains(anchor):
			printerr("Template anchor missing (goblin.tscn changed?):\n  %s" % anchor)
			quit(1); return

	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var made := 0
	for e in ENEMIES:
		var node_name: String = e[0]
		var out_path: String = OUT_DIR + e[1] + ".tscn"
		var ed_path: String = e[2]
		var sf_path: String = e[3]
		var new_uid := ResourceUID.id_to_text(ResourceUID.create_id())

		var txt := template
		txt = txt.replace(SCENE_UID, 'uid="%s"' % new_uid)
		txt = txt.replace(ED_LINE, '[ext_resource type="Resource" path="%s" id="2_vbub7"]' % ed_path)
		txt = txt.replace(SF_LINE, '[ext_resource type="SpriteFrames" path="%s" id="9_7f1la"]' % sf_path)
		txt = txt.replace(ROOT_LINE, '[node name="%s" type="CharacterBody2D"' % node_name)
		txt = txt.replace(ATTACK_ANIM, 'animation_name = "attack_1"')

		var out := FileAccess.open(out_path, FileAccess.WRITE)
		if out == null:
			printerr("Cannot write %s" % out_path)
			continue
		out.store_string(txt)
		out.close()
		print("  + %-16s -> %s  (%s)" % [node_name, out_path, new_uid])
		made += 1

	print("Generated %d/%d Beastmen scenes." % [made, ENEMIES.size()])
	quit(0)
