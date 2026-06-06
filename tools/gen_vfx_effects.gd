extends SceneTree

## Seeds resources/VFX/<key>.tres (VfxEffectData) from the recipe table below —
## the data-driven form of the original hardcoded VfxCatalog.CATALOG. Run once:
##   Godot.exe --headless --path . --script res://tools/gen_vfx_effects.gd
## Re-running OVERWRITES every file (the table here is the seed source of truth;
## after seeding, edit the .tres in the Resources plugin, not this script).

const OUT_DIR := "res://resources/VFX"

const EXPLOSION := "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Explosion-Sheet.png"
const FIRE := "res://assets/sprites/MiniMonsters/MiniMonsters/Fire.png"
const ICE := "res://assets/sprites/MiniElementsHeroes/IceEffect-Sheet.png"
const ICE_SPIKES := "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Ice spikes 1-Sheet.png"
const LIGHTNING := "res://assets/sprites/MiniElementsHeroes/LightningEffect-Sheet.png"
const STARFALL := "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png"
const DARKFIRE := "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png"
const WIND := "res://assets/sprites/MiniElementsHeroes/WindEffect-Sheet.png"
const EARTH := "res://assets/sprites/MiniElementsHeroes/EarthEffect-Sheet.png"

# key -> [category, path, fw, fh, row, fps, loop, scale, modulate]
const RECIPES := {
	"phys_impact":      ["impact", EXPLOSION, 48, 32, 0, 20.0, false, 1.1, Color(0.96, 0.93, 0.85, 1.0)],
	"explosion":        ["impact", EXPLOSION, 48, 32, 0, 18.0, false, 1.6, Color(1.0, 0.95, 0.85, 1.0)],
	"blood_impact":     ["impact", EXPLOSION, 48, 32, 0, 20.0, false, 1.2, Color(1.0, 0.25, 0.2, 1.0)],
	"fire_impact":      ["impact", FIRE, 32, 32, 0, 26.0, false, 1.5, Color(1.0, 1.0, 1.0, 1.0)],
	"ice_impact":       ["impact", ICE, 32, 32, 0, 20.0, false, 1.5, Color(1.0, 1.0, 1.0, 1.0)],
	"lightning_impact": ["impact", LIGHTNING, 32, 32, 0, 18.0, false, 1.6, Color(1.0, 1.0, 1.0, 1.0)],
	"arcane_impact":    ["impact", STARFALL, 32, 32, 0, 20.0, false, 1.6, Color(0.78, 0.6, 1.0, 1.0)],
	"dark_impact":      ["impact", DARKFIRE, 32, 32, 0, 16.0, false, 1.6, Color(0.8, 0.5, 1.0, 1.0)],
	"poison_impact":    ["impact", DARKFIRE, 32, 32, 0, 16.0, false, 1.4, Color(0.5, 1.0, 0.35, 1.0)],

	"buff_cast":        ["cast", STARFALL, 32, 32, 0, 16.0, false, 1.8, Color(1.0, 0.88, 0.45, 1.0)],
	"arcane_cast":      ["cast", STARFALL, 32, 32, 0, 18.0, false, 1.7, Color(0.7, 0.7, 1.0, 1.0)],
	"fire_cast":        ["cast", FIRE, 32, 32, 0, 24.0, false, 1.6, Color(1.0, 0.85, 0.6, 1.0)],
	"ice_cast":         ["cast", ICE, 32, 32, 0, 18.0, false, 1.6, Color(0.8, 0.95, 1.0, 1.0)],
	"dark_cast":        ["cast", DARKFIRE, 32, 32, 0, 16.0, false, 1.8, Color(0.55, 0.35, 0.8, 1.0)],
	"wind_cast":        ["cast", WIND, 40, 32, 0, 18.0, false, 1.6, Color(0.85, 1.0, 0.92, 1.0)],

	"fire_ground":      ["ground", FIRE, 32, 32, 0, 18.0, true, 2.4, Color(1.0, 0.95, 0.8, 0.95)],
	"ice_ground":       ["ground", ICE_SPIKES, 32, 32, 0, 10.0, true, 2.2, Color(0.85, 0.95, 1.0, 0.95)],
	"earth_ground":     ["ground", EARTH, 48, 32, 1, 12.0, true, 2.0, Color(1.0, 0.95, 0.85, 0.95)],
	"poison_ground":    ["ground", DARKFIRE, 32, 32, 0, 12.0, true, 2.4, Color(0.5, 1.0, 0.4, 0.9)],
	"smoke_ground":     ["ground", DARKFIRE, 32, 32, 0, 10.0, true, 2.6, Color(0.62, 0.62, 0.68, 0.85)],
	"holy_ground":      ["ground", STARFALL, 32, 32, 0, 12.0, true, 2.2, Color(1.0, 0.9, 0.5, 0.9)],
	"lightning_ground": ["ground", LIGHTNING, 32, 32, 0, 14.0, true, 2.2, Color(0.7, 0.75, 1.0, 0.95)],
	"dust_ground":      ["ground", EARTH, 48, 32, 0, 12.0, true, 1.9, Color(0.92, 0.85, 0.6, 0.9)],
}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var made := 0
	var fail := 0
	for key in RECIPES.keys():
		var r: Array = RECIPES[key]
		var tex: Texture2D = load(r[1])
		if tex == null:
			printerr("  [FAIL] %s : sheet failed to load (%s)" % [key, r[1]])
			fail += 1
			continue
		var d := VfxEffectData.new()
		d.effect_key = key
		d.category = r[0]
		d.sheet = tex
		d.frame_width = r[2]
		d.frame_height = r[3]
		d.row = r[4]
		d.fps = r[5]
		d.loop = r[6]
		d.scale = r[7]
		d.modulate = r[8]
		var path := "%s/%s.tres" % [OUT_DIR, key]
		var err := ResourceSaver.save(d, path)
		if err != OK:
			printerr("  [FAIL] %s : save err %d" % [key, err])
			fail += 1
			continue
		print("  [ ok ] %s -> %s" % [key, path])
		made += 1
	print("\n%s : wrote %d / %d VfxEffectData files" % ["PASS" if fail == 0 else "FAIL", made, RECIPES.size()])
	quit(1 if fail > 0 else 0)
