class_name VfxCatalog
extends RefCounted

## Central catalog of ability "juice" VFX — one-shot impact/cast bursts and
## looping ground effects sliced at runtime from the Mini-collection effect
## sprite sheets (assets/sprites/Mini*). Each CATALOG entry is a recipe; the
## SpriteFrames are built lazily on first use and cached so every spawn after
## the first is a dictionary lookup.
##
## Used by:
##   - sprite_effect.gd        — builds the AnimatedSprite2D from get_frames(key)
##   - MapManager.broadcast_vfx_everywhere / client_show_vfx — networking
##   - ability.gd (cast) + combat.gd (hit) — resolve_cast / resolve_hit pick the
##     key from an ability's identity (weapon, element, name) so EVERY ability
##     gets an effect with no per-.tres authoring; ActiveBehaviorData.cast_vfx /
##     hit_vfx can override the auto-pick per ability.
##
## Geometry was verified against the actual sheets with
## tools/gen_enemy_spriteframes.gd (report mode) — frame width/height and the
## chosen row are exact, never assumed.

## key -> recipe. Fields:
##   path     : res:// sheet path
##   fw, fh   : frame width/height in px (a sheet may pack 2 rows of fh=32)
##   row      : which row to slice (0-based; multi-row sheets stack animations)
##   fps      : playback speed
##   loop     : true for persistent ground effects, false for one-shot bursts
##   scale    : base sprite scale (callers multiply by their own scale_mult)
##   modulate : tint applied to recolor a shared sheet (e.g. green poison from
##              the purple DarkFire sheet)
const CATALOG: Dictionary = {
	# ---- One-shot impacts (spawned at the struck enemy) ----
	"phys_impact": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Explosion-Sheet.png",
		"fw": 48, "fh": 32, "row": 0, "fps": 20.0, "loop": false, "scale": 1.1,
		"modulate": Color(0.96, 0.93, 0.85, 1.0),
	},
	"explosion": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Explosion-Sheet.png",
		"fw": 48, "fh": 32, "row": 0, "fps": 18.0, "loop": false, "scale": 1.6,
		"modulate": Color(1.0, 0.95, 0.85, 1.0),
	},
	"blood_impact": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Explosion-Sheet.png",
		"fw": 48, "fh": 32, "row": 0, "fps": 20.0, "loop": false, "scale": 1.2,
		"modulate": Color(1.0, 0.25, 0.2, 1.0),
	},
	"fire_impact": {
		"path": "res://assets/sprites/MiniMonsters/MiniMonsters/Fire.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 26.0, "loop": false, "scale": 1.5,
		"modulate": Color(1.0, 1.0, 1.0, 1.0),
	},
	"ice_impact": {
		"path": "res://assets/sprites/MiniElementsHeroes/IceEffect-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 20.0, "loop": false, "scale": 1.5,
		"modulate": Color(1.0, 1.0, 1.0, 1.0),
	},
	"lightning_impact": {
		"path": "res://assets/sprites/MiniElementsHeroes/LightningEffect-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 18.0, "loop": false, "scale": 1.6,
		"modulate": Color(1.0, 1.0, 1.0, 1.0),
	},
	"arcane_impact": {
		"path": "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 20.0, "loop": false, "scale": 1.6,
		"modulate": Color(0.78, 0.6, 1.0, 1.0),
	},
	"dark_impact": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 16.0, "loop": false, "scale": 1.6,
		"modulate": Color(0.8, 0.5, 1.0, 1.0),
	},
	"poison_impact": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 16.0, "loop": false, "scale": 1.4,
		"modulate": Color(0.5, 1.0, 0.35, 1.0),
	},

	# ---- One-shot casts (spawned at the caster's feet/body) ----
	"buff_cast": {
		"path": "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 16.0, "loop": false, "scale": 1.8,
		"modulate": Color(1.0, 0.88, 0.45, 1.0),
	},
	"arcane_cast": {
		"path": "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 18.0, "loop": false, "scale": 1.7,
		"modulate": Color(0.7, 0.7, 1.0, 1.0),
	},
	"fire_cast": {
		"path": "res://assets/sprites/MiniMonsters/MiniMonsters/Fire.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 24.0, "loop": false, "scale": 1.6,
		"modulate": Color(1.0, 0.85, 0.6, 1.0),
	},
	"ice_cast": {
		"path": "res://assets/sprites/MiniElementsHeroes/IceEffect-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 18.0, "loop": false, "scale": 1.6,
		"modulate": Color(0.8, 0.95, 1.0, 1.0),
	},
	"dark_cast": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 16.0, "loop": false, "scale": 1.8,
		"modulate": Color(0.55, 0.35, 0.8, 1.0),
	},
	"wind_cast": {
		"path": "res://assets/sprites/MiniElementsHeroes/WindEffect-Sheet.png",
		"fw": 40, "fh": 32, "row": 0, "fps": 18.0, "loop": false, "scale": 1.6,
		"modulate": Color(0.85, 1.0, 0.92, 1.0),
	},

	# ---- Looping ground effects (live for the GroundZone's duration) ----
	"fire_ground": {
		"path": "res://assets/sprites/MiniMonsters/MiniMonsters/Fire.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 18.0, "loop": true, "scale": 2.4,
		"modulate": Color(1.0, 0.95, 0.8, 0.95),
	},
	"ice_ground": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/Ice spikes 1-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 10.0, "loop": true, "scale": 2.2,
		"modulate": Color(0.85, 0.95, 1.0, 0.95),
	},
	"earth_ground": {
		"path": "res://assets/sprites/MiniElementsHeroes/EarthEffect-Sheet.png",
		"fw": 48, "fh": 32, "row": 1, "fps": 12.0, "loop": true, "scale": 2.0,
		"modulate": Color(1.0, 0.95, 0.85, 0.95),
	},
	"poison_ground": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 12.0, "loop": true, "scale": 2.4,
		"modulate": Color(0.5, 1.0, 0.4, 0.9),
	},
	"smoke_ground": {
		"path": "res://assets/sprites/MiniBigMonsters/MiniBigMonsters/DarkFire-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 10.0, "loop": true, "scale": 2.6,
		"modulate": Color(0.62, 0.62, 0.68, 0.85),
	},
	"holy_ground": {
		"path": "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 12.0, "loop": true, "scale": 2.2,
		"modulate": Color(1.0, 0.9, 0.5, 0.9),
	},
	"lightning_ground": {
		"path": "res://assets/sprites/MiniElementsHeroes/LightningEffect-Sheet.png",
		"fw": 32, "fh": 32, "row": 0, "fps": 14.0, "loop": true, "scale": 2.2,
		"modulate": Color(0.7, 0.75, 1.0, 0.95),
	},
	"dust_ground": {
		"path": "res://assets/sprites/MiniElementsHeroes/EarthEffect-Sheet.png",
		"fw": 48, "fh": 32, "row": 0, "fps": 12.0, "loop": true, "scale": 1.9,
		"modulate": Color(0.92, 0.85, 0.6, 0.9),
	},
}

## Built SpriteFrames cache, key -> SpriteFrames. Static so it survives across
## every spawn for the life of the process (these recipes never change).
static var _frames_cache: Dictionary = {}


## Returns true if `key` names a real catalog entry (empty string = "no effect").
static func has(key: String) -> bool:
	return key != "" and CATALOG.has(key)


## Builds (or returns the cached) SpriteFrames for `key`. The sheet is sliced
## into `fw x fh` cells along the chosen row; frame count is derived from the
## texture width so trailing geometry is never guessed. Returns null if the key
## is unknown or the texture fails to load (a headless server never calls this —
## it only broadcasts keys).
static func get_frames(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	if not CATALOG.has(key):
		return null
	var def: Dictionary = CATALOG[key]
	var tex: Texture2D = load(def["path"])
	if tex == null:
		push_warning("VfxCatalog: could not load sheet for '%s' (%s)" % [key, def["path"]])
		return null

	var fw: int = int(def["fw"])
	var fh: int = int(def["fh"])
	var row: int = int(def.get("row", 0))
	var cols: int = int(tex.get_width() / fw)
	if cols <= 0:
		return null

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation("play")
	sf.set_animation_speed("play", float(def["fps"]))
	sf.set_animation_loop("play", bool(def["loop"]))
	for c in cols:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(c * fw, row * fh, fw, fh)
		sf.add_frame("play", at)

	_frames_cache[key] = sf
	return sf


#region #################### Per-ability auto-resolution ####################

## Authored cast/hit effect map, keyed by AbilityData.ability_name. Each value
## is {cast, hit} (omit a field for "none"). This is the deliberate, per-ability
## layer; anything not listed falls through to _fallback_* below using the
## ability's weapon + damage stat. Designers can still override either side per
## ability via ActiveBehaviorData.cast_vfx / hit_vfx.
const ABILITY_MAP: Dictionary = {
	# ---------------- Sword (physical) ----------------
	"FMA": {"hit": "phys_impact"},
	"Crescent Cleave": {"hit": "phys_impact"},
	"Steel Flurry": {"hit": "phys_impact"},
	"Sundering Blow": {"hit": "phys_impact"},
	"Vanguard's Onslaught": {"hit": "phys_impact"},
	"Sentinel's Mark": {"hit": "phys_impact"},
	"Hemorrhage": {"hit": "blood_impact"},
	"Earthsplitter": {"hit": "explosion"},
	"Vault Strike": {"cast": "wind_cast", "hit": "explosion"},
	"Charge!": {"cast": "wind_cast", "hit": "phys_impact"},
	"Iron Riposte": {"cast": "buff_cast"},
	"Vow of the Vanguard": {"cast": "buff_cast"},
	"Bulwark Stance": {"cast": "buff_cast"},
	"Banner of the Vanguard": {"cast": "buff_cast"},

	# ---------------- Bow (physical / wind / ice) ----------------
	"Snipe": {"hit": "explosion"},
	"Snap Shot": {"hit": "phys_impact"},
	"Split Shot": {"hit": "phys_impact"},
	"Skyfall": {"hit": "phys_impact"},
	"Sky Volley": {"hit": "phys_impact"},
	"Sundering Arrow": {"hit": "phys_impact"},
	"Barbed Shot": {"hit": "blood_impact"},
	"Hailstorm": {"hit": "ice_impact"},
	"Mark of the Hunt": {"hit": "dark_impact"},
	"Caltrops": {},
	"Disengage": {"cast": "wind_cast"},
	"Eagle Eye": {"cast": "buff_cast"},

	# ---------------- Dagger (physical / poison / shadow) ----------------
	"Twin Fang": {"hit": "phys_impact"},
	"Killing Edge": {"hit": "phys_impact"},
	"Cripple": {"hit": "phys_impact"},
	"Fan of Knives": {"hit": "phys_impact"},
	"Eviscerate": {"hit": "blood_impact"},
	"Backstab": {"hit": "dark_impact"},
	"Vendetta": {"hit": "dark_impact"},
	"Death Mark": {"hit": "dark_impact"},
	"Envenom": {"hit": "poison_impact"},
	"Shadowstep": {"cast": "dark_cast"},
	"Shadow Partner": {"cast": "dark_cast"},
	"Smoke Bomb": {"cast": "dark_cast"},

	# ---------------- Staff (elemental / arcane) ----------------
	"Arcane Bolt": {"cast": "arcane_cast", "hit": "arcane_impact"},
	"Arcane Lance": {"cast": "arcane_cast", "hit": "arcane_impact"},
	"Glacial Spike": {"cast": "ice_cast", "hit": "ice_impact"},
	"Immolate": {"cast": "fire_cast", "hit": "fire_impact"},
	"Pyre Burst": {"cast": "fire_cast", "hit": "explosion"},
	"Stormcall": {"cast": "arcane_cast", "hit": "lightning_impact"},
	"Frost Patch": {"cast": "ice_cast"},
	"Communion": {"cast": "buff_cast"},
	"Aether Ward": {"cast": "arcane_cast"},
	"Mana Surge": {"cast": "arcane_cast"},
	"Phase Step": {"cast": "arcane_cast"},
	"Spellweave": {"cast": "arcane_cast"},
	"Arcane Familiar": {"cast": "arcane_cast"},
}


## Server-side. Returns the cast-VFX key for an ability (or "" for none).
## Priority: explicit ActiveBehaviorData.cast_vfx -> authored ABILITY_MAP ->
## weapon/element fallback.
static func resolve_cast(ability: AbilityData) -> String:
	if ability == null:
		return ""
	# .get() + String guard: a placeholder/stale resource instance in the editor
	# can return Nil for an exported property, which must NOT propagate as a key.
	var ov: String = _override_key(ability, "cast_vfx")
	if ov != "":
		return ov
	var entry: Dictionary = ABILITY_MAP.get(ability.ability_name, {})
	if entry.has("cast"):
		return entry["cast"]
	return ""  # most physical actives carry their juice in the HIT, not the cast


## Server-side. Returns the hit-VFX key for an ability (or "" for none).
## Priority: explicit ActiveBehaviorData.hit_vfx -> authored ABILITY_MAP ->
## weapon/element fallback.
static func resolve_hit(ability: AbilityData) -> String:
	if ability == null:
		return ""
	var ov: String = _override_key(ability, "hit_vfx")
	if ov != "":
		return ov
	var entry: Dictionary = ABILITY_MAP.get(ability.ability_name, {})
	if entry.has("hit"):
		return entry["hit"]
	return _fallback_hit(ability)


## Reads an ActiveBehaviorData override property as a String, null-safe. Uses
## .get() so a missing property yields null rather than erroring, and coerces any
## non-String (null included) to "" so callers always receive a real key.
static func _override_key(ability: AbilityData, prop: String) -> String:
	var ab = ability.active_behavior
	if ab == null:
		return ""
	var v = ab.get(prop)
	return v if v is String else ""


## Weapon/element default so an ability NOT in ABILITY_MAP still gets a sensible
## impact. Magic abilities read arcane; everything else reads a physical impact.
static func _fallback_hit(ability: AbilityData) -> String:
	if ability.damage_stat == Constants.StatType.MAGICATTACK:
		return "arcane_impact"
	return "phys_impact"

#endregion
