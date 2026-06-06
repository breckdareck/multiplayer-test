class_name VfxCatalog
extends RefCounted

## Central catalog of ability "juice" VFX — one-shot impact/cast bursts and
## looping ground effects sliced at runtime from sprite sheets.
##
## DATA-DRIVEN: every effect is a VfxEffectData .tres under resources/VFX/, edited
## in the Resources plugin (VFX Effects type). This catalog scans that folder
## lazily on first use, builds a key -> recipe dict, and caches the SpriteFrames
## it slices so every spawn after the first is a lookup.
##
## Used by:
##   - sprite_effect.gd        — builds the AnimatedSprite2D from get_frames(key)
##   - MapManager.broadcast_vfx_everywhere / client_show_vfx — networking
##   - ability.gd (cast) + combat.gd (hit) — resolve_cast / resolve_hit pick the
##     key from an ability's identity (weapon, element, name) so EVERY ability
##     gets an effect with no per-.tres authoring; ActiveBehaviorData.cast_vfx /
##     hit_vfx can override the auto-pick per ability.
##
## Note: resolve_cast/resolve_hit do NOT touch the loaded recipes (they only read
## ABILITY_MAP + the ability's override), so a headless server never scans the
## VFX folder — only the client/host that actually renders an effect does.

## Folder scanned for VfxEffectData .tres files.
const VFX_DIR: String = "res://resources/VFX"

## Sentinel stored in ActiveBehaviorData.cast_vfx/hit_vfx to mean "explicitly NO
## effect" — distinct from "" (auto: resolve from ABILITY_MAP / fallback). The
## resolver returns "" for it, so the broadcast spawns nothing.
const NONE_KEY: String = "none"

## key -> recipe Dictionary {texture, fw, fh, row, fps, loop, scale, modulate,
## category}. Built from the .tres on first access; static so it survives for the
## life of the process.
static var _defs: Dictionary = {}
static var _loaded: bool = false

## Built SpriteFrames cache, key -> SpriteFrames.
static var _frames_cache: Dictionary = {}


## Scans VFX_DIR once, loading every VfxEffectData into the recipe dict. Idempotent.
static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var dir := DirAccess.open(VFX_DIR)
	if dir == null:
		push_warning("VfxCatalog: VFX folder not found (%s) — run tools/gen_vfx_effects.gd" % VFX_DIR)
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.get_extension() == "tres":
			var res = load("%s/%s" % [VFX_DIR, fname])
			if res is VfxEffectData and res.effect_key != "":
				_defs[res.effect_key] = _def_from_resource(res)
		fname = dir.get_next()
	dir.list_dir_end()


## Flattens a VfxEffectData into the recipe dict consumers read.
static func _def_from_resource(r: VfxEffectData) -> Dictionary:
	return {
		"texture": r.sheet,
		"fw": r.frame_width,
		"fh": r.frame_height,
		"row": r.row,
		"fps": r.fps,
		"loop": r.loop,
		"scale": r.scale,
		"modulate": r.modulate,
		"category": r.category,
	}


## All catalog keys (sorted for stable dropdown order). Triggers the lazy load.
static func all_keys() -> Array:
	_ensure_loaded()
	var keys: Array = _defs.keys()
	keys.sort()
	return keys


## Recipe dict for `key` (empty dict if unknown). Triggers the lazy load.
static func get_def(key: String) -> Dictionary:
	_ensure_loaded()
	return _defs.get(key, {})


## Returns true if `key` names a real catalog entry ("" / NONE_KEY = no effect).
static func has(key: String) -> bool:
	if key == "" or key == NONE_KEY:
		return false
	_ensure_loaded()
	return _defs.has(key)


## Builds (or returns the cached) SpriteFrames for `key`. Returns null if the key
## is unknown or its sheet is missing (a headless server never calls this — it
## only broadcasts keys).
static func get_frames(key: String) -> SpriteFrames:
	if _frames_cache.has(key):
		return _frames_cache[key]
	_ensure_loaded()
	if not _defs.has(key):
		return null
	var sf := build_frames(_defs[key])
	if sf != null:
		_frames_cache[key] = sf
	return sf


## Slices a recipe dict into an uncached SpriteFrames: `fw x fh` cells along the
## chosen row, frame count derived from the texture width so trailing geometry is
## never guessed. Public so the editor can preview a LIVE (unsaved) recipe without
## polluting the runtime cache.
static func build_frames(def: Dictionary) -> SpriteFrames:
	var tex: Texture2D = def.get("texture")
	if tex == null:
		return null
	var fw: int = int(def.get("fw", 32))
	var fh: int = int(def.get("fh", 32))
	var row: int = int(def.get("row", 0))
	if fw <= 0 or fh <= 0:
		return null
	var cols: int = int(tex.get_width() / fw)
	if cols <= 0:
		return null

	var sf := SpriteFrames.new()
	if sf.has_animation("default"):
		sf.remove_animation("default")
	sf.add_animation("play")
	sf.set_animation_speed("play", float(def.get("fps", 20.0)))
	sf.set_animation_loop("play", bool(def.get("loop", false)))
	for c in cols:
		var at := AtlasTexture.new()
		at.atlas = tex
		at.region = Rect2(c * fw, row * fh, fw, fh)
		sf.add_frame("play", at)
	return sf


## Builds an uncached SpriteFrames straight from a VfxEffectData — the editor
## preview path (reflects unsaved edits live).
static func build_frames_from_resource(r: VfxEffectData) -> SpriteFrames:
	if r == null:
		return null
	return build_frames(_def_from_resource(r))


## Drops the cached recipes + SpriteFrames so the next access reloads from disk —
## call after editing a VfxEffectData so live gameplay picks up the change.
static func invalidate() -> void:
	_loaded = false
	_defs.clear()
	_frames_cache.clear()


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
	if ov == NONE_KEY:
		return ""  # explicitly suppressed by the designer
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
	if ov == NONE_KEY:
		return ""  # explicitly suppressed by the designer
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
