class_name EnemyDotVisuals
extends Node2D

## Damage-over-time visual feedback on an enemy. Three layers, all asset-free:
##   - a custom-DRAWN floating status icon (blood drop / poison skull / flame),
##   - a per-tick PARTICLE burst (red blood spurt / green gas / fire), code-built
##     GPUParticles2D (mirrors the level-up burst), and
##   - a green TINT on the enemy sprite while poisoned.
## Built dynamically by EnemyBase._ready on EVERY peer (like mark_indicator) and
## driven by EnemyBase.play_dot() → a server→all-peers RPC, so every client sees it.
##
## "Refresh on tick" model: each DoT tick calls tick(); the icon + tint linger
## HOLD_SEC after the LAST tick, so an expired DoT fades out on its own with no
## explicit stop hook. Multiple DoTs on one enemy each spurt their own particles;
## the icon shows the most-recent type (minor flicker on overlap is acceptable v1).

enum DotType { NONE, BLEED, POISON, BURN }

## Icon floats up-and-right of the head (mark_indicator owns straight-above at -60).
const ICON_OFFSET := Vector2(5.0, -50.0)
## Particles emit from mid-body, not the floating icon.
const PARTICLE_POS := Vector2(0.0, -20.0)
## How long the icon / poison tint linger after the last tick (> the 1s tick cadence
## so a still-ticking DoT reads as continuous).
const HOLD_SEC := 1.6

const BLEED_COLOR := Color(0.72, 0.06, 0.06)
const SKULL_COLOR := Color(0.80, 0.93, 0.72)
const POISON_TINT := Color(0.55, 1.0, 0.55)
const FIRE_COLOR := Color(1.0, 0.55, 0.12)
const ICON_OUTLINE := Color(0.05, 0.05, 0.08, 0.9)

var _type: int = DotType.NONE
var _icon_until_ms: int = 0
var _t: float = 0.0

var _blood: GPUParticles2D
var _poison: GPUParticles2D
var _fire: GPUParticles2D

# Poison tint — save/restore the sprite's modulate so we don't clobber other tints.
var _tint_sprite: CanvasItem = null
var _saved_modulate: Color = Color.WHITE
var _tint_until_ms: int = 0
var _tinted: bool = false


func _ready() -> void:
	z_index = 50
	_blood = _make_emitter(_blood_material(), 12, 0.6)
	_poison = _make_emitter(_poison_material(), 10, 1.0)
	_fire = _make_emitter(_fire_material(), 14, 0.6)
	visible = false
	set_process(true)


func _make_emitter(mat: ParticleProcessMaterial, amount: int, lifetime: float) -> GPUParticles2D:
	var p := GPUParticles2D.new()
	p.position = PARTICLE_POS
	p.one_shot = true
	p.emitting = false
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.7
	p.local_coords = false  # particles stay in world space as the enemy moves
	p.process_material = mat
	add_child(p)
	return p


#region #################### Particle materials ####################

func _ramp(c0: Color, c1: Color) -> GradientTexture1D:
	var g := Gradient.new()
	g.set_color(0, c0)
	g.set_color(1, c1)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


## Blood: a downward spurt that falls under gravity.
func _blood_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, 1, 0)
	m.spread = 75.0
	m.initial_velocity_min = 35.0
	m.initial_velocity_max = 80.0
	m.gravity = Vector3(0, 240, 0)
	m.scale_min = 1.5
	m.scale_max = 3.0
	m.color = BLEED_COLOR
	m.color_ramp = _ramp(BLEED_COLOR, Color(0.35, 0.0, 0.0, 0.0))
	return m


## Poison: a slow green gas that rises and lingers.
func _poison_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	m.spread = 45.0
	m.initial_velocity_min = 8.0
	m.initial_velocity_max = 24.0
	m.gravity = Vector3(0, -18, 0)
	m.scale_min = 2.5
	m.scale_max = 4.5
	m.color = Color(0.4, 0.85, 0.2, 0.8)
	m.color_ramp = _ramp(Color(0.4, 0.85, 0.2, 0.8), Color(0.45, 0.7, 0.25, 0.0))
	return m


## Fire: bright sparks that rise and cool to ember red.
func _fire_material() -> ParticleProcessMaterial:
	var m := ParticleProcessMaterial.new()
	m.direction = Vector3(0, -1, 0)
	m.spread = 28.0
	m.initial_velocity_min = 28.0
	m.initial_velocity_max = 60.0
	m.gravity = Vector3(0, -45, 0)
	m.scale_min = 2.0
	m.scale_max = 3.5
	m.color = Color(1.0, 0.9, 0.3, 1.0)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.9, 0.3, 1.0))
	g.add_point(0.5, Color(1.0, 0.45, 0.05, 1.0))
	g.set_color(1, Color(0.5, 0.05, 0.0, 0.0))
	var t := GradientTexture1D.new()
	t.gradient = g
	m.color_ramp = t
	return m

#endregion


## Called on EVERY peer (via EnemyBase's RPC) on each DoT tick. `dot_type` is
## "bleed" / "poison" / "burn"; `sprite` is the enemy's AnimatedSprite2D (for the
## poison tint — may be null, then the tint is skipped).
func tick(dot_type: String, sprite: CanvasItem = null) -> void:
	var dt := _type_from_string(dot_type)
	if dt == DotType.NONE:
		return
	var now := Time.get_ticks_msec()
	_type = dt
	_icon_until_ms = now + int(HOLD_SEC * 1000.0)
	visible = true
	queue_redraw()
	match dt:
		DotType.BLEED:
			_restart(_blood)
		DotType.POISON:
			_restart(_poison)
			_apply_poison_tint(sprite, now)
		DotType.BURN:
			_restart(_fire)


func _type_from_string(s: String) -> int:
	match s:
		"bleed": return DotType.BLEED
		"poison": return DotType.POISON
		"burn": return DotType.BURN
	return DotType.NONE


func _restart(p: GPUParticles2D) -> void:
	if not is_instance_valid(p):
		return
	p.emitting = false
	p.restart()
	p.emitting = true


func _apply_poison_tint(sprite: CanvasItem, now: int) -> void:
	_tint_until_ms = now + int(HOLD_SEC * 1000.0)
	if sprite == null or not is_instance_valid(sprite):
		return
	if not _tinted:
		_tint_sprite = sprite
		_saved_modulate = sprite.modulate
		_tinted = true
	sprite.modulate = POISON_TINT


func _restore_tint() -> void:
	if _tinted and is_instance_valid(_tint_sprite):
		_tint_sprite.modulate = _saved_modulate
	_tinted = false
	_tint_sprite = null


func _process(delta: float) -> void:
	_t += delta
	var now := Time.get_ticks_msec()
	# Poison tint expiry is tracked separately from the icon so a bleed/burn tick
	# never strips a poison tint (or vice-versa).
	if _tinted and now > _tint_until_ms:
		_restore_tint()
	if now > _icon_until_ms:
		if visible:
			visible = false
		return
	queue_redraw()  # animate the bob + alpha pulse while shown


func _draw() -> void:
	# Bob + alpha pulse, like the mark indicator, so the icon catches the eye.
	var bob := sin(_t * 3.2) * 1.6
	var pulse := 0.8 + 0.2 * sin(_t * 4.5)
	var c := ICON_OFFSET + Vector2(0, bob)
	match _type:
		DotType.BLEED: _draw_blood_drop(c, pulse)
		DotType.POISON: _draw_skull(c, pulse)
		DotType.BURN: _draw_flame(c, pulse)


func _draw_blood_drop(c: Vector2, a: float) -> void:
	var col := Color(BLEED_COLOR.r, BLEED_COLOR.g, BLEED_COLOR.b, a)
	# Teardrop: a pointed top + a round bottom.
	var top := PackedVector2Array([c + Vector2(0, -7), c + Vector2(-3.5, 1), c + Vector2(3.5, 1)])
	draw_colored_polygon(top, col)
	draw_circle(c + Vector2(0, 2.5), 4.2, col)
	draw_arc(c + Vector2(0, 2.5), 4.2, 0, TAU, 16, ICON_OUTLINE, 1.0)


func _draw_skull(c: Vector2, a: float) -> void:
	var pale := Color(SKULL_COLOR.r, SKULL_COLOR.g, SKULL_COLOR.b, a)
	var dark := Color(0.08, 0.14, 0.08, a)
	draw_circle(c, 5.5, pale)                                  # cranium
	draw_rect(Rect2(c + Vector2(-2.5, 3.5), Vector2(5, 3)), pale)  # jaw
	draw_circle(c + Vector2(-2.0, -0.5), 1.5, dark)            # left eye
	draw_circle(c + Vector2(2.0, -0.5), 1.5, dark)             # right eye
	draw_line(c + Vector2(0, 1.5), c + Vector2(0, 3.0), dark, 1.0)  # nose
	# teeth
	draw_line(c + Vector2(-1.2, 3.6), c + Vector2(-1.2, 6.2), dark, 1.0)
	draw_line(c + Vector2(1.2, 3.6), c + Vector2(1.2, 6.2), dark, 1.0)


func _draw_flame(c: Vector2, a: float) -> void:
	var outer := Color(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b, a)
	var inner := Color(1.0, 0.9, 0.35, a)
	var body := PackedVector2Array([
		c + Vector2(0, -8), c + Vector2(4, -1.5), c + Vector2(3, 5),
		c + Vector2(0, 6.5), c + Vector2(-3, 5), c + Vector2(-4, -1.5),
	])
	draw_colored_polygon(body, outer)
	var core := PackedVector2Array([
		c + Vector2(0, -2.5), c + Vector2(2, 2), c + Vector2(0, 5), c + Vector2(-2, 2),
	])
	draw_colored_polygon(core, inner)
