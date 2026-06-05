extends Node2D

## Transient, purely-cosmetic animated VFX node. Wraps one (or a tiled row of)
## AnimatedSprite2D built from a VfxCatalog recipe and self-frees when it
## finishes (one-shot bursts) or after an explicit duration (looping ground
## effects).
##
## CLIENT-SIDE. Spawned per-peer by MapManager (broadcast_vfx_everywhere /
## broadcast_ground_vfx_everywhere -> _spawn_*_visual) UNDER the visible map
## instance so it renders in the correct SubViewport — a Node2D under a /root
## autoload would draw into the camera-less root viewport and land off-screen
## (same constraint the lightning-arc / ground-zone visuals document). It never
## touches gameplay state; authoritative damage is applied server-side.

var _elapsed: float = 0.0
## > 0 for looping ground effects: free after this many seconds. <= 0 for
## one-shot bursts: free on animation_finished instead.
var _ttl: float = 0.0


## One-shot or single looping burst at this node's position. `scale_mult`
## multiplies the catalog's base scale; `rot` rotates (radians); `flip_h`
## mirrors; `duration` > 0 keeps a loop alive that long, <= 0 plays once and
## frees on finish. No-op (self-frees) if the key can't be built.
func setup(key: String, scale_mult: float = 1.0, rot: float = 0.0, flip_h: bool = false, duration: float = 0.0) -> void:
	var frames: SpriteFrames = VfxCatalog.get_frames(key)
	if frames == null:
		queue_free()
		return
	var def: Dictionary = VfxCatalog.CATALOG[key]
	_ttl = duration
	var spr := _make_sprite(frames, def, scale_mult, rot, flip_h)
	add_child(spr)
	# One-shot bursts free when the animation ends; loops rely on the _ttl
	# countdown in _process.
	if _ttl <= 0.0:
		spr.animation_finished.connect(queue_free)
	spr.play("play")


## Looping ground strip: tiles the effect across `width` px (centered on this
## node) so a wide ground zone reads as a filled band rather than one stretched
## (distorted) sprite. Tiles are phase-offset so the row doesn't pulse in
## lockstep. Lives `duration` seconds then frees.
func setup_ground_strip(key: String, width: float, duration: float) -> void:
	var frames: SpriteFrames = VfxCatalog.get_frames(key)
	if frames == null:
		queue_free()
		return
	var def: Dictionary = VfxCatalog.CATALOG[key]
	_ttl = maxf(0.1, duration)

	var base_scale: float = float(def.get("scale", 1.0))
	var fw: int = int(def.get("fw", 32))
	var tile_px: float = float(fw) * base_scale
	# At least one tile; enough to span the width with a touch of overlap.
	var count: int = maxi(1, int(ceil(width / maxf(8.0, tile_px * 0.85))))
	var frame_count: int = frames.get_frame_count("play")
	var start_x: float = -width * 0.5 + (width - (count - 1) * (width / float(maxi(1, count)))) * 0.0
	var step: float = width / float(count)
	for i in count:
		var spr := _make_sprite(frames, def, 1.0, 0.0, (i % 2) == 1)
		# Spread tiles evenly across the band, centered.
		spr.position.x = -width * 0.5 + step * (float(i) + 0.5)
		# Random-ish starting frame (per tile, deterministic-free is fine for a
		# cosmetic) so the row shimmers instead of flashing as one.
		if frame_count > 1:
			spr.frame = (i * 3) % frame_count
		add_child(spr)
		spr.play("play")


## Builds one configured AnimatedSprite2D (not yet parented).
func _make_sprite(frames: SpriteFrames, def: Dictionary, scale_mult: float, rot: float, flip_h: bool) -> AnimatedSprite2D:
	var spr := AnimatedSprite2D.new()
	spr.sprite_frames = frames
	spr.animation = "play"
	spr.scale = Vector2.ONE * float(def.get("scale", 1.0)) * scale_mult
	spr.rotation = rot
	spr.flip_h = flip_h
	spr.modulate = def.get("modulate", Color.WHITE)
	spr.z_index = 50  # draw above floor/enemies so the juice reads clearly
	return spr


func _process(delta: float) -> void:
	if _ttl <= 0.0:
		return
	_elapsed += delta
	if _elapsed >= _ttl:
		queue_free()
