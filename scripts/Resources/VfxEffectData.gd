@tool
class_name VfxEffectData
extends Resource

## One ability-VFX recipe — the data-driven form of a VfxCatalog entry. Editable
## in the Resources plugin (VFX Effects type): pick a sheet, set the frame
## geometry, speed, size, tint, and whether it loops. VfxCatalog loads every
## .tres under resources/VFX/ and slices `sheet` into an animation at runtime.
##
## Keep one .tres per effect, named <effect_key>.tres. The `effect_key` is the
## catalog key abilities reference (cast_vfx / hit_vfx and the AL ground calls).

## Catalog key abilities reference (e.g. "fire_impact"). Must be unique; the
## file is conventionally named <effect_key>.tres.
@export var effect_key: String = ""

## Organizational tag only — how the effect is used. Does not affect playback.
@export_enum("impact", "cast", "ground") var category: String = "impact"

## The sprite sheet sliced into frames.
@export var sheet: Texture2D

## Frame cell size in px. A sheet may pack multiple ROWS of `frame_height`; the
## frame count per row is derived from the sheet width / frame_width.
@export var frame_width: int = 32
@export var frame_height: int = 32

## Which row of a multi-row sheet to slice (0-based).
@export var row: int = 0

## Playback speed (frames per second).
@export var fps: float = 20.0

## Looping = persistent ground effect (lives for the zone duration); off =
## one-shot burst that frees when the animation ends.
@export var loop: bool = false

## Base sprite scale (callers may multiply by their own factor).
@export var scale: float = 1.5

## Tint applied to the sprite — recolors a shared sheet (e.g. green poison from
## the purple DarkFire sheet).
@export var modulate: Color = Color.WHITE
