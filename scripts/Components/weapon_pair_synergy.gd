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
const POISON_DURATION: float = 4.0

## Emitted on the server AND the owning client (via call_local RPC) whenever a
## synergy effect fires — drives the synergy widget's flash. `pair_key` is one of
## "sword_staff" / "bow_staff" / "staff_dagger" / "sword_bow" / "sword_dagger" /
## "bow_dagger".
signal synergy_proc(pair_key: String)

## Bow+Dagger swap buffer: incremented on bow hits while a dagger is the off-hand,
## consumed by the next dagger ambush. Required because the Bow Momentum gauge
## itself zeroes the moment you swap off the bow — this parallel buffer survives.
var _bd_charge: int = 0


func signature_discipline() -> int:
	return -1  # the pair layer, not a single-discipline gauge


## Server-only (caller guards). Fires on equip-change AND Tab-swap. Drop the
## Bow+Dagger charge if that pair is no longer equipped.
func on_weapon_state_changed(_active_discipline: int, equipped_disciplines: Array) -> void:
	if not (equipped_disciplines.has(BOW) and equipped_disciplines.has(DAGGER)):
		_bd_charge = 0


func on_owner_died() -> void:
	_bd_charge = 0


## Called by CombatComponent._execute_hit once per target AFTER the hit loop, only
## when the attack landed (max_landed_damage > 0). Server-side. Dispatches the
## active weapon's synergy with whatever ELSE is equipped (you have exactly two
## weapon slots, so the equipped set is at most a single pair).
func on_hit_landed(owner: Node, target: Node, hit_damage: int, ability, did_ambush: bool) -> void:
	if not multiplayer.is_server():
		return
	if not is_instance_valid(owner) or not is_instance_valid(target):
		return
	var equipped: Array = owner.get_equipped_disciplines()
	if equipped.size() < 2:
		return  # need a genuine two-weapon pair (matched pairs de-dup to size 1)
	var active: int = owner.get_active_discipline()

	match active:
		SWORD:
			# Sword+Staff — sword ABILITY hits carry the current stance's element
			# rider (the persistent Stance feeds the wielded sword). Ability-gated
			# to bound uptime, mirroring the staff rider's `ability != null` gate.
			if ability != null and equipped.has(STAFF):
				_imbue_with_stance(owner, target, hit_damage, "sword_staff")
			# Sword+Dagger (reciprocal) — sword ability hits apply Poison.
			if ability != null and equipped.has(DAGGER):
				_imbue_with_poison(owner, target, hit_damage, "sword_dagger")
		BOW:
			# Bow+Staff — arrows carry the stance rider.
			if equipped.has(STAFF):
				_imbue_with_stance(owner, target, hit_damage, "bow_staff")
			# Sword+Bow — bow hits BANK a combo point (Combo persists; swap to the
			# sword and spend the stockpile on a finisher).
			if equipped.has(SWORD):
				_bank_combo(owner)
			# Bow+Dagger — charge the swap-buffer for the next ambush AND (reciprocal)
			# apply Poison on the bow hit.
			if equipped.has(DAGGER):
				_bd_charge = mini(BD_CHARGE_CAP, _bd_charge + 1)
				_imbue_with_poison(owner, target, hit_damage, "bow_dagger")
		DAGGER:
			if did_ambush:
				# Staff+Dagger — the ambush carries the stance element.
				if equipped.has(STAFF):
					_imbue_with_stance(owner, target, hit_damage, "staff_dagger")
				# Sword+Dagger — spend banked Combo for ambush bonus damage.
				if equipped.has(SWORD):
					_spend_combo_for_bonus(owner, target, hit_damage, SWORD_DAGGER_COMBO_MULT, "sword_dagger")
				# Bow+Dagger — spend the bow charge for ambush bonus damage.
				if equipped.has(BOW):
					_ambush_spend_bd_charge(owner, target, hit_damage)
		STAFF:
			# Staff-main RECIPROCALS (spell hits only) — the off-hand gives back, so a
			# staff main isn't a pure GIVER. Each uses the off-hand's identity.
			if ability != null:
				# Staff+Sword — the spell spends banked Combo for a magic burst.
				if equipped.has(SWORD):
					_spend_combo_for_bonus(owner, target, hit_damage, STAFF_SWORD_COMBO_MULT, "staff_sword")
				# Staff+Bow — the spell rides your Momentum ramp (persists across swap).
				if equipped.has(BOW):
					_spell_ride_momentum(owner, target, hit_damage)
				# Staff+Dagger — the spell applies Poison (venom-mage; mirror of the
				# dagger ambush carrying the staff's element).
				if equipped.has(DAGGER):
					_imbue_with_poison(owner, target, hit_damage, "staff_dagger")


## Apply the equipped staff's current stance rider (burn / slow / chain) to a hit
## from a NON-staff weapon. Reuses the staff component's own rider so the element
## numbers stay identical to a real staff cast.
func _imbue_with_stance(owner: Node, target: Node, hit_damage: int, pair_key: String) -> void:
	var staff = owner.get("staff_element_component")
	if staff == null or not is_instance_valid(staff) or not staff.has_method("apply_element_on_hit"):
		return
	staff.apply_element_on_hit(owner, target, hit_damage)
	_proc(owner, pair_key)


## Bow+Sword: a bow hit banks a sword Combo point (Combo persists across the swap).
func _bank_combo(owner: Node) -> void:
	var combo = owner.get("sword_combo_component")
	if combo == null or not is_instance_valid(combo) or not combo.has_method("add_combo_point"):
		return
	combo.add_combo_point()
	_proc(owner, "sword_bow")


## Spend banked sword Combo for a bonus-damage burst on the victim. Shared by
## Sword+Dagger (dagger ambush spends combo) and Staff+Sword (a spell spends combo).
## `mult` scales the per-point bonus; combo is consumed once (so on a multi-target
## hit only the first target gets the burst — the resource is spent).
func _spend_combo_for_bonus(owner: Node, target: Node, hit_damage: int, mult: float, pair_key: String) -> void:
	var combo = owner.get("sword_combo_component")
	if combo == null or not is_instance_valid(combo) or not combo.has_method("get_combo_count"):
		return
	var n: int = int(combo.get_combo_count())
	if n <= 0:
		return
	if combo.has_method("spend_combo"):
		combo.spend_combo()
	_deal_bonus(owner, target, maxi(1, roundi(hit_damage * n * mult)))
	_proc(owner, pair_key)


## Dagger-poison imbue (reciprocal): the active weapon's hit applies a poison DoT,
## the mirror of the staff off-hand imbuing the element. Per-tick scales off the
## applying hit so it keeps pace with stats/mastery/gear (project_dot_scaling_divergence).
## BleedDot is the shared DoT helper; safe to ref directly here (combat does NOT
## hard-preload this component — it resolves it by node path — so no compile cycle).
func _imbue_with_poison(owner: Node, target: Node, hit_damage: int, pair_key: String) -> void:
	if not is_instance_valid(target):
		return
	var per_tick: int = maxi(1, roundi(hit_damage * POISON_PER_TICK_FRAC))
	BleedDot.apply(target, owner, per_tick, POISON_MAX_STACKS, POISON_DURATION, "synergy_poison", "poison")
	_proc(owner, pair_key)


## Staff+Bow (staff active): the spell rides your Bow Momentum ramp — bonus damage =
## hit × the momentum damage fraction (stacks × DAMAGE_PER_STACK). Momentum now
## persists across the swap (+ the sheathe hold), so a mage can build it on the bow
## and unload empowered spells.
func _spell_ride_momentum(owner: Node, target: Node, hit_damage: int) -> void:
	var bm = owner.get("bow_momentum_component")
	if bm == null or not is_instance_valid(bm) or not bm.has_method("get_damage_bonus"):
		return
	var bonus_frac: float = bm.get_damage_bonus()
	if bonus_frac <= 0.0:
		return
	_deal_bonus(owner, target, maxi(1, roundi(hit_damage * bonus_frac)))
	_proc(owner, "staff_bow")


## Bow+Dagger: the ambush spends the bow swap-buffer for bonus damage.
func _ambush_spend_bd_charge(owner: Node, target: Node, hit_damage: int) -> void:
	if _bd_charge <= 0:
		return
	var bonus: int = maxi(1, roundi(hit_damage * _bd_charge * BOW_DAGGER_CHARGE_MULT))
	_bd_charge = 0
	_deal_bonus(owner, target, bonus)
	_proc(owner, "bow_dagger")


## Deal a discrete synergy "spark" of bonus damage. Bypasses i-frames + shows the
## number; never crits (it's a flat synergy bonus, not a rolled hit).
func _deal_bonus(owner: Node, target: Node, bonus: int) -> void:
	var hc = target.get("health_component")
	if hc == null or not is_instance_valid(hc) or hc.is_dead:
		return
	hc.take_damage(bonus, owner, true, false, true)


## Emit the proc signal on the server and the owning client (widget flash). Mirrors
## the gauge sync pattern: call_local RPC to the owning player id; bots (no client,
## non-positive id) just emit locally for any server-side listener.
func _proc(owner: Node, pair_key: String) -> void:
	var pid: int = int(owner.player_id) if "player_id" in owner else 0
	if pid <= 0:
		synergy_proc.emit(pair_key)
		return
	proc_to_client.rpc_id(pid, pair_key)


@rpc("authority", "call_local", "reliable")
func proc_to_client(pair_key: String) -> void:
	synergy_proc.emit(pair_key)
