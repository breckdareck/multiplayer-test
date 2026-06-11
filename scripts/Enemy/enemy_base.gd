class_name EnemyBase
extends CharacterBody2D

# Emitted after the death animation finishes, signaling it can be returned to the pool.
signal ready_for_pooling

## [Boss] Emitted on the SERVER each time the boss crosses into a new phase.
## `phase_index` is 0-based (the index into enemy_data.phase_health_thresholds
## that was just crossed). Phase 0 is the starting state and is never emitted.
signal boss_phase_changed(phase_index: int)

## Enemy-damage defense mitigation curve (diminishing returns, in damage_on_overlap).
## mitigation = eff_def / (eff_def + DEFENSE_SOFTNESS * monster_att), capped at
## MAX_DEFENSE_MITIGATION.
##
## Tuned conservatively so DEFENSE (gear/armor, CON, STR, Bulwark Stance) is NOT
## overpowered: at SOFTNESS 0.75 the curve is no more generous than the OLD
## linear formula for any defense above ~0.25x the monster's attack (the normal
## range), so stacking armor never beats the previous mitigation there — it just
## REMOVES the old hard wall (the old min(b*def, 0.80*att) cap maxed out at low
## defense, wasting everything beyond it). Diminishing returns mean each armor
## point is worth less than the last, and the cap guarantees you always take
## >=15% of the hit. Reaching the 0.85 cap needs eff_def ~= 4.25x the monster's
## attack — i.e. heavy, deliberate investment, not incidental gear.
## Tune SOFTNESS up to make armor weaker per point; tune the cap for peak
## tankiness. The L100 benchmark assumes these values.
const DEFENSE_SOFTNESS: float = 0.75
const MAX_DEFENSE_MITIGATION: float = 0.85

## How long after an evasion DODGE the player's next strike is guaranteed to crit
## (the rogue payoff for speccing evasion). Consumed on the next hit (combat.gd).
const EVASION_CRIT_WINDOW_MS: int = 4000

@export var enemy_data: EnemyData

@export var respawnable: bool
@export var respawn_delay: int = 10

@export_category("Components")
@export var health_component: HealthComponent
@export var stats_component: StatsComponent

@export_category("Curves")
@export var health_curve: Curve
@export var experience_curve: Curve
@export var wep_att_curve: Curve
@export var magic_att_curve: Curve
@export var wep_def_curve: Curve
@export var magic_def_curve: Curve
@export var monies_curve: Curve

@export_category("UI")
@export var name_label: Label

# Internal properties populated from EnemyData
var monster_name: String
var monster_level: int
var movement_speed: float

@export_category("Drops")
var item_drops: Array[ItemDropResource] = []
const DROPPED_ITEM = preload("uid://b43dktokqxhjo")
const POTION_DROP_CHANCE := 0.05

# Flat knockback resistance shared by all enemies, rolled against incoming hits.
const BASE_KNOCKBACK_RESIST := 60

# Health pool handed to is_invincible enemies (training dummies). The
# HealthComponent floor-at-1 guard is the real never-die mechanism; this just
# keeps the health bar reading full while you wail on it.
const INVINCIBLE_MAX_HEALTH := 1_000_000_000

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var state_machine: StateMachine = $StateMachine
@onready var attack_hitbox: Area2D = $AttackHitbox
@onready var body_hitbox: Area2D = $BodyHitbox
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var health_bar: ProgressBar = get_node_or_null("HealthBar")

# MapleStory-style overhead HP bar: the bar stays hidden until the LOCAL player
# damages this enemy, then shows on that player's screen only for a short window
# that refreshes on each hit. Per-client, purely cosmetic — the timer lives on
# each peer (including the host) and is (re)started by client_show_health_bar.
const HEALTH_BAR_VISIBLE_DURATION := 4.0
var _health_bar_hide_timer: Timer


var experience_reward: int = 0:
	get():
		if experience_curve:
			return int(experience_curve.sample(monster_level))
		return 0
var post_death_delay: float = 1.5 # Time to wait after death animation before disappearing.
var damage_by_player: Dictionary = {} # player_id : damage_amount
var facing_direction: int = 1
var _is_being_cleaned_up: bool = false
var initial_position: Vector2

# --- AI / aggro state ---
## The player or bot this enemy is currently hunting (null when not aggroed).
var current_target: Node2D = null
## Where the enemy stood when it began chasing — used to leash the pursuit.
var leash_anchor: Vector2
## Time.get_ticks_msec() at which the next attack becomes available.
var _attack_cooldown_until: int = 0
## Proximity-activation sleep (ADR 0007). Distinct from pool-deactivate (death):
## an asleep enemy keeps its visible body, collision, and synchronizer but pauses
## AI processing. The MapManager scanner toggles this so enemies far from every
## agent — and every enemy on a resident-but-empty map — cost ~0. Pooled/dead
## enemies are skipped so waking never revives a corpse.
var _activation_asleep: bool = false

const _CHASE_STATE_SCRIPT := preload("res://scripts/Enemy/StateMachine/enemy_chase.gd")
const _HIT_STATE_SCRIPT := preload("res://scripts/Enemy/StateMachine/enemy_hit.gd")
const _BOSS_SPECIAL_STATE_SCRIPT := preload("res://scripts/Enemy/StateMachine/enemy_boss_special.gd")

# --- Boss state (server-authoritative; only used when enemy_data.is_boss) -----
## Pure phase/enrage crossing math, kept in a dependency-free helper so it's
## unit-testable in isolation and has one canonical home.
const _BOSS_PHASE_LOGIC := preload("res://scripts/Enemy/boss_phase_logic.gd")
## Per-phase damage multiplier, bumped +15% each phase transition. Multiplies the
## boss's normal attack AND its special. 1.0 outside boss fights.
var _boss_damage_mult: float = 1.0
## Per-phase attack-speed divisor (shrinks the attack cooldown). 1.0 = unmodified.
var _boss_attack_speed_mult: float = 1.0
## Highest phase index already entered (-1 = still in the opening phase). The
## threshold check only fires phases with an index ABOVE this, so a heal-then-
## re-damage never re-triggers a passed phase.
var _boss_phase_idx: int = -1
## True once the enrage threshold has been crossed; enrage applies exactly once.
var _boss_enraged: bool = false
## Per-phase damage bump applied on each phase transition (+15% of base).
const _BOSS_PHASE_DAMAGE_STEP: float = 0.15
## Per-phase attack-speed bump (cooldown divisor) applied on each transition.
const _BOSS_PHASE_ATTACK_SPEED_STEP: float = 0.10
## True while a telegraphed special is mid-windup (suppresses re-scheduling).
var _boss_special_pending: bool = false
## Cached BossAttackData list (authored or legacy-synthesised), built once per spawn.
var _special_attacks_cache: Array[BossAttackData] = []
var _attacks_cached: bool = false
## Per-attack next-ready server clock (ms), keyed by index into the attack list.
var _attack_ready_at: Dictionary = {}
## The attack the readiness gate picked for the in-progress windup, + its index.
var _pending_special_attack: BossAttackData = null
var _pending_special_idx: int = -1

# --- Mark indicator (floating diamond over marked enemies) ---
const _MARK_INDICATOR_SCRIPT := preload("res://scripts/Enemy/mark_indicator.gd")
const _DOT_VISUALS_SCRIPT := preload("res://scripts/Enemy/dot_visuals.gd")
## Mark meta key → indicator color, in PRIORITY order (first active wins when an
## enemy carries more than one mark). The metas are absolute server-clock expiry
## timestamps (ms) written by the mark abilities' AL_*.gd on_hit. Dictionaries
## preserve insertion order, so iterating gives the priority.
const _MARK_META_COLORS := {
	"death_mark_remaining": Color(1.0, 0.27, 0.27),     # Death Mark — red
	"hunters_mark_remaining": Color(1.0, 0.84, 0.22),   # Mark of the Hunt — gold
	"sentinels_mark_remaining": Color(0.42, 0.70, 1.0), # Sentinel's Mark — blue
	"mana_resonance_remaining": Color(0.72, 0.42, 1.0), # Mana Surge — purple
	# Weakened attacker (Challenging Shout / Choking Smoke / Suppressing
	# Fire — the shared smoke-choke channel health.gd reads). Lowest
	# priority: a real mark wins the slot. Drawn as a slashed-through
	# downward sword (see _MARK_META_SHAPES) — the attack-down tell.
	"smoke_choke_expire_at_ms": Color(0.72, 0.76, 0.82),
}
## Glyph shape per mark meta (mark_indicator.gd shapes). Default: "diamond".
const _MARK_META_SHAPES := {
	"smoke_choke_expire_at_ms": "weaken",
}
## How often (seconds) the server re-evaluates an enemy's mark state. Cheap
## (4 meta checks) so 0.2s is plenty responsive without per-frame cost.
const _MARK_CHECK_INTERVAL := 0.2

var mark_indicator: Node2D = null
var dot_visuals: Node2D = null
var _mark_check_accum: float = 0.0
## Index of the currently-broadcast mark color (-1 = none). Only re-broadcast
## the sync RPC when this changes, not every check.
var _current_mark_idx: int = -1


func _apply_enemy_data() -> void:
	monster_name = enemy_data.monster_name
	monster_level = enemy_data.monster_level
	movement_speed = enemy_data.movement_speed
	item_drops = enemy_data.item_drops

	# Set Monies Coin Drop Min and Max Amounts based on Curve
	var filtered_array: Array[ItemDropResource] = item_drops.filter(func(drop): return drop.item_name == "Coin")
	if len(filtered_array) > 0:
		filtered_array[0].min_amount = roundi(monies_curve.sample(monster_level) * 0.9)
		filtered_array[0].max_amount = roundi(monies_curve.sample(enemy_data.monster_level) * 1.1)
	else:
		var monies_drop = ItemDropResource.new()
		monies_drop.drop_chance = 0.9
		monies_drop.min_amount = roundi(monies_curve.sample(monster_level) * 0.9)
		monies_drop.max_amount = roundi(monies_curve.sample(monster_level) * 1.1)
		item_drops.append(monies_drop)

	_add_potion_drops()

	if animated_sprite:
		animated_sprite.sprite_frames = enemy_data.sprite_frames
	
	if stats_component:
		# Effective multipliers off the shared curves = archetype preset x per-enemy
		# fine-tune (1.0 = curve baseline). Lets same-level mobs vary by "feel" —
		# e.g. an OOZE slime: high DEFENSE, low MAGICDEFENSE.
		var mults: Dictionary = enemy_data.effective_stat_mults()
		var atk_m: float = mults["atk"]
		var def_m: float = mults["def"]
		var mdef_m: float = mults["mdef"]
		var curve_stats: Dictionary[Constants.StatType, StatData] = {}
		curve_stats[Constants.StatType.WEAPONATTACK] = StatData.new(Constants.StatType.WEAPONATTACK, roundi(wep_att_curve.sample(monster_level) * atk_m))
		curve_stats[Constants.StatType.MAGICATTACK] = StatData.new(Constants.StatType.MAGICATTACK, roundi(magic_att_curve.sample(monster_level) * atk_m))
		curve_stats[Constants.StatType.DEFENSE] = StatData.new(Constants.StatType.DEFENSE, roundi(wep_def_curve.sample(monster_level) * def_m))
		curve_stats[Constants.StatType.MAGICDEFENSE] = StatData.new(Constants.StatType.MAGICDEFENSE, roundi(magic_def_curve.sample(monster_level) * mdef_m))
		curve_stats[Constants.StatType.KNOCKBACKRESIST] = StatData.new(Constants.StatType.KNOCKBACKRESIST, BASE_KNOCKBACK_RESIST)

		stats_component.stats = curve_stats
		
	var character_collision_shape_node: CollisionShape2D = $CollisionShape2D
	if character_collision_shape_node and enemy_data.character_collision_shape:
		character_collision_shape_node.shape = enemy_data.character_collision_shape
		
	var body_hitbox_shape_node: CollisionShape2D = $BodyHitbox/EnemyBody
	if body_hitbox_shape_node and enemy_data.body_hitbox_shape:
		body_hitbox_shape_node.shape = enemy_data.body_hitbox_shape
		
	var attack_hitbox_shape_node: CollisionShape2D = $AttackHitbox/SlashCollisionShape
	if attack_hitbox_shape_node and enemy_data.attack_hitbox_shape:
		attack_hitbox_shape_node.shape = enemy_data.attack_hitbox_shape


## Gives every enemy a small chance to drop a healing/mana potion matched to its
## level. Idempotent: EnemyData (and its item_drops array) is shared between
## pooled instances, so skip potions that were already injected.
func _add_potion_drops() -> void:
	var tier := _potion_tier_for_level(monster_level)
	for kind in ["Healing", "Mana"]:
		var potion_name := "%s%s Draught" % [tier, kind]
		var already_added := item_drops.any(
			func(drop): return drop != null and drop.item_name == potion_name
		)
		if already_added:
			continue
		var potion_drop := ItemDropResource.new()
		potion_drop.item_name = potion_name
		potion_drop.drop_chance = POTION_DROP_CHANCE
		item_drops.append(potion_drop)


## Maps an enemy level to a Draught tier prefix ("" is the base, untiered tier).
func _potion_tier_for_level(level: int) -> String:
	if level <= 16:
		return "Lesser "
	if level <= 33:
		return ""
	if level <= 50:
		return "Greater "
	if level <= 66:
		return "Grand "
	if level <= 83:
		return "Superior "
	return "Supreme "


func _ready() -> void:
	if not is_multiplayer_authority():
		set_process(false)
		set_physics_process(false)

	# Create the mark indicator on EVERY peer (server + clients) so the
	# sync_mark_indicator RPC has a node to toggle. It's a local child (not
	# part of the replicated scene), positioned above the head — DmgNumOrigin
	# sits at y=-47, so -60 floats just above it. Hidden until a mark applies.
	mark_indicator = _MARK_INDICATOR_SCRIPT.new()
	mark_indicator.name = "MarkIndicator"
	mark_indicator.position = Vector2(0, -60)
	add_child(mark_indicator)

	# DoT visual feedback (bleed / poison / burn icons + particles + poison tint) on
	# EVERY peer, driven by play_dot() → _sync_dot_tick RPC, like the mark indicator.
	dot_visuals = _DOT_VISUALS_SCRIPT.new()
	dot_visuals.name = "DotVisuals"
	add_child(dot_visuals)

	if enemy_data:
		_apply_enemy_data()
	else:
		push_error("Enemy '%s' is missing EnemyData resource." % name)
		return
	# Add to networked entities group for proper cleanup during channel switching
	add_to_group("networked_entities")
	add_to_group("Enemies")
	
	if not health_component:
		push_error("Enemy '%s' requires a HealthComponent to be assigned." % name)
		return

	if multiplayer.is_server():
		# The server listens for the death signal from the component.
		initial_position = global_position
		if enemy_data.is_invincible:
			# Training dummy: never dies. Floor-at-1 in HealthComponent is the
			# real guard; the huge pool just keeps the bar visually full.
			health_component.invincible = true
			health_component.max_health = INVINCIBLE_MAX_HEALTH
		else:
			health_component.max_health = maxi(1, int(health_curve.sample(monster_level) * enemy_data.effective_stat_mults()["hp"]))
		health_component.current_health = health_component.max_health
		health_component.died.connect(_on_enemy_died)
		health_component.damaged.connect(on_enemy_damaged)
		# [Boss] Watch HP crossings for phase/enrage triggers (server-only).
		# health_changed fires on every health mutation; _on_boss_health_changed
		# is gated to is_boss so non-boss enemies that somehow reach it no-op.
		if enemy_data.is_boss:
			health_component.health_changed.connect(_on_boss_health_changed)
			_init_boss_attacks()
		body_hitbox.body_entered.connect(_on_body_hitbox_body_entered)
		# Only connect animation_finished if AnimatedSprite2D exists (not on dedicated server)
		if animated_sprite:
			animated_sprite.animation_finished.connect(_on_animation_finished)
		await get_tree().process_frame

	# Invincible training dummies are level-neutral (combat reads them as the
	# attacker's level), so a fixed "Lv.X" would be misleading — show just the name.
	if enemy_data.is_invincible:
		name_label.text = monster_name
	else:
		name_label.text = "Lv.%d %s" % [monster_level, monster_name]
	# Inject the AI chase state, then initialize the state machine with the
	# same pattern as the player.
	_ensure_chase_state()
	_ensure_hit_state()
	# [Boss] Inject the telegraphed-special state. Created on every peer (gated by
	# the data flag, identical everywhere) so the state-name sync resolves on
	# clients; its windup/damage only advances on the server.
	if enemy_data != null and enemy_data.is_boss:
		_ensure_boss_special_state()
	state_machine.init(self, animated_sprite)

	# Overhead HP bar starts hidden on every peer; only revealed on the screen of
	# whoever lands a hit (MapleStory-style). The hide timer runs locally per peer.
	if health_bar:
		health_bar.hide()
		_health_bar_hide_timer = Timer.new()
		_health_bar_hide_timer.name = "HealthBarHideTimer"
		_health_bar_hide_timer.one_shot = true
		_health_bar_hide_timer.wait_time = HEALTH_BAR_VISIBLE_DURATION
		add_child(_health_bar_hide_timer)
		_health_bar_hide_timer.timeout.connect(_on_health_bar_hide_timeout)


func _process(delta: float) -> void:
	if _is_being_cleaned_up:
		return
		
	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		state_machine.process_frame(delta)
		if body_hitbox.monitoring:
			var overlapping_bodies = body_hitbox.get_overlapping_bodies()
			for body in overlapping_bodies:
				if body is MultiplayerPlayerV2:
					damage_on_overlap(body)

		# Throttled mark-state check — broadcasts only on change.
		_mark_check_accum += delta
		if _mark_check_accum >= _MARK_CHECK_INTERVAL:
			_mark_check_accum = 0.0
			_refresh_mark_indicator()

		# [Boss] Telegraphed special-attack scheduler (server-only, gated to bosses).
		if enemy_data != null and enemy_data.is_boss:
			_boss_special_tick()


func _physics_process(delta: float) -> void:
	if _is_being_cleaned_up:
		return

	if multiplayer.has_multiplayer_peer() and multiplayer.is_server():
		state_machine.process_physics(delta)


# --- Mark indicator -------------------------------------------------------

## [Server] Scans the mark metas in priority order and broadcasts a change to
## the floating indicator when the active mark differs from what's shown.
## Reads absolute expiry timestamps so it transparently handles refresh (mark
## re-applied), consume (Mark of the Hunt cleared on crit), and expiry — no
## per-mark-site hooks needed.
func _refresh_mark_indicator() -> void:
	var now: int = Time.get_ticks_msec()
	var found_idx: int = -1
	var found_color: Color = Color.WHITE
	var found_shape: String = "diamond"
	var i: int = 0
	for key in _MARK_META_COLORS:
		if has_meta(key) and now < int(get_meta(key)):
			found_idx = i
			found_color = _MARK_META_COLORS[key]
			found_shape = _MARK_META_SHAPES.get(key, "diamond")
			break
		i += 1

	if found_idx == _current_mark_idx:
		return  # no change — don't re-broadcast
	_current_mark_idx = found_idx
	# call_local so the host (also a client) updates its own indicator too.
	sync_mark_indicator.rpc(found_idx >= 0, found_color, found_shape)


## [Server → all peers] Toggles + colors + shapes the floating mark indicator.
## Routed as a node-addressed RPC because enemies are MultiplayerSpawner-
## replicated (same path on every peer) — unlike bots, which need autoload
## routing.
@rpc("authority", "call_local", "reliable")
func sync_mark_indicator(active: bool, color: Color, shape: String = "diamond") -> void:
	if mark_indicator == null or not is_instance_valid(mark_indicator):
		return
	if active:
		mark_indicator.set_mark(color, shape)
	else:
		mark_indicator.clear_mark()


## [Server] Play the DoT tick visual (icon + particle burst + poison tint) on EVERY
## peer. Each DoT loop (BleedDot, the burn loops, Envenom/Hemorrhage/Barbed Shot)
## calls this once per tick with `dot_type` = "bleed" / "poison" / "burn". Cosmetic;
## the actual damage is the loop's own take_damage. Safe to call on a dead/despawning
## enemy (the RPC just toggles a local child).
func play_dot(dot_type: String) -> void:
	if not multiplayer.is_server():
		return
	_sync_dot_tick.rpc(dot_type)


## [Server → all peers] Plays the DoT tick visual locally on each peer.
@rpc("authority", "call_local", "unreliable")
func _sync_dot_tick(dot_type: String) -> void:
	if dot_visuals != null and is_instance_valid(dot_visuals):
		dot_visuals.tick(dot_type, animated_sprite)


func on_enemy_damaged(amount: int, source: Node) -> void:
	var player_id = null
	# PR 6 fix: DOT/environmental damage may pass null as source (or a
	# component whose owner has despawned). Guard before dereferencing.
	if source != null and is_instance_valid(source):
		if source is MultiplayerPlayerV2:
			player_id = source.player_id
		elif source.owner != null and is_instance_valid(source.owner) and "player_id" in source.owner:
			player_id = source.owner.player_id
	if player_id != null:
		damage_by_player[player_id] = damage_by_player.get(player_id, 0) + amount
		if multiplayer.is_server():
			for pid in _get_real_players_on_same_map():
				client_show_name_label.rpc_id(pid)
			# MapleStory-style: reveal the overhead HP bar only on the screen of
			# the player who landed the hit. Bots have negative peer ids and no
			# client, so skip them; rpc_id(1) runs locally for a host attacker.
			if player_id > 0:
				client_show_health_bar.rpc_id(player_id)

	# Provoked: a passive enemy wakes up and chases whoever just hit it. An
	# already-aggressive enemy retargets onto its current attacker.
	var attacker := _resolve_character(source)
	if is_valid_target(attacker):
		current_target = attacker

	# Play a brief stagger state if this enemy has a "hit" animation. The
	# attack state is exempt so a swing already in progress still lands.
	if multiplayer.is_server() and not health_component.is_dead:
		_try_enter_hit_state()


## Transitions the enemy into the "hit" stagger state when:
##  - the SpriteFrames contains a "hit" clip (slimes don't),
##  - the enemy isn't mid-swing (attack states should complete), and
##  - the enemy isn't already in the hit state.
func _try_enter_hit_state() -> void:
	if state_machine == null:
		return
	var hit_state: Node = state_machine.get_node_or_null("hit")
	if hit_state == null or state_machine.current_state == hit_state:
		return
	if state_machine.current_state is EnemyAttackState:
		return
	# A telegraphed boss special is committed — chip damage must not cancel the
	# windup (else focus fire would stop the special ever landing).
	var boss_special_state: Node = state_machine.get_node_or_null("boss_special")
	if boss_special_state != null and state_machine.current_state == boss_special_state:
		return
	if enemy_data == null or enemy_data.sprite_frames == null:
		return
	if not enemy_data.sprite_frames.has_animation("hit"):
		return
	state_machine.change_state(hit_state)


func _on_enemy_died(_killer: Node) -> void:
	call_deferred("_deferred_death_processing", _killer)


func _deferred_death_processing(_killer: Node) -> void:
	if _is_being_cleaned_up:
		return

	# Clear any mark metas + hide the indicator immediately on death so a
	# pooled-and-respawned enemy doesn't briefly show a stale mark. (The
	# timestamps would expire on their own, but a respawn within the mark
	# window could otherwise flash the old marker.)
	for key in _MARK_META_COLORS:
		if has_meta(key):
			remove_meta(key)
	if _current_mark_idx != -1:
		_current_mark_idx = -1
		sync_mark_indicator.rpc(false, Color.WHITE, "diamond")

	#print("Enemy died. Killer: ", _killer, " Type: ", typeof(_killer))

	var total_damage = 0
	for dmg in damage_by_player.values():
		total_damage += dmg
		
	var killer_player_id = -1
	# PR 6 fix: mirror on_enemy_damaged's source-resolution. DOT/bleed
	# kills pass MultiplayerPlayerV2 directly as the killer; normal combat
	# hits pass a component whose .owner is the player root.
	if _killer != null and is_instance_valid(_killer):
		if _killer is MultiplayerPlayerV2:
			killer_player_id = _killer.player_id
		elif _killer.owner is MultiplayerPlayerV2:
			killer_player_id = _killer.owner.player_id

	var killer_party_id = PartyManager.get_player_party_id(killer_player_id)
	#print("Determined killer_party_id: ", killer_party_id)
	
	var players_to_reward: Array[int] = []
	var eligible_player_ids_for_drops: Array[int] = []
	var party_exp_bonus_multiplier = 1.0
	var non_damage_dealer_exp_percentage = 0.25 # 25% of base EXP for non-damage dealers in party

	if killer_party_id != -1:
		# Killer is in a party, distribute EXP to party members on the same map
		var all_party_members: Array[int] = PartyManager.get_party_members(killer_player_id)
		var players_on_same_map: Array = _get_players_on_same_map()
		for member_id in all_party_members:
			if member_id in players_on_same_map:
				players_to_reward.append(member_id)
		#print("Players in party to reward (same map only): ", players_to_reward)
		# Only party members on the same map are eligible for drops
		eligible_player_ids_for_drops = players_to_reward
		# Scaling party EXP bonus: +10% per additional member (2p=1.1x, 3p=1.2x, 4p=1.3x, etc.)
		var party_size: int = players_to_reward.size()
		if party_size > 1:
			party_exp_bonus_multiplier = 1.0 + (0.1 * (party_size - 1))
		#print("Party EXP bonus multiplier: ", party_exp_bonus_multiplier)
		var total_party_damage = 0
		for member_id in players_to_reward:
			if damage_by_player.has(member_id):
				total_party_damage += damage_by_player[member_id]
		#print("Total party damage: ", total_party_damage)
		
		for member_id in players_to_reward:
			var exp_amount = 0
			var player_node = PlayerManager.get_player_node(member_id)
			if not player_node:
				#print("Could not find player node for member ID: ", member_id)
				continue

			if damage_by_player.has(member_id) and total_party_damage > 0:
				# Player dealt damage, calculate share based on damage
				var share = float(damage_by_player[member_id]) / total_party_damage
				exp_amount = int(experience_reward * share * party_exp_bonus_multiplier)
				#print("Member %d (damage dealer) share: %f, base exp: %d, bonus: %f, final exp: %d" % [member_id, share, experience_reward, party_exp_bonus_multiplier, exp_amount])
			else:
				# Player is in party but didn't deal damage, give a fixed percentage
				exp_amount = ceili(experience_reward * non_damage_dealer_exp_percentage * party_exp_bonus_multiplier)
				#print("Member %d (non-damage dealer) base exp: %d, non-damage : %f, bonus: %f, final exp: %d" % [member_id, experience_reward, non_damage_dealer_exp_percentage, party_exp_bonus_multiplier, exp_amount])
			
			player_node.gain_experience(exp_amount)
			# Track kill for quest objectives
			QuestManager.record_enemy_kill(player_node.username, monster_name)
			# Share kill-mastery XP with party members who fought (the killer already
			# got theirs in combat.gd). Otherwise grouping SLOWS mastery — you land
			# fewer killing blows. Goes to each member's OWN equipped disciplines.
			if member_id != killer_player_id and damage_by_player.has(member_id):
				var _mc = player_node.get("weapon_mastery_component")
				var _cc = player_node.get("combat_component")
				if _mc and _cc and player_node.level_component:
					var _kxp: int = WeaponMasteryComponent.compute_kill_xp(monster_level, player_node.level_component.level)
					var _pd: int = _cc._active_weapon_discipline()
					if _pd != -1:
						_mc.grant_mastery_xp_server(_pd, _kxp)
					var _sd: int = _cc._secondary_weapon_discipline()
					if _sd != -1 and _sd != _pd:
						_mc.grant_mastery_xp_server(_sd, _kxp)
			#print("PID: %s (Party) gained %s exp from %s" % [str(member_id), str(exp_amount), name])
	else:
		# No party, distribute EXP only to damage dealers
		players_to_reward.append_array(damage_by_player.keys())
		eligible_player_ids_for_drops = players_to_reward
		#print("No party. Players to reward: ", players_to_reward)
		for player_id in players_to_reward:
			var share = float(damage_by_player[player_id]) / total_damage
			var exp_amount = int(experience_reward * share)
			var player_node = PlayerManager.get_player_node(player_id)
			if player_node and player_node.has_method("gain_experience"):
				#print("PID: %s did %s%% damage to %s gaining %s exp" % [str(player_id), share * 100, name, str(exp_amount)])
				player_node.gain_experience(exp_amount)
				# Track kill for quest objectives
				QuestManager.record_enemy_kill(player_node.username, monster_name)
				
	# Spawn drops for all eligible players
	if not eligible_player_ids_for_drops.is_empty():
		_spawn_drops(eligible_player_ids_for_drops)
		
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	
	# When a spawner is managing this enemy it drives the pool cycle via
	# ready_for_pooling -> _spawn_enemy (which also picks a fresh spawn
	# marker). The direct timers below are only for self-respawning enemies
	# placed manually in the scene — otherwise pool_reset would teleport the
	# enemy back to initial_position (≈ the spawn container's origin for
	# pooled enemies) and drop them through the floor.
	if respawnable and ready_for_pooling.get_connections().is_empty():
		get_tree().create_timer(post_death_delay).timeout.connect(pool_deactivate)
		get_tree().create_timer(respawn_delay).timeout.connect(pool_reset)

	# On dedicated server, AnimatedSprite2D is stripped, so we can't wait on animation_finished.
	# Respawnable: trigger pooling after the post-death delay.
	# Non-respawnable: linger briefly, then free (MultiplayerSpawner despawns the node on clients).
	if OS.has_feature("dedicated_server"):
		if respawnable:
			get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)
		else:
			var corpse_linger := post_death_delay + randf_range(5.0, 10.0)
			get_tree().create_timer(corpse_linger).timeout.connect(queue_free)


func _spawn_drops(eligible_player_ids: Array[int]) -> void:
	if not multiplayer.is_server():
		return
	
	# Server needs to find the map this enemy is in
	var map_instance = null
	
	# Try to find map by walking up the tree to find a parent map container
	var parent = get_parent()
	while parent:
		if parent.name.begins_with("Map_"):
			map_instance = parent
			break
		parent = parent.get_parent()
	
	# If not found by walking tree, try to get from current scene structure
	if not map_instance:
		var root = get_tree().current_scene
		if root:
			var maps_node = root.get_node_or_null("Maps")
			if maps_node:
				# Find any Map_* child
				for child in maps_node.get_children():
					if child.name.begins_with("Map_"):
						map_instance = child
						break
	
	if not map_instance:
		push_error("EnemyBase: Could not determine map instance for enemy %s" % name)
		return

	# Find the GlobalDropHandler specific to this map
	var drop_handler = map_instance.get_node_or_null("GlobalDropHandler")
	if not drop_handler:
		push_error("EnemyBase: GlobalDropHandler not found in map %s" % map_instance.name)
		return
	
	for drop_resource in item_drops:
		if drop_resource == null:
			continue
		
		# Check if this drop should occur
		if not drop_resource.should_drop():
			continue
		
		# Get the item data
		var item = drop_resource.get_item_data()
		if item == null:
			push_warning("Item '%s' not found in ResourceManager" % drop_resource.item_name)
			continue
		
		# Determine stack amount
		var amount = drop_resource.get_drop_amount()
		
		# Position it at enemy's location with slight offset to prevent stacking
		var offset = Vector2(randf_range(-10, 10), randf_range(-10, 0))
		var spawn_pos = global_position + offset
		
		# Delegate spawning to GlobalDropHandler which handles RPCs and map filtering
		drop_handler.create_dropped_item(item, amount, spawn_pos, eligible_player_ids, map_instance)
		
		#print("Enemy '%s' dropped %dx %s for eligible players: %s" % [name, amount, item.name, str(eligible_player_ids)])


@rpc("any_peer", "call_local", "reliable")
func client_show_name_label():
	name_label.show()
	
@rpc("any_peer", "call_local", "reliable")
func client_hide_name_label():
	name_label.hide()


## [Server → the hitting client only] Reveal this enemy's overhead HP bar and
## (re)start the hide countdown. Sent per-attacker so each player only sees the
## bar of enemies THEY are fighting.
@rpc("any_peer", "call_local", "reliable")
func client_show_health_bar() -> void:
	if not health_bar or not is_instance_valid(health_bar):
		return
	health_bar.show()
	if _health_bar_hide_timer:
		_health_bar_hide_timer.start()


## [Server → real players on map] Force the HP bar hidden immediately (death /
## pooling), independent of the hide countdown.
@rpc("any_peer", "call_local", "reliable")
func client_hide_health_bar() -> void:
	if _health_bar_hide_timer:
		_health_bar_hide_timer.stop()
	if health_bar and is_instance_valid(health_bar):
		health_bar.hide()


func _on_health_bar_hide_timeout() -> void:
	if health_bar and is_instance_valid(health_bar):
		health_bar.hide()

# --- Object Pooling Methods ---

## Deactivates the enemy, making it invisible and non-interactive.
## Called by the spawner when the enemy is returned to the pool.
func pool_deactivate() -> void:
	if _is_being_cleaned_up:
		return

	damage_by_player.clear()
	current_target = null
	# Clear any proximity-sleep bookkeeping so a respawn starts from a clean,
	# awake state (the scanner re-sleeps it if still agentless).
	_activation_asleep = false
	visible = false
	set_process(false)
	set_physics_process(false)
	collision_shape.set_deferred("disabled", true)
	attack_hitbox.monitoring = false
	body_hitbox.monitoring = false
	
	# CRITICAL: Disable the synchronizer to stop sending delta updates
	var sync = get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_process_mode(Node.PROCESS_MODE_DISABLED)
	
	# Move far away to prevent any lingering interactions.
	global_position = Vector2(INF, INF)
	
	if multiplayer.is_server():
		for pid in _get_real_players_on_same_map():
			client_hide_name_label.rpc_id(pid)
			client_hide_health_bar.rpc_id(pid)


func pool_reset() -> void:
	if _is_being_cleaned_up:
		return

	current_target = null
	_attack_cooldown_until = 0
	# A freshly respawned enemy is awake; the scanner decides on the next tick.
	_activation_asleep = false

	# [Boss] Reset phase/enrage/special state so a pooled-and-respawned boss
	# starts the fight clean instead of inheriting the previous run's buffs.
	_boss_damage_mult = 1.0
	_boss_attack_speed_mult = 1.0
	_boss_phase_idx = -1
	_boss_enraged = false
	_boss_special_pending = false
	_pending_special_attack = null
	_pending_special_idx = -1
	if enemy_data != null and enemy_data.is_boss:
		_init_boss_attacks()

	if respawnable:
		global_position = initial_position
	
	# Reset health and death state using the component.
	if health_component:
		health_component.respawn()

	# Re-enable visuals, logic, and physics.
	visible = true
	set_process(true)
	set_physics_process(true)
	collision_shape.set_deferred("disabled", false)
	attack_hitbox.monitoring = true
	body_hitbox.monitoring = true
	
	# CRITICAL: Re-enable the synchronizer to resume sending delta updates
	var sync = get_node_or_null("MultiplayerSynchronizer")
	if sync:
		sync.set_process_mode(Node.PROCESS_MODE_INHERIT)


# === PROXIMITY ACTIVATION (ADR 0007) ============================================
# Driven by the MapManager scanner, server-side only. Lets resident maps stay
# loaded without paying for AI ticks on enemies no agent is near.

## True when the activation scanner may toggle this enemy — a live, visible,
## non-pooled, non-cleanup body on the server. Pooled/dead enemies (visible ==
## false, parked offscreen) are excluded so a wake never revives a corpse.
func is_activation_eligible() -> bool:
	if _is_being_cleaned_up:
		return false
	if not visible:
		return false # pool-deactivated (dead / awaiting respawn)
	if health_component and health_component.current_health <= 0:
		return false
	return true


## True while the enemy is hunting a target. Engaged enemies are kept awake
## regardless of distance, so a kited or DoT-bleeding target never freezes
## mid-fight even if it slips past the activation radius.
func is_engaged() -> bool:
	return is_valid_target(current_target)


## [Server] Pause AI while no agent is near. Idempotent. Does NOT touch
## visibility, collision, or the synchronizer — a sleeping enemy is still a
## valid, visible, static body; it just stops thinking until woken.
func activation_sleep() -> void:
	if _activation_asleep or not is_activation_eligible():
		return
	_activation_asleep = true
	set_process(false)
	set_physics_process(false)


## [Server] Resume AI when an agent comes near. Idempotent. Only re-activates
## enemies THIS system put to sleep, never a pooled corpse.
func activation_wake() -> void:
	if not _activation_asleep:
		return
	_activation_asleep = false
	set_process(true)
	set_physics_process(true)


func _update_facing() -> void:
	if _is_being_cleaned_up:
		return

	if velocity.x != 0:
		facing_direction = 1 if velocity.x > 0 else -1
		if animated_sprite and is_instance_valid(animated_sprite):
			animated_sprite.flip_h = facing_direction < 0


func _on_body_hitbox_body_entered(body: Node) -> void:
	if _is_being_cleaned_up:
		return
		
	if not multiplayer.is_server():
		return
		
	damage_on_overlap(body)


func _get_a_coefficient(level_diff: int) -> float:
	# Damage is modified by 3% for every level of difference (softened from 5% on
	# 2026-06-02 so a player a few levels ABOVE a mob isn't over-rewarded — a
	# near-level mob should still bite). If player is 10 levels lower (diff = -10),
	# monster deals 30% more damage (A = 1.3); 10 levels higher → 30% less (A = 0.7).
	var modifier = 1.0 - (level_diff * 0.03)
	return clamp(modifier, 0.1, 5.0) # Clamp damage from 10% to 500%


func _get_b_coefficient(level_diff: int) -> float:
	if level_diff >= 0: return 1.00
	if level_diff == -1: return 0.99
	if level_diff == -2: return 0.98
	if level_diff == -3: return 0.97
	if level_diff == -4: return 0.96
	if level_diff == -5: return 0.95
	if level_diff == -6: return 0.94
	if level_diff == -7: return 0.93
	if level_diff == -8: return 0.92
	if level_diff == -9: return 0.91
	if level_diff == -10: return 0.90
	if level_diff == -11: return 0.88
	if level_diff == -12: return 0.86
	if level_diff == -13: return 0.84
	if level_diff == -14: return 0.82
	if level_diff == -15: return 0.80
	if level_diff == -16: return 0.78
	if level_diff == -17: return 0.76
	if level_diff == -18: return 0.74
	if level_diff == -19: return 0.72
	if level_diff == -20: return 0.70
	if level_diff == -21: return 0.68
	if level_diff == -22: return 0.66
	if level_diff == -23: return 0.64
	if level_diff == -24: return 0.62
	if level_diff == -25: return 0.60
	if level_diff == -26: return 0.58
	if level_diff == -27: return 0.56
	if level_diff == -28: return 0.54
	if level_diff == -29: return 0.52
	return 0.50 # -30 or lower


func damage_on_overlap(body: Node):
	if not stats_component:
		push_warning("Enemy %s is missing a StatsComponent! Cannot calculate damage." % name)
		return

	if body.has_meta("is_invisible") and body.get_meta("is_invisible"):
		return

	if body.has_node("Components/Health"):
		var health: HealthComponent = body.get_node("Components/Health")
		var player_stats: StatsComponent = body.get_node("Components/Stats")
		var player_level_comp: LevelingComponent = body.get_node("Components/Leveling")

		if health.is_dead or health.is_invulnerable:
			return

		# --- New Monster Damage Calculation ---
		# Magic attackers (is_magic_attacker) scale on MAGICATTACK and are mitigated
		# by the target's MAGICDEFENSE; everyone else uses WEAPONATTACK vs DEFENSE.
		# This is what makes "magic armor" (MAGICDEFENSE) matter on the player side.
		var is_magic: bool = enemy_data != null and enemy_data.is_magic_attacker
		var att_stat: int = Constants.StatType.MAGICATTACK if is_magic else Constants.StatType.WEAPONATTACK
		var def_stat: int = Constants.StatType.MAGICDEFENSE if is_magic else Constants.StatType.DEFENSE
		var monster_att = stats_component.stats.get(att_stat).total_value
		# [Boss] Phase + enrage damage scaling on the boss's normal attack. Returns
		# 1.0 for every non-boss enemy (and an un-phased, un-enraged boss).
		monster_att = int(round(float(monster_att) * _boss_outgoing_mult()))
		var player_def = player_stats.stats.get(def_stat).total_value
		var level_diff = player_level_comp.level - monster_level

		var a = _get_a_coefficient(level_diff)
		var b = _get_b_coefficient(level_diff)

		# --- Hit / Evasion roll (added 2026-06-02) ---
		# Mirrors CombatComponent._execute_hit's hit-chance so the player's
		# defensive stats apply to INCOMING hits too, not just outgoing ones.
		# Previously the enemy dealt damage unconditionally — it ignored the
		# player's EVASIONCHANCE (dagger passive / gear) entirely. Now:
		#   base 95% at even level, ±3% per level of gap (enemy is the attacker,
		#   so its accuracy improves when IT is higher level, i.e. -level_diff),
		#   + the enemy's ACCURACY stat (0 by default — enemies have none),
		#   − the player's EVASIONCHANCE. Floor 5%, ceil 100%.
		# On a dodge: no damage, no knockback, and the player's on_dodge passive
		# procs fire (the proc hook existed but nothing triggered it before).
		var enemy_accuracy: float = 0.0
		if stats_component.stats.has(Constants.StatType.ACCURACY):
			enemy_accuracy = float(stats_component.stats[Constants.StatType.ACCURACY].total_value)
		var player_evasion: float = 0.0
		if player_stats.stats.has(Constants.StatType.EVASIONCHANCE):
			player_evasion = float(player_stats.stats[Constants.StatType.EVASIONCHANCE].total_value)
		var hit_chance: float = clampf(95.0 + (-level_diff * 3.0) + enemy_accuracy - player_evasion, 5.0, 100.0)
		if randf() * 100.0 > hit_chance:
			var dodger_ability = body.get_node_or_null("Components/Ability")
			if dodger_ability and dodger_ability.has_method("try_trigger_procs"):
				dodger_ability.try_trigger_procs("on_dodge", self, {"attacker": self})
			# Evasion payoff (rogue identity): a dodge primes the next strike to crit,
			# and pops a MISS number so the dodge reads as a win, not a non-event.
			body.set_meta("evasion_crit_until_ms", Time.get_ticks_msec() + EVASION_CRIT_WINDOW_MS)
			if is_instance_valid(health):
				# Consume the contact tick (i-frame window) so this overlap doesn't
				# re-roll every frame — stops the MISS spam AND makes evasion actually
				# reduce sustained contact damage (a dodge = a real 0-damage tick).
				if health.has_method("trigger_dodge_invulnerability"):
					health.trigger_dodge_invulnerability()
				if health.has_method("show_dodge"):
					health.show_dodge()
			return

		# Defense mitigation — DIMINISHING RETURNS on effective defense.
		# (Reworked 2026-06-02.) The old model subtracted a defense term that was
		# hard-capped at 0.68-0.80 x monster_att, so mitigation maxed out at very
		# low defense and any extra (gear, CON, Bulwark Stance) was wasted. The
		# ratio model def/(def+attack) means MORE defense always reduces damage,
		# with strong diminishing returns, asymptotically approaching MAX_DEFENSE_
		# MITIGATION (you always take at least 1 - cap of the hit). `b` keeps
		# scaling defense DOWN when the player is under-levelled vs the monster.
		var eff_def: float = maxf(0.0, b * float(player_def))
		var mitigation: float = eff_def / (eff_def + maxf(1.0, DEFENSE_SOFTNESS * float(monster_att)))
		mitigation = minf(mitigation, MAX_DEFENSE_MITIGATION)

		# Base hit varies 85%-100% of monster attack, then level modifier `a` and
		# the defense mitigation apply.
		var min_damage: int = maxi(1, roundi(a * 0.85 * float(monster_att) * (1.0 - mitigation)))
		var max_damage: int = maxi(min_damage, roundi(a * float(monster_att) * (1.0 - mitigation)))

		var final_damage = randi_range(min_damage, max_damage)

		health.take_damage(final_damage, self)

		# Knockback, gated by the player's knockback resist.
		var knockback_dir = - body.facing_direction
		var knockback_strength = 120.0
		var knockback_lift = -100.0
		var knockback_vec = Vector2(knockback_dir * knockback_strength, knockback_lift)
		if body.has_method("apply_knockback") and StatsComponent.rolls_knockback(player_stats, knockback_strength):
			body.apply_knockback(knockback_vec)


func apply_knockback(knockback: Vector2) -> void:
	if _is_being_cleaned_up:
		return
	# Invincible training dummies stay rooted — ignore knockback impulses.
	if health_component and health_component.invincible:
		return
		
	velocity.x = knockback.x
	velocity.y = knockback.y


func _on_animation_finished() -> void:
	if _is_being_cleaned_up:
		return
		
	# If the death animation has just finished, signal to the spawner that this
	# enemy instance is ready to be deactivated and returned to the pool, after a short delay.
	if animated_sprite.animation == "death": # Assumes death animation is named "death"
		if respawnable:
			# Create a one-shot timer to wait before disappearing.
			get_tree().create_timer(post_death_delay).timeout.connect(emit_ready_for_pooling)
		else:
			# Non-respawnable enemies: corpse lingers 5-10s after death anim, then frees.
			get_tree().create_timer(randf_range(5.0, 10.0)).timeout.connect(queue_free)


func emit_ready_for_pooling() -> void:
	"""Emits the signal that the spawner is waiting for."""
	if _is_being_cleaned_up:
		return
	ready_for_pooling.emit()


func cleanup_before_removal():
	#print("Cleaning up enemy: ", name)
	_is_being_cleaned_up = true
	
	# Stop all processing
	set_process(false)
	set_physics_process(false)
	
	# Disconnect signals to prevent callbacks during cleanup
	if health_component and health_component.died.is_connected(_on_enemy_died):
		health_component.died.disconnect(_on_enemy_died)
	
	if body_hitbox and body_hitbox.body_entered.is_connected(_on_body_hitbox_body_entered):
		body_hitbox.body_entered.disconnect(_on_body_hitbox_body_entered)
	
	if animated_sprite and animated_sprite.animation_finished.is_connected(_on_animation_finished):
		animated_sprite.animation_finished.disconnect(_on_animation_finished)
	
	# Stop state machine processing
	if is_instance_valid(state_machine):
		if state_machine.has_method("cleanup"):
			state_machine.cleanup()
		state_machine.set_process(false)
	
	# Disable collision and monitoring
	if collision_shape:
		collision_shape.set_deferred("disabled", true)
	if attack_hitbox:
		attack_hitbox.monitoring = false
	if body_hitbox:
		body_hitbox.monitoring = false


# Override _exit_tree to handle cleanup
func _exit_tree():
	cleanup_before_removal()


func _get_players_on_same_map() -> Array:
	if not multiplayer.is_server(): return []
	
	# Try to find map by walking up the tree to find a parent map container
	var parent = get_parent()
	var map_name = ""
	while parent:
		if parent.name.begins_with("Map_"):
			map_name = parent.name.replace("Map_", "")
			break
		parent = parent.get_parent()
	
	if map_name != "":
		return MapManager.get_players_on_map(map_name)
	return []


func _get_real_players_on_same_map() -> Array:
	if not multiplayer.is_server(): return []
	var parent = get_parent()
	var map_name = ""
	while parent:
		if parent.name.begins_with("Map_"):
			map_name = parent.name.replace("Map_", "")
			break
		parent = parent.get_parent()
	if map_name != "":
		return MapManager.get_real_players_on_map(map_name)
	return []


# --- AI: targeting & combat ----------------------------------------------

## Creates and attaches the runtime "chase" AI state if it isn't already in the
## state machine. Done in code so every enemy scene gets the behaviour without
## per-scene wiring; sibling states are resolved by name at transition time.
func _ensure_chase_state() -> void:
	if state_machine == null or state_machine.has_node("chase"):
		return
	var chase := Node.new()
	chase.set_script(_CHASE_STATE_SCRIPT)
	chase.name = "chase"
	# Reuse the walk/patrol animation while pursuing a target.
	chase.animation_name = "patrol"
	state_machine.add_child(chase)


## Creates and attaches the runtime "hit" stagger state. Entered from
## on_enemy_damaged when the enemy has a "hit" animation; injected unconditionally
## so the state-machine node lookup ("hit") works on every enemy.
func _ensure_hit_state() -> void:
	if state_machine == null or state_machine.has_node("hit"):
		return
	var hit := Node.new()
	hit.set_script(_HIT_STATE_SCRIPT)
	hit.name = "hit"
	hit.animation_name = "hit"
	state_machine.add_child(hit)


## [Boss] Creates and attaches the runtime "boss_special" state — the telegraphed
## AoE windup. Only injected for bosses (gated by the caller). animation_name is
## left empty: bosses reuse a base enemy's SpriteFrames, which has no dedicated
## windup clip, so the sprite holds its current pose during the telegraph.
func _ensure_boss_special_state() -> void:
	if state_machine == null or state_machine.has_node("boss_special"):
		return
	var s := Node.new()
	s.set_script(_BOSS_SPECIAL_STATE_SCRIPT)
	s.name = "boss_special"
	s.animation_name = ""
	state_machine.add_child(s)


## Resolves a damage source (a player/bot node, or an ability/projectile owned
## by one) down to the player or bot character node behind it.
func _resolve_character(source: Node) -> Node2D:
	if source is MultiplayerPlayerV2:
		return source as MultiplayerPlayerV2
	if source != null and source.owner is MultiplayerPlayerV2:
		return source.owner as MultiplayerPlayerV2
	return null


## True when `node` is a living, visible player or bot this enemy may attack.
func is_valid_target(node) -> bool:
	if not is_instance_valid(node):
		return false
	if not node is MultiplayerPlayerV2:
		return false
	if node.has_meta("is_invisible") and node.get_meta("is_invisible"):
		return false
	var health := node.get_node_or_null("Components/Health") as HealthComponent
	if health == null or health.is_dead:
		return false
	return true


## Nearest living player/bot on this enemy's map within its detection radius,
## or null when none are in sight.
func acquire_target() -> Node2D:
	if not multiplayer.is_server() or enemy_data == null:
		return null
	var best: Node2D = null
	var best_dist: float = enemy_data.detection_radius
	for pid in _get_players_on_same_map():
		var node: Node2D = PlayerManager.get_player_node(pid)
		if not is_valid_target(node):
			continue
		var d: float = global_position.distance_to(node.global_position)
		if d < best_dist:
			best_dist = d
			best = node
	return best


## The target the idle/patrol states should chase, or null to keep wandering.
## A passive enemy only returns a target it was already provoked by; an
## aggressive enemy actively scans for one in sight.
func get_aggro_target() -> Node2D:
	if is_valid_target(current_target):
		return current_target
	current_target = null
	if enemy_data and enemy_data.is_aggressive:
		current_target = acquire_target()
	return current_target


## True when this enemy has a melee attack state — i.e. it swings rather than
## simply charging into its target.
func has_attack_state() -> bool:
	return state_machine != null and state_machine.has_node("slash_attack")


func can_attack() -> bool:
	return Time.get_ticks_msec() >= _attack_cooldown_until


func start_attack_cooldown() -> void:
	var cd: float = enemy_data.attack_cooldown if enemy_data else 1.4
	# [Boss] Phase + enrage attack-speed divisor (>1 = faster). 1.0 otherwise.
	var speed_mult: float = _boss_attack_speed_mult
	if enemy_data != null and enemy_data.is_boss and _boss_enraged:
		speed_mult *= maxf(0.01, enemy_data.enrage_attack_speed_mult)
	if speed_mult > 0.0:
		cd /= speed_mult
	_attack_cooldown_until = Time.get_ticks_msec() + int(cd * 1000.0)


## Points facing (and the sprite) in a horizontal direction (-1 or +1).
func face_direction(dir: int) -> void:
	if dir == 0:
		return
	facing_direction = dir
	if animated_sprite and is_instance_valid(animated_sprite):
		animated_sprite.flip_h = facing_direction < 0


## Points facing at a world position. Used while attacking, when velocity is
## ~0 and the velocity-based _update_facing won't fire.
func face_toward(pos: Vector2) -> void:
	var dx: float = pos.x - global_position.x
	if absf(dx) < 1.0:
		return
	face_direction(1 if dx > 0 else -1)


# --- Boss encounter logic -------------------------------------------------
# All of the following only runs when enemy_data.is_boss is true and only on the
# server. Phase transitions, enrage, and special-attack scheduling are
# server-authoritative; the telegraph + roar flash are cosmetic broadcasts routed
# through MapManager (an autoload that resolves on every peer — including bot
# hosts, which have no client and can't be node-addressed by RPC).

## The combined outgoing-damage multiplier for the boss's normal + special hits.
## 1.0 for non-bosses and an un-phased, un-enraged boss.
func _boss_outgoing_mult() -> float:
	if enemy_data == null or not enemy_data.is_boss:
		return 1.0
	var m: float = _boss_damage_mult
	if _boss_enraged:
		m *= maxf(0.0, enemy_data.enrage_damage_mult)
	return m


## [Server] Reacts to every HP change on a boss: fires any newly-crossed phase
## thresholds (in order, once each) and the enrage trigger (once).
func _on_boss_health_changed(current: int, maximum: int) -> void:
	if not multiplayer.is_server():
		return
	if enemy_data == null or not enemy_data.is_boss:
		return
	if health_component == null or health_component.is_dead:
		return
	if maximum <= 0:
		return
	var frac: float = float(current) / float(maximum)

	# Phase transitions — fire each newly-passed index in order.
	var new_idx: int = _BOSS_PHASE_LOGIC.compute_phase_index(_boss_phase_idx, frac, enemy_data.phase_health_thresholds)
	while new_idx > _boss_phase_idx:
		_boss_phase_idx += 1
		_enter_boss_phase(_boss_phase_idx)

	# Enrage — independent, once.
	if not _boss_enraged and _BOSS_PHASE_LOGIC.should_enrage(frac, enemy_data.enrage_health_threshold):
		_boss_enraged = true
		boss_phase_changed.emit(-2)  # sentinel: an enrage "phase" for listeners
		_broadcast_boss_roar(Color(1.0, 0.25, 0.2))


## [Server] Applies a phase's effects: bumps the boss's damage + attack speed,
## emits boss_phase_changed, and broadcasts a cosmetic roar flash to every peer.
func _enter_boss_phase(idx: int) -> void:
	_boss_damage_mult += _BOSS_PHASE_DAMAGE_STEP
	_boss_attack_speed_mult += _BOSS_PHASE_ATTACK_SPEED_STEP
	boss_phase_changed.emit(idx)
	_broadcast_boss_roar(Color(1.0, 0.6, 0.1))


## [Server] Cosmetic, all-peer expanding ring at the boss's feet — the roar flash
## (phase/enrage) and the special's telegraph both use it. show_ground_zone_everywhere
## (not broadcast_ground_zone) so the HOST sees it too: the boss has no
## authoritative GroundZone node to render locally. No-op off a resolvable map.
func broadcast_telegraph_ring(pos: Vector2, radius: float, duration: float, color: Color) -> void:
	var map_id: String = _get_map_id()
	if map_id == "":
		return
	MapManager.show_ground_zone_everywhere(map_id, pos, radius, duration, color)


## [Server] All-peer (incl. host) RECTANGULAR ground telegraph — the boss slam
## band. Centered on `pos`, `rect_size` is full width × height. Reads correctly on
## the 2D platformer plane where a circle does not.
func broadcast_telegraph_rect(pos: Vector2, rect_size: Vector2, duration: float, color: Color) -> void:
	var map_id: String = _get_map_id()
	if map_id == "":
		return
	MapManager.show_ground_zone_shaped_everywhere(map_id, pos, 1, 0.0, rect_size, duration, color)


func _broadcast_boss_roar(color: Color) -> void:
	var radius: float = enemy_data.special_attack_radius if enemy_data != null else 120.0
	broadcast_telegraph_ring(global_position, radius, 0.5, color)


## [Server] Builds + caches the boss's attack list (authored or legacy-synthesised)
## and seeds each attack's cooldown so the boss doesn't special the instant it spawns.
func _init_boss_attacks() -> void:
	var list: Array[BossAttackData] = []
	if enemy_data != null:
		list = enemy_data.get_special_attacks()
	_special_attacks_cache = list
	_attacks_cached = true
	_attack_ready_at.clear()
	var now: int = Time.get_ticks_msec()
	for i in _special_attacks_cache.size():
		var atk: BossAttackData = _special_attacks_cache[i]
		_attack_ready_at[i] = now + int(maxf(0.0, atk.cooldown) * 1000.0)


func _get_boss_attacks() -> Array[BossAttackData]:
	if not _attacks_cached:
		_init_boss_attacks()
	return _special_attacks_cache


## The attack the readiness gate picked for the current windup — read by the
## boss_special state on enter.
func get_pending_special_attack() -> BossAttackData:
	return _pending_special_attack


## [Server] Readiness GATE for the telegraphed special — the only boss code left in
## _process. Picks the first off-cooldown, in-range attack and hands control to the
## "boss_special" state, which owns the telegraph + windup + AoE/dash (see
## enemy_boss_special.gd). Kept tiny on purpose: the behaviour is a state + data.
func _boss_special_tick() -> void:
	if _boss_special_pending:
		return
	if health_component == null or health_component.is_dead:
		return
	if state_machine == null:
		return
	var special_state: Node = state_machine.get_node_or_null("boss_special")
	if special_state == null or state_machine.current_state == special_state:
		return
	# Don't open a windup mid-stagger; only from an active combat/idle pose.
	var hit_state: Node = state_machine.get_node_or_null("hit")
	if hit_state != null and state_machine.current_state == hit_state:
		return
	var target: Node2D = acquire_target()
	if target == null:
		return

	var now: int = Time.get_ticks_msec()
	var attacks: Array[BossAttackData] = _get_boss_attacks()
	for i in attacks.size():
		var atk: BossAttackData = attacks[i]
		if atk == null or atk.cooldown <= 0.0:
			continue
		if now < int(_attack_ready_at.get(i, 0)):
			continue
		if not _attack_target_in_range(atk, target):
			continue
		_pending_special_attack = atk
		_pending_special_idx = i
		_boss_special_pending = true
		state_machine.change_state(special_state)
		return


## Whether `target` is close enough to be worth opening this attack's windup.
func _attack_target_in_range(atk: BossAttackData, target: Node2D) -> bool:
	var d: float = global_position.distance_to(target.global_position)
	return d <= atk.reach + 48.0  # small grace so the dash can close the gap


## [Server] Re-arms the in-windup flag + the just-used attack's own cooldown.
## Called by the boss_special state on exit, whether the windup completed or was
## interrupted (death/stagger), so an interrupted windup can't instantly re-fire.
func arm_boss_special_cooldown() -> void:
	_boss_special_pending = false
	if _pending_special_attack != null and _pending_special_idx >= 0:
		_attack_ready_at[_pending_special_idx] = Time.get_ticks_msec() + int(maxf(0.0, _pending_special_attack.cooldown) * 1000.0)
	_pending_special_attack = null
	_pending_special_idx = -1


## [Server] Shape-aware ground telegraph for `attack`, centered on `center`, facing
## `facing` (-1/+1). RECT = slam band, CIRCLE = nova, CONE = forward fan (approx as a
## band until a cone GroundZone visual lands). All-peer incl. host.
func broadcast_attack_telegraph(attack: BossAttackData, center: Vector2, _facing: int, duration: float, color: Color) -> void:
	match attack.shape:
		BossAttackData.Shape.CIRCLE:
			broadcast_telegraph_ring(center, attack.reach, duration, color)
		_:  # RECT and (for now) CONE
			broadcast_telegraph_rect(center, Vector2(attack.reach, attack.band_height), duration, color)


## [Server] Deals `attack`'s AoE damage to every player inside its shape, centered
## on the telegraphed `center` with the boss facing `facing` (-1/+1). RECT = AABB
## band, CIRCLE = radius, CONE = forward fan within cone_angle. Reuses the player
## HealthComponent.take_damage path; carries the boss's phase/enrage multiplier.
func deal_boss_special_damage(attack: BossAttackData, center: Vector2, facing: int) -> void:
	if not multiplayer.is_server() or _is_being_cleaned_up:
		return
	if health_component == null or health_component.is_dead:
		return
	if stats_component == null or enemy_data == null:
		return

	var is_magic: bool = enemy_data.is_magic_attacker
	var att_stat: int = Constants.StatType.MAGICATTACK if is_magic else Constants.StatType.WEAPONATTACK
	if not stats_component.stats.has(att_stat):
		return
	var base_att: float = float(stats_component.stats.get(att_stat).total_value)
	var special_damage: int = maxi(1, roundi(base_att * _boss_outgoing_mult() * attack.damage_mult))

	for pid in _get_players_on_same_map():
		var node: Node2D = PlayerManager.get_player_node(pid)
		if not is_valid_target(node):
			continue
		if not _point_in_attack(attack, center, facing, node.global_position):
			continue
		var health: HealthComponent = node.get_node_or_null("Components/Health")
		if health == null or health.is_dead or health.is_invulnerable:
			continue
		health.take_damage(special_damage, self)


## Shape hit-test: is `point` inside `attack`'s zone? RECT uses the telegraphed
## centre + band (AABB); CIRCLE uses radius from the boss; CONE is a forward fan
## from the boss apex within cone_angle_deg and `reach`.
func _point_in_attack(attack: BossAttackData, center: Vector2, facing: int, point: Vector2) -> bool:
	match attack.shape:
		BossAttackData.Shape.CIRCLE:
			return global_position.distance_to(point) <= attack.reach
		BossAttackData.Shape.CONE:
			var to_p: Vector2 = point - global_position
			var fwd: float = to_p.x * float(facing)
			if fwd <= 0.0 or to_p.length() > attack.reach:
				return false
			var ang: float = rad_to_deg(absf(to_p.angle_to(Vector2(float(facing), 0.0))))
			return ang <= attack.cone_angle_deg * 0.5
		_:  # RECT
			var off: Vector2 = point - center
			return absf(off.x) <= attack.reach * 0.5 and absf(off.y) <= attack.band_height * 0.5


## Returns this enemy's map id (the name after the "Map_" prefix), or "" when it
## isn't parented under a Map_ container.
func _get_map_id() -> String:
	var parent = get_parent()
	while parent:
		if parent.name.begins_with("Map_"):
			return parent.name.replace("Map_", "")
		parent = parent.get_parent()
	return ""
