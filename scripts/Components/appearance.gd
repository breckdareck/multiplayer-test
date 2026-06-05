class_name AppearanceComponent
extends Node

## Owns ALL sprite/appearance application for a player or bot character — the one
## place that turns "what discipline + level am I" into AnimatedSprite2D frames.
##
## Why this exists (candidate-3 deepening): appearance was the one character
## concern with no Component, so the weapon overhaul spread sprite-application
## across the player root in THREE near-identical sites (level-up / class refresh,
## bot appearance, weapon-swap sprite) plus an in-code swap-transition FX builder,
## with MapManager and discipline-change reaching into a private method. This
## component consolidates the single apply path, the swap transition FX, and the
## sprite-state RPCs behind one interface. It asks the player root (and through it
## WeaponMasteryComponent) for the wielded discipline — it never re-derives it.
##
## Server-authoritative: the server decides the discipline+level and broadcasts
## via change_sprite_rpc (authority); clients apply. Bots (no client at a stable
## node path mid-transition) get their appearance routed through MapManager.
## `owner` is the player root (MultiplayerPlayerV2).

#region #################### Swap-transition FX constants ####################

## Total swap-transition window. The player root passes its own swap duration to
## play_swap_transition(); these frame constants describe the flash sheet and at
## which frame the sprite actually swaps (the visual peak).
const SWAP_FX_PATH: String = "res://assets/sprites/MiniDarkElves/MiniDarkElves/Starfall-Sheet.png"
const SWAP_FX_FRAME_COUNT: int = 11
const SWAP_FX_FRAME_SIZE: int = 32
## Frame at which the sprite swap happens (visual peak of the flash).
const SWAP_FX_SPRITE_SWAP_FRAME: int = 3

#endregion


#region #################### Core apply ####################

## The single sprite-application path: resolve the SpriteFrames for a discipline +
## level and apply them to the owner's AnimatedSprite2D. Every other entry point
## funnels through here. Safe on any peer.
func apply_frames(discipline: int, level: int) -> void:
	if not is_instance_valid(owner):
		return
	var sprite: AnimatedSprite2D = owner.animated_sprite
	if not is_instance_valid(sprite):
		return
	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(discipline, level)
	if sprite_frames:
		sprite.sprite_frames = sprite_frames
		sprite.play("idle")
	else:
		push_warning("Could not find sprite for discipline %d level %d" % [discipline, level])


## [SERVER] Refresh the sprite to match the currently-wielded discipline + level.
## Broadcasts to clients via change_sprite_rpc for a real player, or routes
## through MapManager for a bot (whose node may be missing on a client
## mid-transition). Was multiplayer_controller_v2._handle_sprite_change_on_server.
func refresh_on_server() -> void:
	if not is_instance_valid(owner):
		return
	var level_comp = owner.level_component
	if not is_instance_valid(level_comp):
		return

	# Use the currently-wielded discipline (not the starting class) so a Swordsman
	# who's swapped to a bow stays an Archer sprite on level-up.
	var discipline: int = owner.get_active_discipline()
	var current_level: int = level_comp.level

	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(discipline, current_level)
	if sprite_frames:
		if BotManager.is_bot(owner.player_id):
			# A bot's node may be missing on a client mid map-transition, so route
			# its sprite updates through MapManager (an autoload).
			MapManager.broadcast_player_appearance(owner.player_id)
		else:
			# Pass the enum-key string so change_sprite_rpc resolves the same way
			# on every peer via ResourceManager.get_class_type_from_string.
			var key: String = Constants.ClassType.find_key(discipline)
			# Apply on the host (server) directly...
			change_sprite_rpc(key, current_level)
			# ...and send the node-addressed RPC ONLY to real peers on THIS player's
			# map. A blanket .rpc() also hits peers who don't have this node (off-map
			# or mid map-transition), spamming "node not found" RPC errors — the same
			# hazard the bot branch above avoids by routing through MapManager.
			var map_id: String = MapManager.get_player_map(owner.player_id)
			if not map_id.is_empty():
				MapManager.broadcast_to_map(map_id, func(pid: int): change_sprite_rpc.rpc_id(pid, key, current_level), true, true)


## [CLIENT] Applies sprite frames for the given class/level and records the
## primary discipline. Used for BOTS, whose appearance is delivered via MapManager
## rather than the node-addressed change_sprite_rpc (a bot's node may be missing
## on a client mid-transition). Called by MapManager (and the player root's
## forwarder). Was multiplayer_controller_v2.apply_appearance.
func apply_appearance(class_type: int, level: int) -> void:
	if not is_instance_valid(owner):
		return
	var wm = owner.weapon_mastery_component
	if is_instance_valid(wm):
		wm.primary_discipline = class_type as Constants.ClassType
	apply_frames(class_type, level)


## Resolves the ACTIVE weapon's discipline and applies its tier-appropriate
## sprite. Runs on the same peers that see the swap FX. Falls back to the primary
## discipline when the active slot is empty (bare hands) so the sprite stays
## sensible. Was multiplayer_controller_v2._apply_active_weapon_sprite.
func apply_active_weapon_sprite() -> void:
	if not is_instance_valid(owner) or owner._is_being_cleaned_up:
		return
	# Only the LOCAL player resolves its sprite from its own equipment. A remote
	# player's equipment items are synced only to their owner, so resolving here
	# for someone else's body falls back to their primary discipline (always
	# "sword") and — running on the swap-FX timer — overwrites the authoritative
	# change_sprite_rpc the server broadcast. Remote bodies get their sprite from
	# refresh_on_server's broadcast exclusively. (Multiplayer weapon-swap sprite fix.)
	if multiplayer.has_multiplayer_peer() and multiplayer.get_unique_id() != owner.player_id:
		return
	var equip = owner.equipment_component
	var level_comp = owner.level_component
	if not is_instance_valid(equip) or not is_instance_valid(level_comp):
		return

	var weapon: WeaponData = equip.active_weapon_data
	var discipline_class: int = -1
	if weapon != null:
		discipline_class = WeaponMasteryComponent.weapon_type_to_discipline(weapon.weapon_type)
	if discipline_class == -1:
		var wm = owner.weapon_mastery_component
		if is_instance_valid(wm):
			discipline_class = wm.primary_discipline

	if discipline_class == -1:
		return

	apply_frames(discipline_class, level_comp.level)

#endregion


#region #################### Swap transition ####################

## Plays the weapon-swap transition: spawns the flash FX on every peer that has
## this player node, then swaps the sprite at the FX's visual peak. `duration` is
## the player root's swap-transition window (it also drives the input lock there).
## The FX-render + sprite-swap timing is the appearance concern; the input lock
## stays on the player root next to the input read.
func play_swap_transition(duration: float) -> void:
	_spawn_swap_transition_fx()
	# Frame SWAP_FX_SPRITE_SWAP_FRAME of SWAP_FX_FRAME_COUNT over `duration`.
	var swap_delay: float = duration * (float(SWAP_FX_SPRITE_SWAP_FRAME) / float(SWAP_FX_FRAME_COUNT))
	get_tree().create_timer(swap_delay).timeout.connect(apply_active_weapon_sprite)


## Spawns the one-shot transition FX at the player's chest. Runs on every peer
## that has this player node (server included), skipping a headless dedicated
## server. Auto-frees when the animation finishes. Was
## multiplayer_controller_v2._spawn_swap_transition_fx (now parents to `owner`).
func _spawn_swap_transition_fx() -> void:
	if OS.has_feature("dedicated_server"):
		return
	if not is_instance_valid(owner) or not is_instance_valid(owner.animated_sprite):
		return

	var fx_texture: Texture2D = load(SWAP_FX_PATH)
	if fx_texture == null:
		return

	var fx_frames := SpriteFrames.new()
	fx_frames.add_animation("swap")
	fx_frames.set_animation_loop("swap", false)
	# 11 frames over the transition duration.
	fx_frames.set_animation_speed("swap", float(SWAP_FX_FRAME_COUNT) / 0.25)

	for i in range(SWAP_FX_FRAME_COUNT):
		var atlas := AtlasTexture.new()
		atlas.atlas = fx_texture
		atlas.region = Rect2(i * SWAP_FX_FRAME_SIZE, 0, SWAP_FX_FRAME_SIZE, SWAP_FX_FRAME_SIZE)
		fx_frames.add_frame("swap", atlas)

	var fx_sprite := AnimatedSprite2D.new()
	fx_sprite.name = "WeaponSwapFX"
	fx_sprite.sprite_frames = fx_frames
	fx_sprite.position = Vector2(0, -16) # Roughly the player's chest.
	fx_sprite.z_index = 5
	owner.add_child(fx_sprite)
	fx_sprite.play("swap")

	# Auto-free when the animation finishes (one-shot per non-looping animation).
	fx_sprite.animation_finished.connect(fx_sprite.queue_free)

#endregion


#region #################### Peer sync ####################

## [SERVER] Sends this player's current sprite (wielded discipline + level) to a
## newly-connected peer. Was multiplayer_controller_v2._on_peer_connected.
func notify_peer_connected(peer_id: int) -> void:
	if not is_instance_valid(owner):
		return
	if not multiplayer.is_server() or peer_id == owner.player_id:
		return
	if BotManager.is_bot(peer_id):
		return

	# Wait a frame to ensure the new peer is ready.
	await get_tree().process_frame
	if not is_instance_valid(owner):
		return

	var level_comp = owner.level_component
	if is_instance_valid(level_comp):
		# Use the currently-wielded discipline so a newly-joining peer sees the
		# player holding whatever weapon they're actually using right now.
		var discipline: int = owner.get_active_discipline()
		change_sprite_rpc.rpc_id(peer_id, Constants.ClassType.find_key(discipline), level_comp.level)

#endregion


#region #################### RPCs ####################

## [SERVER -> CLIENTS] Broadcasts the sprite change to all clients. Authority =
## server (the component's default multiplayer authority); call_local so the host
## (server + client in one tree) applies it too.
@rpc("authority", "call_local", "reliable")
func change_sprite_rpc(class_name_key: String, level: int) -> void:
	var class_type: int = ResourceManager.get_class_type_from_string(class_name_key)
	var sprite_frames: SpriteFrames = ResourceManager.get_sprite_for_level(class_type, level)
	if not is_instance_valid(owner):
		return
	var sprite: AnimatedSprite2D = owner.animated_sprite
	if sprite_frames and is_instance_valid(sprite):
		sprite.sprite_frames = sprite_frames
		sprite.play("idle")
	else:
		push_warning("Could not find sprite for %s level %d" % [class_name_key, level])


## [CLIENT -> SERVER] Asks the server to refresh this player's sprite.
@rpc("any_peer", "call_local", "reliable")
func request_sprite_change() -> void:
	if not multiplayer.is_server():
		return
	refresh_on_server()


## [CLIENT -> SERVER] A new client requests the sprite states of all existing
## players on its map. Was multiplayer_controller_v2.request_all_sprite_states.
@rpc("any_peer", "call_local", "reliable")
func request_all_sprite_states() -> void:
	if not multiplayer.is_server():
		return

	var requester_id: int = multiplayer.get_remote_sender_id()

	var requester_map = MapManager.get_player_map(requester_id)
	if requester_map.is_empty():
		push_warning("Player %d not assigned to a map yet" % requester_id)
		return

	# Only sync sprites of players on the SAME map.
	var players_on_map = MapManager.get_players_on_map(requester_map)

	for other_player_id in players_on_map:
		if other_player_id == requester_id:
			continue # Skip self
		var other_player = PlayerManager.get_player_node(other_player_id)
		if other_player and other_player is MultiplayerPlayerV2 \
				and is_instance_valid(other_player.appearance_component):
			other_player.appearance_component.notify_peer_connected(requester_id)

#endregion
