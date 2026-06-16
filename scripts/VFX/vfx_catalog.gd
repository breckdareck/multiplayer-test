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
## the ability's cast_vfx/hit_vfx override + a weapon fallback), so a headless
## server never scans the VFX folder — only the client/host that renders does.

## Folder scanned for VfxEffectData .tres files.
const VFX_DIR: String = "res://resources/VFX"

## Sentinel stored in ActiveBehaviorData.cast_vfx/hit_vfx to mean "explicitly NO
## effect" — distinct from "" (unset: cast = none, hit = weapon fallback). The
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
	# Coerce types defensively: a resource saved by a stale/placeholder editor
	# instance can persist null for a typed export (e.g. face_direction = null),
	# which would otherwise silently disable flipping or crash a consumer.
	var fd = r.face_direction
	var ofs = r.offset
	return {
		"texture": r.sheet,
		"fw": r.frame_width,
		"fh": r.frame_height,
		"row": r.row,
		"fps": r.fps,
		"loop": bool(r.loop) if r.loop != null else false,
		"scale": r.scale,
		"offset": ofs if ofs is Vector2 else Vector2.ZERO,
		"face_direction": fd if fd is bool else true,
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
	var cols: int = int(tex.get_width() / float(fw))
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

## Server-side. Returns the cast-VFX key for an ability — the explicit
## ActiveBehaviorData.cast_vfx you set in the editor, or "" if unset/None. There
## is no hardcoded per-ability map: casts are authored per ability.
static func resolve_cast(ability: AbilityData) -> String:
	if ability == null:
		return ""
	# .get() + String guard: a placeholder/stale resource instance in the editor
	# can return Nil for an exported property, which must NOT propagate as a key.
	var ov: String = _override_key(ability, "cast_vfx")
	if ov == NONE_KEY:
		return ""  # explicitly suppressed
	return ov  # the chosen key, or "" when unset


## Server-side. Returns the hit-VFX key for an ability: the explicit
## ActiveBehaviorData.hit_vfx you set, else a weapon/element default so an unset
## ability still sparks on hit (set hit_vfx to None to suppress it).
static func resolve_hit(ability: AbilityData) -> String:
	if ability == null:
		return ""
	var ov: String = _override_key(ability, "hit_vfx")
	if ov == NONE_KEY:
		return ""  # explicitly suppressed
	if ov != "":
		return ov
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


## Weapon/element default so an ability with no explicit hit_vfx still sparks on
## hit. Magic abilities read arcane; everything else reads a physical impact.
static func _fallback_hit(ability: AbilityData) -> String:
	if ability.damage_stat == Constants.StatType.MAGICATTACK:
		return "arcane_impact"
	return "phys_impact"


## Hit key for a BASIC attack (no ability), by the equipped weapon type — staff
## reads its active element (0 fire / 1 ice / 2 lightning, else arcane), every
## other weapon a physical impact. `weapon_type` is a Constants.WeaponType (-1 =
## unarmed). Keeps basic-swing sparks consistent with the weapon's identity.
static func resolve_basic_hit(weapon_type: int, staff_element: int = -1) -> String:
	if weapon_type == Constants.WeaponType.STAFF:
		match staff_element:
			0: return "fire_impact"
			1: return "ice_impact"
			2: return "lightning_impact"
			_: return "arcane_impact"
	return "phys_impact"

#endregion
