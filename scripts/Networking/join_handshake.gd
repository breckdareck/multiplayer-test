class_name JoinHandshake
extends RefCounted

## Owns the per-character spawn sequence — the "join handshake" that brings a
## freshly-spawned MultiplayerPlayerV2 (Player or Bot) to life: apply the Player
## save, initialize components, sync authoritative state to the owning client,
## and notify dependent systems.
##
## Extracted verbatim from PlayerManager._initialize_spawned_player so the ordered
## bring-up sequence lives in ONE phased module instead of smeared through the
## 795-line PlayerManager autoload. PlayerManager keeps the spawn LIFECYCLE
## (find the node, cache it, active_players bookkeeping); this module owns the
## "make this character live" CONTRACT.
##
## Phases (run in order; only LOAD and SYNC await):
##   IDENTIFY → name + discipline + enter loading mode
##   LOAD     → apply the Player save into components (+ inventory/money)
##   INIT     → starter kit, health/mana, recalc, announce name/discipline
##   SYNC     → push authoritative state to the owning client (skipped for bots/host)
##   NOTIFY   → register save node, end loading, onboarding / bot-spawned
##
## Server-only: PlayerManager constructs + runs this on the server after it has
## found the spawned node. Bots have no client and the host (peer 1) is already
## authoritative locally, so the SYNC phase is gated on `_has_client`.

var _pm: Node                  # PlayerManager — get_tree(), active_players, starter helpers
var _player: Node              # the MultiplayerPlayerV2 instance
var _id: int
var _character_type: int
var _username: String
var _save: Dictionary
var _is_bot: bool
var _has_client: bool          # has an owning client to sync to (not a bot, not the host)


func _init(pm: Node, player: Node, id: int, character_type: int, username: String, save: Dictionary) -> void:
	_pm = pm
	_player = player
	_id = id
	_character_type = character_type
	_username = username
	_save = save
	_is_bot = BotManager.is_bot(id)
	_has_client = not _is_bot and id != 1


## Runs the full handshake. Async — awaits frame boundaries during LOAD and SYNC.
func run() -> void:
	_phase_identify()
	await _phase_load()
	_phase_init()
	await _phase_sync()
	_phase_notify()


# ── IDENTIFY ────────────────────────────────────────────────────────────────
## Set the username up front (QuestManager.load_quests, run during LOAD, keys
## per-player dicts off it), set the primary discipline, and put the stateful
## components into loading mode so the save restore below fires no side effects.
func _phase_identify() -> void:
	# Set username on the server immediately. Several pieces of code that run
	# during _load_data — notably QuestManager.load_quests — read the
	# controller's `username` field; if empty, dicts get keyed under "".
	_player.username = _username

	if not _player.weapon_mastery_component:
		push_error("Player %d missing weapon_mastery_component!" % _id)
	elif _player.weapon_mastery_component:
		_player.weapon_mastery_component.set_primary_discipline(_character_type)

	if not _player.stats_component:
		push_error("Player %d missing stats_component!" % _id)
	elif _player.stats_component:
		_player.stats_component.set_loading_mode(true)

	if _player.ability_component:
		_player.ability_component.disconnect_level_signals()

	if _player.level_component:
		_player.level_component._is_loading_data = true


# ── LOAD ──────────────────────────────────────────────────────────────────────
## Apply the Player save into the components, then the inventory. Awaits a few
## frames so the level component settles before loading mode is cleared.
func _phase_load() -> void:
	var has_save_data: bool = not _save.is_empty()
	if has_save_data:
		_player._load_data(_save)
		_pm.active_players[_id]["party_id"] = _save.get("party_id", -1)
		_player.set_current_party_id(_pm.active_players[_id]["party_id"])

		if _player.level_component:
			for i in range(5):
				await _pm.get_tree().process_frame

	# Reset loading flags
	if _player.level_component:
		_player.level_component._is_loading_data = false

	# Load inventory
	if _player.player_inventory:
		var inventory_data: Dictionary = _save.get("inventory", {})
		_player.player_inventory.load_player_inventory_silent(inventory_data)
		# Sync money to client
		if _has_client:
			var monies = _save.get("monies", 0)
			# Also check if monies is inside inventory data structure depending on save format
			if monies == 0 and inventory_data.has("monies"):
				monies = inventory_data.get("monies", 0)
			_player.player_inventory.set_monies_rpc.rpc_id(_id, monies)


# ── INIT ──────────────────────────────────────────────────────────────────────
## Starter kit for a brand-new character, health/mana, the stats recalc, and the
## name/discipline announcement to all peers.
func _phase_init() -> void:
	# Set default equipment if no save or no inventory data, or if inventory is empty (new character)
	var inv_data_check: Dictionary = _save.get("inventory", {})
	var has_items: bool = not inv_data_check.get("slots", []).is_empty()
	var has_equipment: bool = not inv_data_check.get("equipment", {}).is_empty()

	if not _save or not _save.has("inventory") or (not has_items and not has_equipment):
		var ec = _player.equipment_component
		var starter_weapon: String = _pm._starter_weapon_for(_character_type)
		_grant_starter_equip(ec, "WEAPON", starter_weapon)
		# Class-appropriate starter armour: the level-1 "Worn" set of the
		# discipline's family (Vanguard plate / Pathfinder leather / Arcanist robes
		# / Nightshade cloth), so new characters spawn fully kitted.
		var fam: String = _pm._starter_armor_family(_character_type)
		_grant_starter_equip(ec, Constants.ArmorType.HEAD, "Worn %s Helm" % fam)
		_grant_starter_equip(ec, Constants.ArmorType.CHEST, "Worn %s Mail" % fam)
		_grant_starter_equip(ec, Constants.ArmorType.LEGS, "Worn %s Legguards" % fam)
		_grant_starter_equip(ec, Constants.ArmorType.FEET, "Worn %s Boots" % fam)

	# Set health and mana (PRE-recalc). mark_stats_dirty() below defers a stats
	# recalc that fires during the SYNC phase's await; that recalc can change
	# max_health and clamp current_health, so the SYNC phase re-applies these
	# saved values once max is final. Both sets are load-bearing — do not collapse.
	if _player.health_component:
		_player.health_component.current_health = _save.get("current_health", 100)
	if _player.mana_component:
		_player.mana_component.current_mana = _save.get("current_mana", 100)

	# Recalculate stats
	if _player.stats_component:
		_player.stats_component.set_loading_mode(false)
		_player.stats_component.mark_stats_dirty()

	# Refresh equipment-driven UI now that the (carried/loaded or default) weapon
	# is applied. load_player_inventory_silent suppressed signals, and the player
	# node + its signature widgets already spawned, so re-emit on_equipment_changed
	# to make them re-evaluate get_active_discipline() against the loaded weapon.
	if is_instance_valid(_player.equipment_component):
		_player.equipment_component.on_equipment_changed.emit()

	# Reconnect signals
	if _player.ability_component:
		_player.ability_component.reconnect_level_signals()

	# Announce username + primary discipline over the network.
	if _is_bot:
		_player.set_username(_username)
	else:
		_player.set_username.rpc(_username)
	_player.weapon_mastery_component.set_primary_discipline_rpc(_character_type)


## Writes a starter item into the equipment SlotData model (the source of truth)
## and refreshes whatever view is bound, if any. Unlike the old `ec.weapon_slot.item`
## view write, this works on the host, a dedicated server, AND a bot — the model
## is always present even when no UI slot is (ADR 0009 Stage A). The client
## receives the items through the normal inventory sync, which reads slots_data.
func _grant_starter_equip(ec, key, item_name: String) -> void:
	if not is_instance_valid(ec):
		return
	var sd: SlotData = ec.get_slot_data(key)
	if sd == null:
		return
	sd.item = ResourceManager.get_item_by_name(item_name)
	ec.refresh_view(key)


# ── SYNC ──────────────────────────────────────────────────────────────────────
## Push authoritative state to the owning client. Skipped for bots (no client)
## and the host (peer 1, already authoritative). See the health/mana note in INIT.
func _phase_sync() -> void:
	if _has_client:
		# Tell client to start loading mode (suppress saves)
		_player.set_loading_state_rpc.rpc_id(_id, true)

		if _player.ability_component:
			await _pm.get_tree().process_frame
			_player.ability_component.sync_all_abilities_to_client(_id)

		# PR 7: push the server's reconciled attribute allocation to the client.
		if _player.stats_component:
			_player.stats_component.sync_attributes_to_client(_id)

		# Mirror the full mastery state (per-discipline level + xp). The
		# incremental sync_mastery_to_client only fires on XP grants, so without
		# this push the client's mastery bar and ability window read zeros after
		# every spawn (first join and each map-change rebuild).
		if _player.weapon_mastery_component:
			_player.weapon_mastery_component.sync_all_mastery_to_client(_id)

	# Re-apply health/mana AFTER the deferred recalc has run (see INIT note).
	if _player.health_component:
		_player.health_component.current_health = _save.get("current_health", 100)
	if _player.mana_component:
		_player.mana_component.current_mana = _save.get("current_mana", 100)

	if _has_client and _player.buff_component:
		await _pm.get_tree().process_frame
		_player.buff_component.sync_all_buffs_to_client(_id)

	if _id in _pm.active_players:
		_pm.active_players[_id]["synced"] = true


# ── NOTIFY ─────────────────────────────────────────────────────────────────────
## Log the spawn, refresh SaveManager's node ref, end client loading mode, and
## fire dependent-system hooks (bot-spawned / first-login onboarding).
func _phase_notify() -> void:
	var _spawn_level: int = int(_save.get("level", 1))
	var _spawn_map: String = _pm.active_players[_id].get("last_map", "unknown") if _id in _pm.active_players else "unknown"
	var _spawn_kind: String = "Bot" if _is_bot else "Player"
	NetworkUtils.log_network_event("PLAYER_SPAWNED", "%s '%s' (%s lv%d, peer %d) spawned on '%s'" % [_spawn_kind, _username, Constants.ClassType.find_key(_character_type), _spawn_level, _id, _spawn_map])

	# Refresh SaveManager's node reference. On a map change the previous node was
	# freed, and SaveManager keeps a per-player node ref for its debounce.
	if _pm.multiplayer.is_server() and not _username.is_empty():
		SaveManager.register_player(_username, _player)

	# Loading done — tell the client to re-enable saves.
	if _has_client:
		_player.set_loading_state_rpc.rpc_id(_id, false)

	if _is_bot:
		BotManager._on_bot_spawned(_id)

	# First-login onboarding. QuestManager handles idempotency via a persisted
	# `_onboarded` flag — safe to call on every spawn.
	if _pm.multiplayer.is_server() and not _is_bot:
		QuestManager.start_onboarding(_username)
