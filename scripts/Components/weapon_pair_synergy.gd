extends WeaponSignatureComponent

## Weapon-pair synergy — automatic cross-gauge effects that fire when the player
## has a specific PAIR of weapon disciplines equipped (Sword+Staff, Sword+Bow, …).
## "Automatic-on-equip" exactly like spellblade (combat.gd): no buff, no ability, no
## points — equip the pair and the synergy works. Design: project_farever_reference.
##
## The four signature gauges have a GATING ASYMMETRY that drives the shapes:
##   GIVERS (persistent): Sword Combo (clears only when sword leaves BOTH slots),
##     Staff Stance (never clears). These feed whatever weapon you're wielding.
##   RECEIVERS (active-only, zero the instant you swap away): Bow Momentum, Dagger
##     Shadowmeld.
## So five synergies read a persistent gauge while you wield the other weapon; only
## Bow+Dagger (both non-persistent) needs a swap-surviving buffer (`_bd_charge`).
##
## Server-authoritative (mutators guarded), volatile (never saved), bot-safe.
## Auto-discovered by the player's `_collect_weapon_signatures()` because it extends
## WeaponSignatureComponent, so it receives on_weapon_state_changed / on_owner_died
## for free. CombatComponent calls `on_hit_landed()` from _execute_hit's post-loop
## rider section (beside the staff-element + bow-momentum riders).

const SWORD := Constants.ClassType.SWORD
const BOW := Constants.ClassType.BOW
const STAFF := Constants.ClassType.STAFF
const DAGGER := Constants.ClassType.DAGGER

## Sword+Dagger ambush bonus = hit × combo(0-3) × this.
const SWORD_DAGGER_COMBO_MULT: float = 0.5
## Bow+Dagger ambush bonus = hit × charge(0-10) × this.
const BOW_DAGGER_CHARGE_MULT: float = 0.15
## Bow+Dagger charge cap (mirrors the Bow Momentum cap).
const BD_CHARGE_CAP: int = 10
## Staff+Sword (staff active): a spell spends banked Combo for a magic burst —
## bonus = hit × combo(0-3) × this. Build combo on the sword, unload through a spell.
const STAFF_SWORD_COMBO_MULT: float = 0.5
## Dagger-poison imbue (Sword / Bow / Staff active + dagger off-hand): your hits
## apply a poison DoT — the reciprocal mirror of the staff off-hand imbuing the
## element. Per tick per stack = this fraction of the applying hit (so it scales with
## stats / mastery / gear like the other DoTs).
const POISON_PER_TICK_FRAC: float = 0.06
const POISON_MAX_STACKS: int = 5
const POISON_DURATION: float = 12.0

## Emitted on the server AND the owning client (via call_local RPC) whenever a
## synergy effect fires — drives the synergy widget's flash. `pair_key` is one of
## "sword_staff" / "bow_staff" / "staff_dagger" / "sword_bow" / "sword_dagger" /
## "bow_dagger".
signal synergy_proc(pair_key: String)

## Emitted only when a DUO on-swap trigger actually fires (ICD-gated, both
## disciplines past threshold) — the rare "rotation beat" moment. Drives the
## widget's duo flash + stinger; deliberately separate from synergy_proc,
## which fires on every ordinary pair effect and would drown a sound cue.
signal duo_swap_proc(pair_key: String)

# ---------------------------------------------------------------------------
# Duo nodes (ADR 0013) — the named pair-identity layer on top of the always-on
# synergies above. A duo is a stateless DERIVED unlock: active while BOTH
# equipped disciplines have at least DUO_THRESHOLD_POINTS ability points spent
# in them. Never purchased, never persisted (recomputed from synced state),
# costs nothing, deactivates automatically on respec below threshold, works
# for bots with no extra wiring. Each duo = one ON-SWAP trigger (ICD-bounded,
# transient server state) + one STANDING amplification of the pair's existing
# synergy. Bots never swap, so for them only the standing half applies.
# ---------------------------------------------------------------------------
const DUO_THRESHOLD_POINTS := 30
const DUO_SWAP_ICD_MS := 8000
## Points-spent rescan rate limit (spending points mid-fight shows up within
## this window even without a weapon event).
const DUO_REFRESH_MS := 2000
## Duo standing values
const DUO_SWORD_DAGGER_COMBO_MULT := 0.75  # ambush combo-spend 0.5 → 0.75
const DUO_BD_CHARGE_CAP := 15              # bow_dagger buffer cap 10 → 15
const DUO_POISON_MAX_STACKS := 8           # staff_dagger imbue cap 5 → 8
const DUO_MOMENTUM_RIDE_MULT := 1.5        # bow_staff spell ride ×1.5

var _duo_active: bool = false
var _duo_pair_key: String = ""  # canonical "sword_staff" order: sword/bow/staff/dagger
var _duo_last_refresh_ms: int = -1000000
var _duo_swap_ready_at_ms: int = 0
## sword_staff swap-to-SWORD trigger: the next stance imbue fires twice.
var _ss_double_imbue: bool = false
## sword_staff swap-to-STAFF trigger: the next spell's combo-spend pays double.
var _ss_spell_spend_double: bool = false
## bow_staff swap-to-STAFF trigger: the next spell's Momentum ride is doubled.
var _bs_ride_double: bool = false
## staff_dagger swap-to-STAFF trigger: the next poison imbue applies double stacks.
var _venom_double_next: bool = false
## staff_dagger swap-to-DAGGER trigger: the next ambush carries the stance twice.
var _sd_ambush_imbue_double: bool = false
## sword_bow duo standing: every 3rd bow hit banks an extra combo point.
var _sb_hit_count: int = 0

## Bow+Dagger swap buffer: incremented on bow hits while a dagger is the off-hand,
## consumed by the next dagger ambush. Required because the Bow Momentum gauge
## itself zeroes the moment you swap off the bow — this parallel buffer survives.
var _bd_charge: int = 0


func signature_discipline() -> int:
	return -1  # the pair layer, not a single-discipline gauge


## Server-only (caller guards). Fires on equip-change AND Tab-swap. Drop the
## Bow+Dagger charge if that pair is no longer equipped, then re-derive the
## duo state and fire the duo's on-swap trigger (ICD-bounded).
func on_weapon_state_changed(active_discipline: int, equipped_disciplines: Array) -> void:
	if not (equipped_disciplines.has(BOW) and equipped_disciplines.has(DAGGER)):
		_bd_charge = 0

	var owner_node: Node = _resolve_owner()
	if owner_node == null:
		return
	_duo_last_refresh_ms = -1000000  # weapon events always force a re-derive
	_refresh_duo(owner_node)
	if not _duo_active:
		return
	var now: int = Time.get_ticks_msec()
	if now < _duo_swap_ready_at_ms:
		return
	_duo_swap_ready_at_ms = now + DUO_SWAP_ICD_MS
	_fire_duo_swap_trigger(owner_node, active_discipline)
	_duo_proc(owner_node, _duo_pair_key)


func on_owner_died() -> void:
	_bd_charge = 0
	_ss_double_imbue = false
	_ss_spell_spend_double = false
	_bs_ride_double = false
	_venom_double_next = false
	_sd_ambush_imbue_double = false
	_sb_hit_count = 0


## The duo's on-swap beat. Effects are deliberately small and immediate —
## the swap button becomes a rotation beat (GW2 sigil pattern), bounded by
## the 8s internal cooldown. DIRECTION-AWARE: the reward always lands on the
## weapon you arrive on, in that weapon's own currency (sword → combo,
## bow → Momentum, dagger → stealth / ambush buffer, staff → an empowered
## next spell), so neither side of a pair is the "donor" on swap.
func _fire_duo_swap_trigger(owner_node: Node, active_discipline: int) -> void:
	match _duo_pair_key:
		"sword_staff":
			# Emberblade — to the SWORD: the next stance imbue strikes twice;
			# to the STAFF: the next spell's combo-spend pays double.
			if active_discipline == STAFF:
				_ss_spell_spend_double = true
			else:
				_ss_double_imbue = true
			_proc(owner_node, "sword_staff")
		"sword_bow":
			# Skirmisher's Rhythm — to the SWORD: bank 2 combo points;
			# to the BOW: gain 3 Momentum stacks.
			if active_discipline == BOW:
				_grant_momentum(owner_node, 3, "sword_bow")
			else:
				_grant_combo(owner_node, 2, "sword_bow")
		"sword_dagger":
			# Blade Dancer's Oath — to the DAGGER: meld into shadow;
			# to the SWORD: bank 2 combo points.
			if active_discipline == DAGGER:
				var shadow = owner_node.get("shadowmeld_component")
				if shadow != null and is_instance_valid(shadow) and shadow.has_method("toggle_shadowmeld"):
					var stealthed: bool = shadow.is_stealthed() if shadow.has_method("is_stealthed") else false
					if not stealthed:
						# Deferred: the player root is still iterating its
						# signature list; shadowmeld's own handler must see
						# the dagger active before stealth is granted.
						shadow.call_deferred("toggle_shadowmeld")
						_proc(owner_node, "sword_dagger")
			else:
				_grant_combo(owner_node, 2, "sword_dagger")
		"bow_staff":
			# Galecaller — to the BOW: gain 4 Momentum; to the STAFF: the
			# next spell's Momentum ride is doubled.
			if active_discipline == STAFF:
				_bs_ride_double = true
				_proc(owner_node, "bow_staff")
			else:
				_grant_momentum(owner_node, 4, "bow_staff")
		"bow_dagger":
			# Veiled Quarry — to the DAGGER: the ambush buffer charges +4;
			# to the BOW: gain 3 Momentum.
			if active_discipline == BOW:
				_grant_momentum(owner_node, 3, "bow_dagger")
			else:
				_bd_charge = mini(DUO_BD_CHARGE_CAP, _bd_charge + 4)
				_proc(owner_node, "bow_dagger")
		"staff_dagger":
			# Venomweave — to the STAFF: the next poison imbue applies double
			# stacks; to the DAGGER: the next ambush carries the stance twice.
			if active_discipline == DAGGER:
				_sd_ambush_imbue_double = true
			else:
				_venom_double_next = true
			_proc(owner_node, "staff_dagger")


func _grant_combo(owner_node: Node, n: int, pair_key: String) -> void:
	var combo = owner_node.get("sword_combo_component")
	if combo == null or not is_instance_valid(combo) or not combo.has_method("add_combo_point"):
		return
	for _i in range(n):
		combo.add_combo_point()
	_proc(owner_node, pair_key)


func _grant_momentum(owner_node: Node, n: int, pair_key: String) -> void:
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("add_momentum"):
		return
	bm.add_momentum(n)
	_proc(owner_node, pair_key)


## Re-derive whether the equipped pair's duo is unlocked (rate-limited; weapon
## events force it by resetting the timestamp). Stateless w.r.t. persistence —
## reads the live per-discipline points-spent, which is server-authoritative
## and already part of the synced progression state.
func _refresh_duo(owner_node: Node) -> void:
	var now: int = Time.get_ticks_msec()
	if now - _duo_last_refresh_ms < DUO_REFRESH_MS:
		return
	_duo_last_refresh_ms = now
	_duo_active = false
	_duo_pair_key = ""

	var ac = owner_node.get("ability_component")
	if ac == null or not is_instance_valid(ac) or not ac.has_method("get_points_spent_in_discipline"):
		return
	if not owner_node.has_method("get_equipped_disciplines"):
		return
	var equipped: Array = owner_node.get_equipped_disciplines()
	if equipped.size() < 2:
		return
	var keys: Array[String] = []
	for entry in [[SWORD, "sword"], [BOW, "bow"], [STAFF, "staff"], [DAGGER, "dagger"]]:
		if equipped.has(entry[0]):
			keys.append(entry[1])
	if keys.size() != 2:
		return
	for k in keys:
		if int(ac.get_points_spent_in_discipline(k)) < DUO_THRESHOLD_POINTS:
			return
	_duo_pair_key = "%s_%s" % [keys[0], keys[1]]
	_duo_active = true


## True when the given pair's duo is currently unlocked + equipped.
func _duo(pair_key: String) -> bool:
	return _duo_active and _duo_pair_key == pair_key


## This component receives signature notifications without an owner argument —
## resolve the player root by walking up to the node that owns the equipped-
## disciplines API (same tree shape every player/bot character has).
func _resolve_owner() -> Node:
	var n: Node = get_parent()
	while n != null:
		if n.has_method("get_equipped_disciplines"):
			return n
		n = n.get_parent()
	return null


## Called by CombatComponent._execute_hit once per target AFTER the hit loop, only
## when the attack landed (max_landed_damage > 0). Server-side. Dispatches the
## active weapon's synergy with whatever ELSE is equipped (you have exactly two
## weapon slots, so the equipped set is at most a single pair).
func on_hit_landed(owner_node: Node, target: Node, hit_damage: int, ability, did_ambush: bool) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(owner_node) or not is_instance_valid(target):
		return
	var equipped: Array = owner_node.get_equipped_disciplines()
	if equipped.size() < 2:
		return  # need a genuine two-weapon pair (matched pairs de-dup to size 1)
	var active: int = owner_node.get_active_discipline()
	_refresh_duo(owner_node)

	match active:
		SWORD:
			# Sword+Staff — sword ABILITY hits carry the current stance's element
			# rider (the persistent Stance feeds the wielded sword). Ability-gated
			# to bound uptime, mirroring the staff rider's `ability != null` gate.
			# Emberblade duo (standing): BASIC sword hits imbue too.
			if (ability != null or _duo("sword_staff")) and equipped.has(STAFF):
				_imbue_with_stance(owner_node, target, hit_damage, "sword_staff")
			# Sword+Dagger (reciprocal) — sword ability hits apply Poison.
			if ability != null and equipped.has(DAGGER):
				_imbue_with_poison(owner_node, target, hit_damage, "sword_dagger")
		BOW:
			# Bow+Staff — arrows carry the stance rider.
			if equipped.has(STAFF):
				_imbue_with_stance(owner_node, target, hit_damage, "bow_staff")
			# Sword+Bow — bow hits BANK a combo point (Combo persists; swap to the
			# sword and spend the stockpile on a finisher). Skirmisher's Rhythm
			# duo (standing): every 3rd bow hit banks one extra.
			if equipped.has(SWORD):
				_bank_combo(owner_node)
				if _duo("sword_bow"):
					_sb_hit_count += 1
					if _sb_hit_count >= 3:
						_sb_hit_count = 0
						_bank_combo(owner_node)
			# Bow+Dagger — charge the swap-buffer for the next ambush AND (reciprocal)
			# apply Poison on the bow hit. Veiled Quarry duo (standing): deeper buffer.
			if equipped.has(DAGGER):
				var bd_cap: int = DUO_BD_CHARGE_CAP if _duo("bow_dagger") else BD_CHARGE_CAP
				_bd_charge = mini(bd_cap, _bd_charge + 1)
				_imbue_with_poison(owner_node, target, hit_damage, "bow_dagger")
		DAGGER:
			if did_ambush:
				# Staff+Dagger — the ambush carries the stance element.
				if equipped.has(STAFF):
					_imbue_with_stance(owner_node, target, hit_damage, "staff_dagger")
				# Sword+Dagger — spend banked Combo for ambush bonus damage.
				# Blade Dancer's Oath duo (standing): richer per-point spend.
				if equipped.has(SWORD):
					var sd_mult: float = DUO_SWORD_DAGGER_COMBO_MULT if _duo("sword_dagger") else SWORD_DAGGER_COMBO_MULT
					_spend_combo_for_bonus(owner_node, target, hit_damage, sd_mult, "sword_dagger")
				# Bow+Dagger — spend the bow charge for ambush bonus damage.
				if equipped.has(BOW):
					_ambush_spend_bd_charge(owner_node, target, hit_damage)
		STAFF:
			# Staff-main RECIPROCALS (spell hits only) — the off-hand gives back, so a
			# staff main isn't a pure GIVER. Each uses the off-hand's identity.
			if ability != null:
				# Staff+Sword — the spell spends banked Combo for a magic burst.
				if equipped.has(SWORD):
					_spend_combo_for_bonus(owner_node, target, hit_damage, STAFF_SWORD_COMBO_MULT, "staff_sword")
				# Staff+Bow — the spell rides your Momentum ramp (persists across swap).
				# Galecaller duo (standing): the ride pays 1.5×.
				if equipped.has(BOW):
					var ride_mult: float = DUO_MOMENTUM_RIDE_MULT if _duo("bow_staff") else 1.0
					_spell_ride_momentum(owner_node, target, hit_damage, ride_mult)
				# Staff+Dagger — the spell applies Poison (venom-mage; mirror of the
				# dagger ambush carrying the staff's element).
				if equipped.has(DAGGER):
					_imbue_with_poison(owner_node, target, hit_damage, "staff_dagger")


## Apply the equipped staff's current stance rider (burn / slow / chain) to a hit
## from a NON-staff weapon. Reuses the staff component's own rider so the element
## numbers stay identical to a real staff cast.
func _imbue_with_stance(owner_node: Node, target: Node, hit_damage: int, pair_key: String) -> void:
	var staff = owner_node.get("staff_element_component")
	if staff == null or not is_instance_valid(staff) or not staff.has_method("apply_element_on_hit"):
		return
	staff.apply_element_on_hit(owner_node, target, hit_damage)
	# Emberblade duo swap trigger (to the sword): the post-swap imbue
	# discharges twice.
	if _ss_double_imbue and pair_key == "sword_staff":
		_ss_double_imbue = false
		staff.apply_element_on_hit(owner_node, target, hit_damage)
	# Venomweave duo swap trigger (to the dagger): the post-swap ambush
	# carries the stance element twice.
	if _sd_ambush_imbue_double and pair_key == "staff_dagger":
		_sd_ambush_imbue_double = false
		staff.apply_element_on_hit(owner_node, target, hit_damage)
	_proc(owner_node, pair_key)


## Bow+Sword: a bow hit banks a sword Combo point (Combo persists across the swap).
func _bank_combo(owner_node: Node) -> void:
	var combo = owner_node.get("sword_combo_component")
	if combo == null or not is_instance_valid(combo) or not combo.has_method("add_combo_point"):
		return
	combo.add_combo_point()
	_proc(owner_node, "sword_bow")


## Spend banked sword Combo for a bonus-damage burst on the victim. Shared by
## Sword+Dagger (dagger ambush spends combo) and Staff+Sword (a spell spends combo).
## `mult` scales the per-point bonus; combo is consumed once (so on a multi-target
## hit only the first target gets the burst — the resource is spent).
func _spend_combo_for_bonus(owner_node: Node, target: Node, hit_damage: int, mult: float, pair_key: String) -> void:
	var combo = owner_node.get("sword_combo_component")
	if combo == null or not is_instance_valid(combo) or not combo.has_method("get_combo_count"):
		return
	var n: int = int(combo.get_combo_count())
	if n <= 0:
		return
	if combo.has_method("spend_combo"):
		combo.spend_combo()
	# Emberblade duo swap trigger (to the staff): the post-swap spell's
	# combo-spend pays double. Consumed only when a spend actually happens.
	if _ss_spell_spend_double and pair_key == "staff_sword":
		_ss_spell_spend_double = false
		mult *= 2.0
	_deal_bonus(owner_node, target, maxi(1, roundi(hit_damage * n * mult)), "COMBO BURST", EventJuice.COLOR_COMBO)
	_proc(owner_node, pair_key)


## Dagger-poison imbue (reciprocal): the active weapon's hit applies a poison DoT,
## the mirror of the staff off-hand imbuing the element. Per-tick scales off the
## applying hit so it keeps pace with stats/mastery/gear (project_dot_scaling_divergence).
## BleedDot is the shared DoT helper; safe to ref directly here (combat does NOT
## hard-preload this component — it resolves it by node path — so no compile cycle).
func _imbue_with_poison(owner_node: Node, target: Node, hit_damage: int, pair_key: String) -> void:
	if not is_instance_valid(target):
		return
	var per_tick: int = maxi(1, roundi(hit_damage * POISON_PER_TICK_FRAC))
	# Venomweave duo (standing): the staff_dagger imbue stacks deeper.
	var max_stacks: int = DUO_POISON_MAX_STACKS if (pair_key == "staff_dagger" and _duo("staff_dagger")) else POISON_MAX_STACKS
	BleedDot.apply(target, owner_node, per_tick, max_stacks, POISON_DURATION, "synergy_poison", "poison")
	# Venomweave duo swap trigger: the post-swap application doubles up.
	if _venom_double_next and pair_key == "staff_dagger":
		_venom_double_next = false
		BleedDot.apply(target, owner_node, per_tick, max_stacks, POISON_DURATION, "synergy_poison", "poison")
	_proc(owner_node, pair_key)


## Staff+Bow (staff active): the spell rides your Bow Momentum ramp — bonus damage =
## hit × the momentum damage fraction (stacks × DAMAGE_PER_STACK). Momentum now
## persists across the swap (+ the sheathe hold), so a mage can build it on the bow
## and unload empowered spells.
func _spell_ride_momentum(owner_node: Node, target: Node, hit_damage: int, ride_mult: float = 1.0) -> void:
	var bm = owner_node.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("get_damage_bonus"):
		return
	# Galecaller duo swap trigger (to the staff): the post-swap spell's ride
	# is doubled. Consumed only when a ride actually pays out.
	if _bs_ride_double and bm.get_damage_bonus() > 0.0:
		_bs_ride_double = false
		ride_mult *= 2.0
	var bonus_frac: float = bm.get_damage_bonus() * ride_mult
	if bonus_frac <= 0.0:
		return
	_deal_bonus(owner_node, target, maxi(1, roundi(hit_damage * bonus_frac)), "MOMENTUM SURGE", EventJuice.COLOR_MOMENTUM)
	_proc(owner_node, "staff_bow")


## Bow+Dagger: the ambush spends the bow swap-buffer for bonus damage.
func _ambush_spend_bd_charge(owner_node: Node, target: Node, hit_damage: int) -> void:
	if _bd_charge <= 0:
		return
	var bonus: int = maxi(1, roundi(hit_damage * _bd_charge * BOW_DAGGER_CHARGE_MULT))
	_bd_charge = 0
	_deal_bonus(owner_node, target, bonus, "CHARGED AMBUSH", EventJuice.COLOR_AMBUSH)
	_proc(owner_node, "bow_dagger")


## Deal a discrete synergy "spark" of bonus damage. Bypasses i-frames + shows the
## number; never crits (it's a flat synergy bonus, not a rolled hit).
func _deal_bonus(owner_node: Node, target: Node, bonus: int, label: String = "", label_color: Color = Color.WHITE) -> void:
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return
	hc.take_damage(bonus, owner_node, true, false, true)
	# Juice: the synergy payoffs are the pair's identity moments — name them
	# next to the number and give them a stinger so the spend is FELT.
	if label != "":
		EventJuice.proc(target, label, label_color, EventJuice.SFX_SYNERGY)


## Emit the proc signal on the server and the owning client (widget flash). Mirrors
## the gauge sync pattern: call_local RPC to the owning player id; bots (no client,
## non-positive id) just emit locally for any server-side listener.
func _proc(owner_node: Node, pair_key: String) -> void:
	var pid: int = int(owner_node.player_id) if "player_id" in owner_node else 0
	if pid <= 0:
		synergy_proc.emit(pair_key)
		return
	proc_to_client.rpc_id(pid, pair_key)


@rpc("authority", "call_local", "reliable")
func proc_to_client(pair_key: String) -> void:
	synergy_proc.emit(pair_key)


## Duo-swap mirror of _proc: local emit for bots, call_local RPC to the
## owning client for real players.
func _duo_proc(owner_node: Node, pair_key: String) -> void:
	var pid: int = int(owner_node.player_id) if "player_id" in owner_node else 0
	if pid <= 0:
		duo_swap_proc.emit(pair_key)
		return
	duo_proc_to_client.rpc_id(pid, pair_key)


@rpc("authority", "call_local", "reliable")
func duo_proc_to_client(pair_key: String) -> void:
	duo_swap_proc.emit(pair_key)
