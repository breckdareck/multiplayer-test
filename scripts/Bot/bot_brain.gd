extends Node

const BotEconomy = preload("res://scripts/Bot/bot_economy.gd")
const BotCombat = preload("res://scripts/Bot/bot_combat.gd")
const BotNavigator = preload("res://scripts/Bot/bot_navigator.gd")

var player: MultiplayerPlayerV2
var bot_id: int

var think_timer: float = 0.0
var think_interval: float = 0.3

var current_action: String = "idle"
var action_timer: float = 0.0

var wander_direction: int = 0
var idle_duration_min: float = 1.0
var idle_duration_max: float = 4.0
var wander_duration_min: float = 2.0
var wander_duration_max: float = 6.0
var wander_chance: float = 0.6

var retreat_health_pct: float = 0.2
## When retreating, the bot flees to safety and waits until HP regenerates to
## this fraction before re-engaging — hysteresis well above retreat_health_pct
## so it doesn't yo-yo straight back into a fight at 1 HP over the threshold.
const RECOVER_TARGET_PCT: float = 0.7
## A retreating bot considers itself safe once no enemy is within this distance.
const SAFE_DISTANCE: float = 260.0
## Recovery gives up waiting once HP has gone this long without climbing — so a
## bot that can't heal (no regen, no potions) doesn't stand frozen forever.
const RECOVER_STALL_TIMEOUT: float = 8.0
## HP must climb at least this fraction to count as recovery progress.
const RECOVER_PROGRESS_STEP: float = 0.02
var _recovering: bool = false
var _recover_hp_mark: float = 0.0
var _recover_stall_timer: float = 0.0
var loot_range: float = 80.0
var loot_priority_range: float = 50.0
## Max vertical gap (px) at which the bot counts as standing on the loot's own
## level. Above it the bot keeps pathing toward the item (down or up) rather than
## freezing in place — comfortably below a platform gap, above the same-platform
## origin/item Y offset that still lets pickup fire (<=15px euclidean).
const LOOT_SAME_LEVEL_Y: float = 20.0
## Periodic loot sweep: when this elapses the bot collects every reachable
## drop in range even mid-combat, so forever-spawning enemies don't starve it
## of loot before drops despawn (~2m10s). Reset once no loot remains in range.
var _loot_sweep_timer: float = 0.0
const LOOT_SWEEP_INTERVAL: float = 14.0

var target_enemy: EnemyBase = null
var target_loot: DroppedItem = null

var _blacklisted_loot: Array[DroppedItem] = []
var _blacklist_clear_timer: float = 0.0
const BLACKLIST_DURATION: float = 15.0
## Combat — target selection, ability use, kiting, the "fight" action.
var _combat = BotCombat.new(self)

var _respawn_timer: float = -1.0
const RESPAWN_DELAY: float = 3.0

var _equip_check_timer: float = 0.0
const EQUIP_CHECK_INTERVAL: float = 2.0

var _ability_check_timer: float = 0.0
const ABILITY_CHECK_INTERVAL: float = 5.0

var _consumable_check_timer: float = 0.0
const CONSUMABLE_CHECK_INTERVAL: float = 1.0
const HEALTH_POTION_THRESHOLD: float = 0.4
const MANA_POTION_THRESHOLD: float = 0.3

var _shop_check_timer: float = 0.0
const SHOP_CHECK_INTERVAL: float = 10.0
const TOWN_MAP_ID: String = "lanterns_rest"
## Inventory & shopping — sell junk, restock potions, route to a town merchant.
var _economy = BotEconomy.new(self)

var allow_map_travel: bool = true

var patrol_route: Array = []
var patrol_index: int = 0
var target_portal: Node = null

# Cached reference to the bot's current map node — avoids resolving it through
# MapManager on every think tick. Refreshed lazily when the bot's map changes.
var _cached_map_node: Node = null
var _cached_map_id: String = ""
var _map_travel_timer: float = 0.0
var _map_stay_timer: float = 0.0
const MAP_TRAVEL_CHECK_INTERVAL: float = 15.0
const MAP_MIN_STAY_TIME: float = 120.0
const LEVEL_OVERRIDE_THRESHOLD: int = 5

var _party_seek_timer: float = 0.0
const PARTY_SEEK_INTERVAL: float = 12.0
const PARTY_SEEK_RANGE: float = 300.0

# --- Bot-invites-player (ADR 0012): rare, polite, self-cleaning. ---
## Cooldown between invite attempts at real players.
var _player_invite_timer: float = 0.0
const PLAYER_INVITE_COOLDOWN: float = 300.0
## How long an unanswered invite keeps the bot waiting in its solo party.
var _pending_player_invite_timer: float = -1.0
const PLAYER_INVITE_TIMEOUT: float = 30.0

# --- Stuck detection: catches a bot that intends to move but makes no
# progress (bad terrain, an unreachable target) and escalates to recovery. ---
var _stuck_sample_pos: Vector2 = Vector2.ZERO
var _stuck_sample_timer: float = 0.0
var _stuck_timer: float = 0.0
const STUCK_SAMPLE_INTERVAL: float = 0.5
## Min px of progress expected per sample while actively walking.
const STUCK_MIN_PROGRESS: float = 6.0
## Stuck this long -> attempt a recovery jump.
const STUCK_JUMP_TIME: float = 1.0
## Stuck this long -> abandon the current target so the think loop re-plans.
const STUCK_ABANDON_TIME: float = 4.0

# --- Travel watchdog: a hard cap per portal hop, since an oscillating failed
# climb keeps "moving" and would slip past the stuck detector. ---
var _travel_timed_portal: Node = null
var _travel_timeout_timer: float = 0.0
const TRAVEL_TIMEOUT: float = 35.0

# Platform-aware navigation: routing across the map's nav graph, the
# ground/jump/climb/drop movement heuristics, and the raycast terrain probes.
var _navigator = BotNavigator.new(self)

# --- Level-of-detail: a bot on a map with no real player re-applies its action
# only once every LOD_APPLY_EVERY frames. The character keeps moving on its held
# input flags between updates, so this lowers decision fidelity only where
# nobody is watching, and cuts the per-frame nav/combat raycast cost there. ---
var _lod_far: bool = false
var _lod_check_timer: float = 0.0
var _lod_frame: int = 0
const LOD_CHECK_INTERVAL: float = 1.0
const LOD_APPLY_EVERY: int = 4

# --- Ambient population (ADR 0011): personality voice + companion commands ---
## Archetype data ({chattiness, lines, key}) resolved by BotManager and set on
## every spawn/attach. Empty when personalities are unavailable — all speech
## no-ops.
var personality: Dictionary = {}
## Per-bot gap between lines; ChatManager.bot_say applies the server-wide
## budget on top. Only reset when a line was actually delivered.
var _speech_cooldown: float = 0.0
const SPEECH_COOLDOWN: float = 40.0
var _last_party_id: int = -1

## Player-issued companion command: "", "follow", or "stay" (/bot follow|stay|free).
## Persists across map hops (the brain outlives the body); lapses when the bot
## stops being a party member under someone else's lead.
var companion_mode: String = ""
var companion_anchor: Vector2 = Vector2.ZERO
var _companion_goal: Vector2 = Vector2.ZERO
const FOLLOW_NEAR_DISTANCE: float = 90.0
const STAY_RADIUS: float = 220.0

# --- Lifetime metrics, surfaced by `/bot stats` and the debug panel. ---
var _metrics := {
	"kills": 0,
	"deaths": 0,
	"deaths_to_enemy": 0,
	"deaths_to_hazard": 0,
	"stuck_recoveries": 0,
	"travel_abandons": 0,
	"loot_collected": 0,
	"gold_from_sales": 0,
}


## Lifetime behaviour counters for this bot (see _metrics).
func get_metrics() -> Dictionary:
	return _metrics


## Connects to the character's death signal for death-cause metrics. Safe to
## call repeatedly (e.g. after a map change re-bodies the bot).
func _connect_health_signals() -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(player.health_component) \
			and not player.health_component.died.is_connected(_on_player_died):
		player.health_component.died.connect(_on_player_died)
	if is_instance_valid(player.level_component) \
			and not player.level_component.leveled_up.is_connected(_on_leveled_up):
		player.level_component.leveled_up.connect(_on_leveled_up)


func _on_player_died(killer: Node) -> void:
	_metrics.deaths += 1
	if killer is EnemyBase:
		_metrics.deaths_to_enemy += 1
	else:
		_metrics.deaths_to_hazard += 1
	try_speak("death")
	ChatManager.bot_emote(bot_id, "/cry")


func _on_leveled_up(new_level: int) -> void:
	try_speak("level_up", {"level": new_level})


# --- Personality speech (ADR 0011) -------------------------------------------

## Attempts a personality line for `event`. Rolls against chattiness and the
## per-bot cooldown, then hands the line to ChatManager.bot_say, which applies
## the server-wide speech budget and the map-scoped broadcast. `force` skips
## the chattiness roll and cooldown (command acks and trade declines should
## answer) — the global budget still applies. The cooldown only resets when a
## line was actually delivered, so a blocked attempt doesn't silence the bot.
func try_speak(event: String, ctx: Dictionary = {}, force: bool = false) -> bool:
	if personality.is_empty():
		return false
	var pool: Array = personality.get("lines", {}).get(event, [])
	if pool.is_empty():
		return false
	if not force:
		if _speech_cooldown > 0.0:
			return false
		if randf() > float(personality.get("chattiness", 0.5)):
			return false
	var text: String = String(pool.pick_random()).format(_speech_context(ctx))
	if ChatManager.bot_say(bot_id, text):
		_speech_cooldown = SPEECH_COOLDOWN
		return true
	return false


## Default template values ({player}, {map}, {level}, ...) with event-specific
## entries merged over them.
func _speech_context(ctx: Dictionary) -> Dictionary:
	var level: int = 0
	if is_instance_valid(player) and is_instance_valid(player.level_component):
		level = player.level_component.level
	var map_id := MapManager.get_player_map(bot_id)
	var base := {
		"player": "",
		"map": MapManager.MAP_DISPLAY_NAMES.get(map_id, map_id.replace("_", " ").capitalize()),
		"level": level,
		"item": "",
		"enemy": "",
	}
	if String(ctx.get("player", "")).is_empty():
		var names := _real_player_names_on_map()
		if not names.is_empty():
			base["player"] = names.pick_random()
	base.merge(ctx, true)
	return base


## Which greeting pool fits this player: stranger, familiar, or friend.
func _greet_event_for(player_name: String) -> String:
	var rep := BotManager.get_reputation(bot_id, player_name)
	if rep >= 10:
		return "greet_friend"
	if rep >= 3:
		return "greet_familiar"
	return "greet"


func _real_player_names_on_map() -> Array:
	var names: Array = []
	for pid in MapManager.get_real_players_on_map(MapManager.get_player_map(bot_id)):
		var node := PlayerManager.get_player_node(pid)
		if is_instance_valid(node) and not node.username.is_empty():
			names.append(node.username)
	return names


func init(player_node: MultiplayerPlayerV2, id: int, behavior_config: Dictionary = {}) -> void:
	player = player_node
	bot_id = id

	think_interval = behavior_config.get("think_interval", 0.3)
	wander_chance = behavior_config.get("wander_chance", 0.6)
	idle_duration_min = behavior_config.get("idle_duration_min", 1.0)
	idle_duration_max = behavior_config.get("idle_duration_max", 4.0)
	wander_duration_min = behavior_config.get("wander_duration_min", 2.0)
	wander_duration_max = behavior_config.get("wander_duration_max", 6.0)
	_combat.aggro_range = behavior_config.get("aggro_range", 200.0)
	loot_range = behavior_config.get("loot_range", 80.0)
	allow_map_travel = behavior_config.get("allow_map_travel", true)
	patrol_route = behavior_config.get("patrol_route", [])

	think_timer = randf() * think_interval
	_party_seek_timer = PARTY_SEEK_INTERVAL + randf() * PARTY_SEEK_INTERVAL

	# Start "far" so the first LOD check on a map that already has a real player
	# registers as an arrival and can fire a greet line.
	_lod_far = true

	_navigator.compute_jump_profile()
	_connect_health_signals()


## Re-points the brain at a freshly spawned character body after a map change.
## The brain is parented to BotManager, not the character (see
## BotManager._on_bot_spawned), so it persists across the despawn/respawn a map
## change performs — keeping travel timers, patrol progress and cooldowns. Only
## references into the old, now-freed map are cleared.
func attach_to_player(player_node: MultiplayerPlayerV2) -> void:
	player = player_node
	current_action = "idle"
	action_timer = 0.0
	target_enemy = null
	target_loot = null
	target_portal = null
	_combat._combat_timer = 0.0
	_combat._combat_last_enemy_hp = -1
	_recovering = false
	_combat._blacklisted_enemies.clear()
	_cached_map_node = null
	_cached_map_id = ""
	_respawn_timer = -1.0
	# The new map has its own nav graph — point IDs from the old graph are
	# meaningless here, so drop any planned path.
	_navigator._nav_path = PackedInt64Array()
	_navigator._nav_goal = Vector2.INF
	_navigator._descend_dir = 0
	# Re-arm the arrival greet: entering a map that has a real player on it
	# counts as meeting them (the LOD check sees a far->near transition).
	_lod_far = true
	# Run shop maintenance on the very next think instead of waiting up to
	# SHOP_CHECK_INTERVAL. Without this, a bot that traveled to town for a
	# restock can leave again before the timer elapses — needs_restock /
	# needs_sell stay stale, the bot re-enters the training map, and the same
	# flags immediately send it back to town. Ping-pong through the portal.
	_shop_check_timer = 0.0
	_connect_health_signals()


func _process(delta: float) -> void:
	if not is_instance_valid(player):
		return

	if player._is_being_cleaned_up:
		return

	if is_instance_valid(player.health_component) and player.health_component.is_dead:
		_clear_input()
		_handle_dead(delta)
		return

	_respawn_timer = -1.0
	_navigator._jump_cooldown_timer -= delta
	_navigator._nav_repath_timer -= delta
	_loot_sweep_timer -= delta
	_combat._gcd_timer -= delta
	action_timer -= delta
	think_timer -= delta

	_speech_cooldown -= delta
	_player_invite_timer -= delta
	if _pending_player_invite_timer > 0.0:
		_pending_player_invite_timer -= delta
		if _pending_player_invite_timer <= 0.0:
			_abandon_unanswered_invite()

	_lod_check_timer -= delta
	if _lod_check_timer <= 0.0:
		_lod_check_timer = LOD_CHECK_INTERVAL
		var was_far := _lod_far
		_lod_far = _is_lod_far()
		# far -> near means a real player just arrived on this map (or the bot
		# just arrived on theirs) — the natural moment for a greeting. The
		# greeting pool tiers by how well this bot knows that player (ADR 0012).
		if was_far and not _lod_far:
			var names := _real_player_names_on_map()
			if not names.is_empty():
				var who: String = names.pick_random()
				if try_speak(_greet_event_for(who), {"player": who}):
					ChatManager.bot_emote(bot_id, "/wave")

	if current_action == "fight" and is_instance_valid(target_enemy):
		var enemy_hp := -1
		if target_enemy.health_component:
			enemy_hp = target_enemy.health_component.current_health
		if _combat._combat_last_enemy_hp != enemy_hp and enemy_hp >= 0:
			_combat._combat_last_enemy_hp = enemy_hp
			_combat._combat_timer = 0.0
		else:
			_combat._combat_timer += delta

	_blacklist_clear_timer -= delta
	if _blacklist_clear_timer <= 0.0:
		_blacklist_clear_timer = BLACKLIST_DURATION
		_combat._blacklisted_enemies.clear()
		_blacklisted_loot.clear()

	if think_timer <= 0.0:
		think_timer = think_interval
		# Don't re-pick the action while the bot is traversing a ladder/rope (the
		# whole CLIMB hop — mounting, riding, dismounting — not just the climb
		# state, since the mount jump is briefly airborne). Switching to or
		# re-pathing toward a wandering enemy mid-traversal strands it on the rope.
		# Normal thinking resumes the moment the bot is off the climb segment.
		if not _navigator.is_climbing() and not _navigator.is_on_climb_segment():
			_think()

	_equip_check_timer -= delta
	if _equip_check_timer <= 0.0:
		_equip_check_timer = EQUIP_CHECK_INTERVAL
		_evaluate_and_equip()

	_ability_check_timer -= delta
	if _ability_check_timer <= 0.0:
		_ability_check_timer = ABILITY_CHECK_INTERVAL
		_combat.build_ability_lists()

	_consumable_check_timer -= delta
	if _consumable_check_timer <= 0.0:
		_consumable_check_timer = CONSUMABLE_CHECK_INTERVAL
		_try_use_consumable()

	_shop_check_timer -= delta
	if _shop_check_timer <= 0.0:
		_shop_check_timer = SHOP_CHECK_INTERVAL
		_economy.run_maintenance()

	# Track how long we've been stuck against a wall
	if player.is_on_wall() and player.is_on_floor() and player.direction != 0:
		_navigator._wall_stuck_timer += delta
	else:
		_navigator._wall_stuck_timer = 0.0

	# Climb inputs are re-asserted each frame by the navigator only while riding a
	# ladder; clear them first so they never stick once the bot is off the ladder.
	player.input_up = false
	player.input_down = false
	if _navigator.is_climbing() and current_action in ["idle", "wander"]:
		# Recovery: the bot is in the climb state but its task ended mid-rope (e.g.
		# loot auto-collected while climbing past it set the action to idle). Idle
		# drives no input AND is_climbing() blocks the think loop, so it would hover
		# on the rope forever. Ride up and off so it lands and can think again.
		player.input_up = true
	elif _should_apply_action():
		_apply_current_action()

	# Stuck detection runs after the action set player.direction this frame.
	_update_stuck_detection(delta)
	_update_travel_watchdog(delta)


## True when no real (non-bot) player is on the bot's map — its action updates
## can run at a reduced rate since no one is observing it.
func _is_lod_far() -> bool:
	var map_id := MapManager.get_player_map(bot_id)
	if map_id.is_empty():
		return false
	return MapManager.get_real_players_on_map(map_id).is_empty()


## Whether to re-apply the current action this frame. Always true near a real
## player; throttled to 1-in-LOD_APPLY_EVERY frames when LOD-far.
func _should_apply_action() -> bool:
	if not _lod_far:
		return true
	_lod_frame = (_lod_frame + 1) % LOD_APPLY_EVERY
	return _lod_frame == 0


## Detects a bot that intends to move but is making no progress, and escalates:
## a recovery jump first, then abandoning the wedged target.
func _update_stuck_detection(delta: float) -> void:
	# Only meaningful while actively trying to walk on the ground. Airborne
	# frames (jump arcs) and deliberate stops reset the tracker.
	if player.direction == 0 or not player.is_on_floor():
		_stuck_timer = 0.0
		_stuck_sample_timer = STUCK_SAMPLE_INTERVAL
		_stuck_sample_pos = player.global_position
		return

	_stuck_sample_timer -= delta
	if _stuck_sample_timer > 0.0:
		return
	_stuck_sample_timer = STUCK_SAMPLE_INTERVAL

	var progress := player.global_position.distance_to(_stuck_sample_pos)
	_stuck_sample_pos = player.global_position
	if progress >= STUCK_MIN_PROGRESS:
		_stuck_timer = 0.0
		return

	_stuck_timer += STUCK_SAMPLE_INTERVAL
	if _stuck_timer >= STUCK_ABANDON_TIME:
		_stuck_timer = 0.0
		_recover_from_stuck()
	elif _stuck_timer >= STUCK_JUMP_TIME:
		_navigator.try_jump()


## Hard cap on a single portal hop. An oscillating failed climb keeps "moving"
## and would slip past the stuck detector, so time the hop directly.
func _update_travel_watchdog(delta: float) -> void:
	if current_action != "travel" or not is_instance_valid(target_portal):
		_travel_timed_portal = null
		_travel_timeout_timer = 0.0
		return

	if target_portal != _travel_timed_portal:
		_travel_timed_portal = target_portal
		_travel_timeout_timer = 0.0

	_travel_timeout_timer += delta
	if _travel_timeout_timer >= TRAVEL_TIMEOUT:
		_travel_timed_portal = null
		_travel_timeout_timer = 0.0
		_abandon_travel()


## Abandons the current travel target and defers the next travel attempt so the
## bot doesn't immediately re-wedge on the same unreachable route.
func _abandon_travel() -> void:
	target_portal = null
	current_action = "idle"
	action_timer = 2.0
	_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
	_navigator._nav_path = PackedInt64Array()
	_metrics.travel_abandons += 1
	player.direction = 0


## Last-resort recovery when the bot is wedged against terrain it can't pass —
## drops whatever target caused it so the think loop can re-plan.
func _recover_from_stuck() -> void:
	_metrics.stuck_recoveries += 1
	match current_action:
		"fight":
			if is_instance_valid(target_enemy) and not _combat._blacklisted_enemies.has(target_enemy):
				_combat._blacklisted_enemies.append(target_enemy)
			_combat.disengage()
		"loot":
			# Loot we can't reach — blacklist it so the sweep moves on rather
			# than re-targeting the same unreachable drop forever.
			if is_instance_valid(target_loot) and not _blacklisted_loot.has(target_loot):
				_blacklisted_loot.append(target_loot)
			target_loot = null
			current_action = "idle"
			action_timer = 1.0
			player.do_pickup = false
		"travel":
			_abandon_travel()
		"wander":
			wander_direction *= -1
		_:
			player.direction = 0


func _handle_dead(delta: float) -> void:
	if _respawn_timer < 0.0:
		_respawn_timer = RESPAWN_DELAY
	_respawn_timer -= delta
	if _respawn_timer <= 0.0:
		_respawn_timer = -1.0
		player.respawn()


## The bot's decision step. Each consideration is checked in strict priority
## order; the first that commits an action stops the cascade. Survival outranks
## errands, errands outrank combat, combat outranks chores, chores outrank idle.
func _think() -> void:
	_refresh_targets()
	_tick_travel_timers()
	_track_party_changes()

	if _consider_retreat(): return
	if _consider_companion(): return
	if _consider_restock_trip(): return
	if _consider_follow_leader(): return
	if _consider_urgent_travel(): return
	if _consider_priority_loot(): return
	if _consider_fight(): return
	if _consider_pending_loot(): return
	if _consider_map_travel(): return
	_consider_idle()


## Clears a dead enemy or collected drop from the current targets.
func _refresh_targets() -> void:
	if is_instance_valid(target_enemy):
		if target_enemy.health_component and target_enemy.health_component.is_dead:
			_metrics.kills += 1
			if target_enemy.enemy_data != null and target_enemy.enemy_data.is_boss:
				try_speak("boss_kill", {"enemy": target_enemy.monster_name})
			target_enemy = null
	else:
		target_enemy = null

	if is_instance_valid(target_loot):
		if target_loot.current_state == DroppedItem.ItemState.COLLECTED:
			_metrics.loot_collected += 1
			if target_loot.item_data != null \
					and target_loot.item_data.rarity >= Constants.ItemRarity.RARE:
				try_speak("rare_loot", {"item": target_loot.item_data.name})
			target_loot = null
	else:
		target_loot = null


## One "here we go" line per boss instance — engaging the same boss again
## after a retarget stays quiet.
var _announced_boss: EnemyBase = null

func _maybe_announce_boss(enemy: EnemyBase) -> void:
	if enemy.enemy_data != null and enemy.enemy_data.is_boss and enemy != _announced_boss:
		_announced_boss = enemy
		try_speak("boss_engage", {"enemy": enemy.monster_name})


## Detects party changes for speech + companion-command hygiene. Tracks real-
## player MEMBERSHIP, not just the party id: a bot that created a solo party
## to invite someone hasn't "joined" anything yet, and a player accepting that
## invite later changes the roster without changing the bot's party id.
var _known_real_members: Dictionary = {}  # username -> true

func _track_party_changes() -> void:
	var party_id := PartyManager.get_player_party_id(bot_id)
	var real_members: Dictionary = {}
	if party_id != -1:
		for member_id in PartyManager.get_party_members(bot_id):
			if not BotManager.is_bot(member_id):
				var member_node := PlayerManager.get_player_node(member_id)
				if is_instance_valid(member_node):
					real_members[member_node.username] = true

	var newly_joined := party_id != -1 and _last_party_id == -1
	var new_real: Array = []
	for uname in real_members:
		if not _known_real_members.has(uname):
			new_real.append(uname)
	_last_party_id = party_id
	_known_real_members = real_members

	if party_id == -1:
		companion_mode = ""  # commands lapse with the party
		return
	if newly_joined or not new_real.is_empty():
		_pending_player_invite_timer = -1.0  # someone answered — stop the clock
		try_speak("party_join")
	# Grouping with real players builds familiarity (ADR 0012 reputation).
	for uname in new_real:
		BotManager.add_reputation(bot_id, uname, 3)


## Survival: when critically low on HP, retreat to safety and regenerate. Stays
## in recovery until HP is comfortably back up — hysteresis so the bot doesn't
## pop out of retreat 1 HP over the threshold and dive straight back in.
func _consider_retreat() -> bool:
	# Town is safe and has the merchant — never recover here. Standing idle to
	# regen wastes time when the bot can shop, heal and head back out; staying
	# in retreat would also leave it stuck if HP regenerates slowly.
	if MapManager.get_player_map(bot_id) == TOWN_MAP_ID:
		_recovering = false
		return false

	if _recovering:
		var hp := _health_fraction()
		if hp >= RECOVER_TARGET_PCT:
			_recovering = false
			return false
		# Track HP progress; if it stalls (no regen, no potions) and the bot is
		# out of the critical danger band, give up waiting and resume activity.
		if hp > _recover_hp_mark + RECOVER_PROGRESS_STEP:
			_recover_hp_mark = hp
			_recover_stall_timer = 0.0
		elif hp >= retreat_health_pct:
			_recover_stall_timer += think_interval
			if _recover_stall_timer >= RECOVER_STALL_TIMEOUT:
				_recovering = false
				return false
		current_action = "retreat"
		return true
	elif _should_retreat():
		_recovering = true
		_recover_hp_mark = _health_fraction()
		_recover_stall_timer = 0.0
		current_action = "retreat"
		try_speak("retreat")
		return true
	return false


## Applies a player-issued companion command (ADR 0011): "follow" sticks to the
## party leader — including same-map and into town, unlike the ambient
## regroup — and "stay" anchors the bot near where it was commanded. Speech
## acks happen in set_companion_mode. Returns true only when the command needs
## movement this think; otherwise falls through so the bot fights/loots
## normally around the commanded position.
func _consider_companion() -> bool:
	if companion_mode.is_empty():
		return false
	# Commands lapse when the bot is no longer a party member under someone
	# else's lead (kicked, disbanded, or promoted to leader itself).
	var leader_id := _get_party_leader()
	if leader_id == 0 or leader_id == bot_id:
		companion_mode = ""
		return false

	if companion_mode == "stay":
		if player.global_position.distance_to(companion_anchor) > STAY_RADIUS:
			_companion_goal = companion_anchor
			target_enemy = null
			current_action = "regroup"
			return true
		return false

	# follow
	var leader_map := MapManager.get_player_map(leader_id)
	var my_map := MapManager.get_player_map(bot_id)
	if leader_map.is_empty():
		return false
	if leader_map != my_map:
		var hop := MapManager.get_next_map_toward(my_map, leader_map)
		if hop.is_empty():
			return false
		if not is_instance_valid(target_portal) or target_portal.target_map_id != hop:
			target_portal = _find_portal_to_map(hop)
		if not is_instance_valid(target_portal):
			return false
		target_enemy = null
		current_action = "travel"
		return true
	var leader_node := PlayerManager.get_player_node(leader_id)
	if not is_instance_valid(leader_node):
		return false
	if player.global_position.distance_to(leader_node.global_position) > FOLLOW_NEAR_DISTANCE:
		_companion_goal = leader_node.global_position
		current_action = "regroup"
		return true
	return false


## Sets a player-issued companion command ("follow"/"stay"/"" = free) and
## speaks the matching ack. "stay" anchors at the bot's current position.
func set_companion_mode(mode: String) -> void:
	companion_mode = mode
	if mode == "stay" and is_instance_valid(player):
		companion_anchor = player.global_position
	target_portal = null
	if not mode.is_empty():
		think_timer = 0.0  # obey on the very next frame's think
	match mode:
		"follow":
			try_speak("command_follow", {}, true)
		"stay":
			try_speak("command_stay", {}, true)
		_:
			try_speak("command_free", {}, true)


## Visit town when out of potions, or when the bag is full with no merchant here
## to sell to. Routes hop-by-hop (town may not be directly portal-connected).
## bot_economy sets needs_restock/needs_sell — its affordability gate keeps a
## broke bot from looping here instead of fighting to earn the gold it needs.
func _consider_restock_trip() -> bool:
	# A commanded bot postpones errands — wandering off to shop mid-"follow"
	# abandons the player it was told to stick with.
	if not companion_mode.is_empty():
		return false
	if not (_economy.needs_restock or _economy.needs_sell):
		return false
	var my_map := MapManager.get_player_map(bot_id)
	if my_map == TOWN_MAP_ID:
		return false
	var hop := MapManager.get_next_map_toward(my_map, TOWN_MAP_ID)
	if hop.is_empty():
		return false
	if not is_instance_valid(target_portal) or target_portal.target_map_id != hop:
		target_portal = _find_portal_to_map(hop)
	if not is_instance_valid(target_portal):
		return false
	target_enemy = null
	current_action = "travel"
	return true


## Squad members regroup with their party leader only when separated onto a
## different map — never into town (the leader visits town to restock; members
## keep farming and rejoin when it heads back out). On the same map a member
## explores, fights and loots on its own instead of clustering on the leader.
## Regrouping routes the bot to the leader's map on foot, hop-by-hop through
## portals — it is never a teleport.
func _consider_follow_leader() -> bool:
	# "stay" outranks ambient regrouping; "follow" already handled cross-map
	# travel (including into town) in _consider_companion before this runs.
	if companion_mode == "stay":
		return false
	if not _should_follow_leader():
		return false
	var leader_map := MapManager.get_player_map(_get_party_leader())
	var my_map := MapManager.get_player_map(bot_id)
	if leader_map == my_map:
		return false
	if leader_map.is_empty() or leader_map == TOWN_MAP_ID:
		return false
	# Step toward the leader's map via the next directly-connected hop, then
	# walk to and through that portal like any other travel action.
	var hop := MapManager.get_next_map_toward(my_map, leader_map)
	if hop.is_empty():
		return false
	if not is_instance_valid(target_portal) or target_portal.target_map_id != hop:
		target_portal = _find_portal_to_map(hop)
	if not is_instance_valid(target_portal):
		return false
	target_enemy = null
	current_action = "travel"
	return true


## Grab loot before chasing the next enemy when it's close, and on a periodic
## sweep clear every reachable drop even mid-combat — otherwise forever-spawning
## enemies keep the bot fighting until the loot despawns. Also keeps target_loot
## current for the lower-priority pending-loot check.
func _consider_priority_loot() -> bool:
	if not _economy.has_inventory_space():
		target_loot = null
		return false
	if not target_loot:
		target_loot = _find_best_loot()
	if target_loot:
		var loot_dist := player.global_position.distance_to(target_loot.global_position)
		if loot_dist <= loot_priority_range or _loot_sweep_timer <= 0.0:
			current_action = "loot"
			return true
	elif _loot_sweep_timer <= 0.0:
		# Sweep done — nothing reachable left in range; wait for the next one.
		_loot_sweep_timer = LOOT_SWEEP_INTERVAL
	return false


## Acquire a combat target, or — if already fighting — switch to a much closer
## enemy so the bot doesn't tunnel-vision a distant foe while one is on top of
## it. Prefers an enemy a party member is already on (focus fire).
func _consider_fight() -> bool:
	if not target_enemy:
		var new_enemy: EnemyBase = _combat.party_focus_target()
		if not is_instance_valid(new_enemy):
			new_enemy = _combat.find_best_enemy()
		if new_enemy:
			_combat.set_target_enemy(new_enemy)
			_maybe_announce_boss(new_enemy)
	else:
		var closer: EnemyBase = _combat.find_best_enemy()
		if is_instance_valid(closer) and closer != target_enemy:
			var cur_sq := player.global_position.distance_squared_to(target_enemy.global_position)
			var new_sq := player.global_position.distance_squared_to(closer.global_position)
			if new_sq < cur_sq * _combat.RETARGET_FACTOR:
				_combat.set_target_enemy(closer)
	# A "stay" bot defends its anchor, not the whole map — chasing an enemy
	# beyond the stay radius would just yo-yo against the regroup pull.
	if companion_mode == "stay" and is_instance_valid(target_enemy) \
			and target_enemy.global_position.distance_to(companion_anchor) > STAY_RADIUS:
		_combat.disengage()
	if target_enemy:
		current_action = "fight"
		return true
	return false


## Known loot that was farther than the priority range — collect it now since
## nothing more urgent is pending.
func _consider_pending_loot() -> bool:
	if target_loot and _economy.has_inventory_space():
		current_action = "loot"
		return true
	return false


## Per-think bookkeeping: advances the travel and min-stay timers no matter
## what the bot is doing. These were previously decremented only when the think
## cascade reached _consider_map_travel — so a bot kept busy by a steady supply
## of enemies or loot never advanced them, and never reconsidered travel until
## it happened to run dry. Gated to squad leaders, who own travel decisions.
func _tick_travel_timers() -> void:
	if not (allow_map_travel and _is_squad_leader() and not _should_follow_leader()):
		return
	_map_stay_timer -= think_interval
	_map_travel_timer -= think_interval


## The portal on the current map that steps toward `dest_map`, routing via the
## next directly-connected hop (the destination is often not adjacent). Null
## when there is no route or no matching portal.
func _portal_toward(dest_map: String) -> Node:
	if dest_map.is_empty():
		return null
	var hop := MapManager.get_next_map_toward(MapManager.get_player_map(bot_id), dest_map)
	if hop.is_empty():
		return null
	return _find_portal_to_map(hop)


## High-priority travel: a bot sitting well outside its map's level band leaves
## now. Checked ahead of looting and combat so an over-/under-levelled bot
## stops farming the wrong map instead of lingering there until the enemies and
## drops run out. Ignores the min-stay timer and re-plans the moment it has no
## portal target, so a multi-hop journey doesn't stall on a transit map.
func _consider_urgent_travel() -> bool:
	if not (allow_map_travel and _is_squad_leader() and not _should_follow_leader()):
		return false
	if not _is_level_out_of_band():
		return false
	if _map_travel_timer <= 0.0 or not is_instance_valid(target_portal):
		_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
		target_portal = _portal_toward(_get_target_map())
	if is_instance_valid(target_portal):
		current_action = "travel"
		return true
	return false


## Routine travel: an in-band squad leader drifts toward the next patrol map
## once its min-stay on the current map has elapsed. Low priority — combat and
## looting come first. Out-of-band travel is handled by _consider_urgent_travel.
func _consider_map_travel() -> bool:
	if not (allow_map_travel and _is_squad_leader() and not _should_follow_leader()):
		return false
	if _map_travel_timer <= 0.0:
		_map_travel_timer = MAP_TRAVEL_CHECK_INTERVAL
		target_portal = null
		if _should_change_map():
			target_portal = _portal_toward(_get_target_map())
	if is_instance_valid(target_portal):
		current_action = "travel"
		return true
	return false


## Nothing pressing — seek a party, then idle or wander.
func _consider_idle() -> void:
	_try_party_seek()
	if action_timer > 0.0:
		return
	if randf() < wander_chance:
		_start_wander()
	else:
		_start_idle()


func _should_retreat() -> bool:
	return _health_fraction() < retreat_health_pct


## Current HP as a 0..1 fraction (1.0 when there is no health component).
func _health_fraction() -> float:
	if not is_instance_valid(player.health_component):
		return 1.0
	var max_hp: int = player.health_component.max_health
	if max_hp <= 0:
		return 1.0
	return float(player.health_component.current_health) / float(max_hp)


## Returns the bot's current map node, resolving it through MapManager only
## when the bot has actually changed maps (cheap map_id string compare otherwise).
func _get_map_node() -> Node:
	var map_id := MapManager.get_player_map(bot_id)
	if map_id != _cached_map_id or not is_instance_valid(_cached_map_node):
		_cached_map_id = map_id
		_cached_map_node = MapManager.get_player_map_node(bot_id)
	return _cached_map_node


func _find_best_loot() -> DroppedItem:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null

	var drops_node = map_node.get_node_or_null("ItemDrops")
	if not drops_node:
		return null

	# Collect eligible drops in range, nearest first, then take the closest one the
	# bot can actually PATH to — don't target loot stranded on an unreachable
	# platform (it would sit there trying to grab it without ever pathing over).
	var candidates: Array = []
	for child in drops_node.get_children():
		if child is not DroppedItem:
			continue
		if not is_instance_valid(child):
			continue
		if child.current_state != DroppedItem.ItemState.SETTLED:
			continue
		if not child._can_player_pickup(player):
			continue
		if child in _blacklisted_loot:
			continue

		var dist_sq := player.global_position.distance_squared_to(child.global_position)
		if dist_sq < loot_range * loot_range:
			candidates.append([dist_sq, child])

	candidates.sort_custom(func(a, b): return a[0] < b[0])
	for c in candidates:
		var drop: DroppedItem = c[1]
		if _navigator.is_target_reachable(drop.global_position):
			return drop
	return null


func _start_idle() -> void:
	current_action = "idle"
	action_timer = randf_range(idle_duration_min, idle_duration_max)
	wander_direction = 0
	# Ambient flavor: occasionally sit through the idle — only when someone is
	# around to see it (the emote gap caps the map-wide rate).
	if not _lod_far and randf() < 0.15:
		if ChatManager.bot_emote(bot_id, "/sit"):
			action_timer = maxf(action_timer, 3.5)


func _start_wander() -> void:
	current_action = "wander"
	action_timer = randf_range(wander_duration_min, wander_duration_max)
	wander_direction = 1 if randf() > 0.5 else -1


func _apply_current_action() -> void:
	match current_action:
		"idle":
			player.direction = 0
			player.do_pickup = false
		"wander":
			player.do_pickup = false
			_do_wander()
		"fight":
			player.do_pickup = false
			_combat.do_fight()
		"retreat":
			player.do_pickup = false
			_do_retreat()
		"loot":
			_do_loot()
		"travel":
			_do_navigate_to_portal()
		"regroup":
			# Walking back to a companion goal (the leader, or a stay anchor).
			player.do_pickup = false
			_navigator.navigate_smart(_companion_goal)


func _do_wander() -> void:
	player.direction = wander_direction
	if player.direction != 0:
		player.facing_direction = player.direction

	if not player.is_on_floor():
		return

	if player.is_on_wall():
		if _navigator._wall_stuck_timer >= _navigator.WALL_STUCK_JUMP_TIME:
			_navigator.try_jump()
		else:
			wander_direction *= -1
			player.direction = wander_direction
			if player.direction != 0:
				player.facing_direction = player.direction
		return

	if _navigator.is_near_ledge():
		wander_direction *= -1
		player.direction = wander_direction
		if player.direction != 0:
			player.facing_direction = player.direction


## Retreats from danger and waits to regenerate. Moves away from the nearest
## threat; once no enemy is within SAFE_DISTANCE it holds still and lets HP (and
## any potion _try_use_consumable can drink) bring it back up. The think loop
## keeps the bot in this action until _recovering clears.
func _do_retreat() -> void:
	var threat := _nearest_enemy(SAFE_DISTANCE)
	if not is_instance_valid(threat):
		# Clear of every enemy — stand still and recover.
		player.direction = 0
		return

	var to_threat := threat.global_position - player.global_position
	var dir := -1 if to_threat.x > 0 else 1
	player.direction = dir
	player.facing_direction = dir

	if player.is_on_floor():
		# Jump over a wall in the escape direction.
		if player.is_on_wall():
			if _navigator._wall_stuck_timer >= _navigator.WALL_STUCK_JUMP_TIME:
				_navigator.try_jump()
		elif _navigator.is_near_ledge():
			# Drop down only when there is safe ground below. At a pit or the
			# map edge, stop at the ledge — never jump or walk off into the
			# void (jumping while fleeing toward the edge launches the bot off).
			if not _navigator.raycast_down(player.global_position + Vector2(dir * 18.0, 0), 200.0):
				player.direction = 0


## Nearest live enemy on the bot's map within max_dist, or null. Unlike
## _find_best_enemy this is used for retreat safety checks, not target picking.
func _nearest_enemy(max_dist: float) -> EnemyBase:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	var best: EnemyBase = null
	var best_sq := max_dist * max_dist
	for node: EnemyBase in BotManager.get_enemies_on_map(MapManager.get_player_map(bot_id), map_node):
		var d := player.global_position.distance_squared_to(node.global_position)
		if d < best_sq:
			best_sq = d
			best = node
	return best


func _do_loot() -> void:
	if not is_instance_valid(target_loot) or target_loot.current_state == DroppedItem.ItemState.COLLECTED:
		target_loot = null
		current_action = "idle"
		player.do_pickup = false
		return

	var to_loot := target_loot.global_position - player.global_position
	var dx = abs(to_loot.x)
	var dy = abs(to_loot.y)

	# "On top of" the item needs the bot GROUNDED on the same level, BOTH axes
	# aligned. Pickup fires at <=15px euclidean (DroppedItem.pickup_distance), so on
	# the loot's own platform dy is tiny; a platform away it's 40px+. The floor
	# check matters when the loot sits beside a ladder: without it, climbing past
	# the item's x/y trips this "on top" branch and the bot stops dead on the rope
	# trying to grab loot it can't reach. Off the floor (climbing/jumping) it keeps
	# pathing instead.
	if player.is_on_floor() and dx <= 10.0 and dy <= LOOT_SAME_LEVEL_Y:
		player.direction = 0
		player.do_pickup = true
	else:
		player.do_pickup = true  # keep trying while approaching
		_navigator.navigate_smart(target_loot.global_position)


func _get_party_leader() -> int:
	var party_id := PartyManager.get_player_party_id(bot_id)
	if party_id == -1:
		return 0
	return PartyManager.get_party_leader(party_id)


func _should_follow_leader() -> bool:
	var leader_id := _get_party_leader()
	if leader_id == 0:
		return false  # not in a party
	# Follow whoever leads the party — bot or player — unless that is this bot.
	# Only the squad leader makes its own travel decisions; members follow it.
	return leader_id != bot_id


func _try_party_seek() -> void:
	_party_seek_timer -= think_interval
	if _party_seek_timer > 0.0:
		return
	_party_seek_timer = PARTY_SEEK_INTERVAL + randf() * 5.0

	var my_party_id := PartyManager.get_player_party_id(bot_id)
	if my_party_id != -1:
		return

	var my_map := MapManager.get_player_map(bot_id)
	var best_bot_id: int = 0
	var best_dist: float = PARTY_SEEK_RANGE

	for other_id in BotManager.active_bots:
		if other_id == bot_id:
			continue
		if PartyManager.get_player_party_id(other_id) != -1:
			continue
		if MapManager.get_player_map(other_id) != my_map:
			continue
		var other_node := PlayerManager.get_player_node(other_id)
		if not is_instance_valid(other_node):
			continue
		var dist := player.global_position.distance_to(other_node.global_position)
		if dist < best_dist:
			best_dist = dist
			best_bot_id = other_id

	if best_bot_id == 0:
		# No solo bot around — maybe a solo PLAYER wants company (ADR 0012).
		_maybe_invite_player(my_map)
		return

	var party_id := PartyManager.create_party(bot_id)
	if party_id == -1:
		return
	var accepted := PartyManager.send_invite(bot_id, best_bot_id)
	if not accepted:
		PartyManager.leave_party(bot_id)


## A solo bot may invite a nearby solo player to group. Rare and polite: a
## long per-bot cooldown, one pending attempt at a time, and the temporary
## solo party is abandoned if the player doesn't answer — a bot never sits
## leader of a phantom party. The player consents through the normal invite UI.
func _maybe_invite_player(my_map: String) -> void:
	if _player_invite_timer > 0.0 or _pending_player_invite_timer > 0.0:
		return
	if not is_instance_valid(player.level_component):
		return
	var bot_level: int = player.level_component.level

	for pid in MapManager.get_real_players_on_map(my_map):
		if PartyManager.get_player_party_id(pid) != -1:
			continue
		var node := PlayerManager.get_player_node(pid)
		if not is_instance_valid(node) or not is_instance_valid(node.level_component):
			continue
		if absi(node.level_component.level - bot_level) > 10:
			continue
		if player.global_position.distance_to(node.global_position) > PARTY_SEEK_RANGE:
			continue

		_player_invite_timer = PLAYER_INVITE_COOLDOWN
		var party_id := PartyManager.create_party(bot_id)
		if party_id == -1:
			return
		# Creating the solo party is setup, not "joining" — keep the membership
		# tracker quiet so party_join only fires if the player accepts.
		_last_party_id = party_id
		if not PartyManager.send_invite(bot_id, pid):
			PartyManager.leave_party(bot_id)
			return
		_pending_player_invite_timer = PLAYER_INVITE_TIMEOUT
		try_speak("party_invite", {"player": node.username}, true)
		return


## The invite timed out unanswered — stand down if still alone in the party.
func _abandon_unanswered_invite() -> void:
	_pending_player_invite_timer = -1.0
	if PartyManager.get_player_party_id(bot_id) == -1:
		return
	if PartyManager.get_party_members(bot_id).size() <= 1:
		PartyManager.leave_party(bot_id)


func _is_squad_leader() -> bool:
	var party_id := PartyManager.get_player_party_id(bot_id)
	if party_id == -1:
		return true
	return PartyManager.get_party_leader(party_id) == bot_id


## True when the bot's level sits far enough outside its current map's
## difficulty band (by LEVEL_OVERRIDE_THRESHOLD) that it should travel now,
## even mid-combat. False on maps with no difficulty entry (e.g. town).
func _is_level_out_of_band() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.level_component):
		return false
	var difficulty := BotManager.get_map_difficulty(MapManager.get_player_map(bot_id))
	if difficulty.is_empty():
		return false
	var bot_level: int = player.level_component.level
	var max_level: int = difficulty.get("max_level", 999)
	var min_level: int = difficulty.get("min_level", 1)
	return bot_level >= max_level + LEVEL_OVERRIDE_THRESHOLD \
		or bot_level <= min_level - LEVEL_OVERRIDE_THRESHOLD


func _should_change_map() -> bool:
	if not is_instance_valid(player) or not is_instance_valid(player.level_component):
		return false

	var my_map := MapManager.get_player_map(bot_id)
	var difficulty := BotManager.get_map_difficulty(my_map)
	if difficulty.is_empty():
		return not patrol_route.is_empty()

	# Level override: always travel immediately if way out of range.
	if _is_level_out_of_band():
		return true

	# Patrol route: only after stay timer expires, 30% chance per check.
	if _map_stay_timer > 0.0:
		return false
	if not patrol_route.is_empty():
		return randf() < 0.3

	return false


func _get_target_map() -> String:
	if not is_instance_valid(player) or not is_instance_valid(player.level_component):
		return ""

	var bot_level: int = player.level_component.level
	var my_map := MapManager.get_player_map(bot_id)

	# Level override: pick the map whose difficulty band best fits the bot.
	if _is_level_out_of_band():
		var best_map := ""
		var best_fit := 999
		var difficulties_map: Dictionary = BotManager.bot_config.get("map_difficulty", {})
		for map_id in difficulties_map:
			if map_id == my_map:
				continue
			var md: Dictionary = difficulties_map[map_id]
			var mid_level: int = (md.get("min_level", 1) + md.get("max_level", 60)) / 2
			var fit := absi(bot_level - mid_level)
			if fit < best_fit:
				best_fit = fit
				best_map = map_id
		if not best_map.is_empty():
			return best_map

	# Patrol route: prefer the next entry whose difficulty band fits the bot's
	# level. On a "transient" map with no band of its own (e.g. town), fall
	# back to the closest-fitting entry when nothing is in-band — otherwise the
	# bot refuses to leave and idles forever. On a banded map, do NOT fall
	# back: returning "" tells the caller "no patrol move right now," and the
	# bot stays where it is. Falling back from a banded map would patrol-travel
	# an in-band bot onto a wrong-level map, triggering urgent travel back —
	# slow oscillation through the same portals.
	if patrol_route.is_empty():
		return ""
	var on_transient_map: bool = BotManager.get_map_difficulty(my_map).is_empty()
	var all_difficulties: Dictionary = BotManager.bot_config.get("map_difficulty", {})
	var fallback_map := ""
	var fallback_idx := patrol_index
	var fallback_gap := 1 << 30
	for i in patrol_route.size():
		var idx := (patrol_index + 1 + i) % patrol_route.size()
		var candidate: String = patrol_route[idx]
		if candidate == my_map:
			continue
		var md: Dictionary = all_difficulties.get(candidate, {})
		if md.is_empty():
			patrol_index = idx
			return candidate
		var min_lvl: int = md.get("min_level", 1)
		var max_lvl: int = md.get("max_level", 999)
		if bot_level >= min_lvl - LEVEL_OVERRIDE_THRESHOLD and bot_level <= max_lvl + LEVEL_OVERRIDE_THRESHOLD:
			patrol_index = idx
			return candidate
		if on_transient_map:
			# Track the closest-fit out-of-band entry as a transient-map fallback.
			var gap: int = maxi(min_lvl - bot_level, bot_level - max_lvl)
			if gap < fallback_gap:
				fallback_gap = gap
				fallback_map = candidate
				fallback_idx = idx
	if not fallback_map.is_empty():
		patrol_index = fallback_idx
		return fallback_map
	return ""


func _find_portal_to_map(target_map_id: String) -> Node:
	var map_node := _get_map_node()
	if not is_instance_valid(map_node):
		return null
	return _search_for_portal(map_node, target_map_id)


func _search_for_portal(node: Node, target_map_id: String) -> Node:
	if "target_map_id" in node and node.target_map_id == target_map_id:
		return node
	for child in node.get_children():
		var result := _search_for_portal(child, target_map_id)
		if result:
			return result
	return null


func _do_navigate_to_portal() -> void:
	if not is_instance_valid(target_portal):
		target_portal = null
		current_action = "idle"
		return

	# Interact ONLY with the portal we actually want — not whatever portal we
	# happen to be passing through (or spawned next to). Without this, a bot
	# that arrives in a map at a spawn point overlapping a *different* portal's
	# Area2D — common because spawn points are placed adjacent to their portal
	# of origin — immediately portal-interacts and rides that portal back the
	# way it came on the very first travel tick, even when target_portal is
	# somewhere else. That's a single-frame town <-> game oscillation.
	if player.current_portal == target_portal:
		player.direction = 0
		player.do_portal_interact = true
		target_portal = null
		_map_stay_timer = MAP_MIN_STAY_TIME
		return

	# Route to the portal via the platform-nav graph; it handles terrain the
	# greedy heuristics can't, and falls back to direct navigation itself.
	_navigator.navigate_smart(target_portal.global_position)


func _evaluate_and_equip() -> void:
	if not is_instance_valid(player):
		return
	if not is_instance_valid(player.inventory_component):
		return
	if not is_instance_valid(player.equipment_component):
		return

	var class_type: Constants.ClassType = Constants.ClassType.BEGINNER
	if is_instance_valid(player.weapon_mastery_component):
		class_type = player.weapon_mastery_component.primary_discipline as Constants.ClassType

	for slot in player.inventory_component.get_slots():
		if slot.item == null:
			continue
		if slot.item is not EquipmentData:
			continue

		var target_slot := BotEquipmentLogic.get_target_slot(slot.item, player.equipment_component)
		if target_slot == null:
			continue

		if BotEquipmentLogic.should_equip(target_slot.item, slot.item, class_type):
			var upgrade_name: String = slot.item.name
			# UI-independent swap — moves the upgrade into equipment and the
			# old item back into this inventory slot, with tracking + stats.
			player.inventory_component.swap_slot_data(slot, target_slot)
			try_speak("gear_upgrade", {"item": upgrade_name})


func _try_use_consumable() -> void:
	if not is_instance_valid(player) or not is_instance_valid(player.inventory_component):
		return

	var need_health := false
	var need_mana := false

	if is_instance_valid(player.health_component):
		var health_pct := float(player.health_component.current_health) / float(player.health_component.max_health)
		need_health = health_pct < HEALTH_POTION_THRESHOLD

	if is_instance_valid(player.mana_component):
		var mana_pct := float(player.mana_component.current_mana) / float(player.mana_component.max_mana)
		need_mana = mana_pct < MANA_POTION_THRESHOLD

	if not need_health and not need_mana:
		return

	for slot in player.inventory_component.get_slots():
		if not slot.item or slot.item is not ConsumableData:
			continue
		var consumable := slot.item as ConsumableData
		if not consumable.effect_script:
			continue

		var is_health_pot := consumable.effect_properties.has("heal_amount")
		var is_mana_pot := consumable.effect_properties.has("regain_amount")

		if (need_health and is_health_pot) or (need_mana and is_mana_pot):
			player.inventory_component.remove_item_from_stack(consumable, 1, "used")
			var effect_instance = consumable.effect_script.new() as BaseItemEffect
			effect_instance.user = player
			effect_instance.source_item = consumable
			effect_instance.execute()
			return


func _clear_input() -> void:
	player.direction = 0
	player.do_attack = false
	player.do_jump = false
	player.do_drop = false
	player.do_pickup = false
	player.do_portal_interact = false
	player.input_up = false
	player.input_down = false
