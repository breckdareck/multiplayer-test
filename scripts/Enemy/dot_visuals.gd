class_name EnemyDotVisuals
extends Node2D

## Damage-over-time visual feedback on an enemy. Two layers, all asset-free:
##   - a per-tick PARTICLE burst (red blood spurt / green gas / fire sparks),
##     code-built GPUParticles2D (mirrors the level-up burst), and
##   - a green TINT on the enemy sprite while poisoned.
## NO floating per-tick icons (2026-06-10 playtest feedback): the persistent
## status row (mark_indicator's droplet / bubbles / flame / snowflake glyphs)
## owns "this enemy is bleeding/poisoned/burning" state — the old per-tick
## icons doubled it up. Particles + tint remain the tick-rhythm feedback.
## Built dynamically by EnemyBase._ready on EVERY peer (like mark_indicator) and
## driven by EnemyBase.play_dot() → a server→all-peers RPC, so every client sees it.
##
## "Refresh on tick" model: each DoT tick calls tick(); the poison tint lingers
## HOLD_SEC after the LAST tick, so an expired DoT fades out on its own with no
## explicit stop hook. Multiple DoTs on one enemy each spurt their own particles.

enum DotType { NONE, BLEED, POISON, BURN }

## Particles emit from mid-body.
const PARTICLE_POS := Vector2(0.0, -20.0)
## How long the poison tint lingers after the last tick (> the 1s tick cadence
## so a still-ticking DoT reads as continuous).
const HOLD_SEC := 1.6

const BLEED_COLOR := Color(0.72, 0.06, 0.06)
const POISON_TINT := Color(0.55, 1.0, 0.55)

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
	# Always visible — the node draws nothing itself; visibility only gates
	# the child particle emitters, which manage their own one-shot lifetimes.
	visible = true
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
	match dt:
		DotType.BLEED:
			_restart(_blood)
		DotType.POISON:
			_restart(_poison)
			_apply_poison_tint(sprite, Time.get_ticks_msec())
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


func _process(_delta: float) -> void:
	# Only the poison tint has a lifetime to manage now (the particle bursts
	# are one-shot and self-terminating).
	if _tinted and Time.get_ticks_msec() > _tint_until_ms:
		_restore_tint()
