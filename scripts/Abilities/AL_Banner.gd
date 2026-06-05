extends Node

## Banner of the Vanguard (sword active) — POSITIONAL DEFENSIVE PARTY-BUFF
## ZONE. Plant a banner at the caster's feet for 8 seconds. Any party
## member (including the caster) standing inside the radius gains a
## +DEFENSE_FLAT_BONUS to Defense and a small HP regen tick each second.
##
## Sword becomes the ONLY weapon with a defensive party utility — every
## other weapon's party buff is offensive (Vow = +all stats burst,
## Eagle Eye = +crit, Bloodlust = +crit, Communion = +MP regen/MagicAtk).
## Pairs with Vow (offensive burst on top of defensive aura) and
## Earthsplitter (zone over zone — frontline brawl).
##
## Implementation: uses the shared GroundZone helper with the new ally
## callback. Damage=0 (purely benevolent). The callback re-applies a
## stat-buff-tagged meta to each overlapping ally every second; the
## buff naturally falls off when the ally leaves the zone (the meta
## expiry is shorter than the next tick interval).

const ZONE_RADIUS: float = 110.0
const ZONE_DURATION: float = 8.0
const ZONE_TICK_INTERVAL: float = 1.0

## Per-tick HP regen — flat amount, not %. Scales by ability level via
## the .tres scaling formula (read from level_stats), but for v1 we use a
## fixed const that the .tres formula can override later.
const HP_REGEN_PER_TICK: int = 8

## Defense buff while inside zone. Stored as a Stat modifier on the ally
## node via a meta tag that BannerAura buff scaffolding can consume. For
## v1 we apply via the existing BuffComponent if available; otherwise the
## defense bonus is tracked as a meta the ally's stats can read at recalc.
const BANNER_BUFF_NAME: String = "Banner Aura"
const BANNER_BUFF_DURATION: float = 1.5  ## slightly longer than tick interval

const ZONE_COLOR: Color = Color(1.0, 0.85, 0.45, 0.30)  ## golden glow

## Metas an ally inside the banner carries, read by combat.gd. Expiry slightly
## exceeds the tick interval so they persist while inside and lapse on exit.
const DMG_AURA_META: String = "banner_dmg_bonus_until_ms"
const DMG_AURA_AMT_META: String = "banner_dmg_bonus_amt"
const DR_AURA_META: String = "banner_dr_until_ms"
const DR_AURA_AMT_META: String = "banner_dr_amt"

## Level-scaled aura values — fallback only. The live values come from the .tres
## custom_value_formulas ("defense" 30→75, "hp_regen" 5→14), the same formulas the
## $[value:defense] / $[value:hp_regen] description placeholders read, so the
## tooltip and the applied aura can never drift.
const HP_REGEN_MIN: int = 5
const HP_REGEN_MAX: int = 14
const DEFENSE_MIN: float = 30.0
const DEFENSE_MAX: float = 75.0

# Per-cast state, set in execute(), read in the per-tick callback.
var _heal_mult: float = 0.0
var _aura_damage: float = 0.0
var _damage_reduction: float = 0.0
var _hp_regen: int = HP_REGEN_MIN
var _aura_defense: float = DEFENSE_MIN
var _scaled_allies: Dictionary = {}  # ally instance_id -> true (defense scaled once)


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	# PR 6 upgrade reads — Wider Banner (T1) adds aura radius; Lasting
	# Banner (T2) adds duration. T3 variants: Healing Banner (double regen),
	# Inspiring Banner (+ally damage), Bulwark Banner (-ally incoming damage).
	var radius_bonus: float = 0.0
	var duration_bonus: float = 0.0
	_heal_mult = 0.0
	_aura_damage = 0.0
	_damage_reduction = 0.0
	var ability_comp = owner_node.get("ability_component")
	if ability_comp and _ability != null and ability_comp.has_method("get_ability_upgrade_magnitude"):
		radius_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_radius")
		duration_bonus = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_zone_duration")
		_heal_mult = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_heal_mult")
		_aura_damage = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_aura_damage")
		_damage_reduction = ability_comp.get_ability_upgrade_magnitude(_ability.ability_id, "bonus_damage_reduction")

	# HP regen + aura Defense scale with the ability's level. Read from the shared
	# .tres formulas so they match the $[value:defense] / $[value:hp_regen] tooltip.
	var lvl: int = _level_stats.level if _level_stats != null else 1
	if _ability != null:
		_hp_regen = int(roundf(_ability.get_custom_value("hp_regen", lvl, float(HP_REGEN_MAX))))
		_aura_defense = _ability.get_custom_value("defense", lvl, DEFENSE_MAX)
	else:
		_hp_regen = HP_REGEN_MAX
		_aura_defense = DEFENSE_MAX
	_scaled_allies.clear()

	var radius: float = ZONE_RADIUS + radius_bonus
	var duration: float = ZONE_DURATION + duration_bonus

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		owner_node.global_position,
		radius,
		duration,
		ZONE_TICK_INTERVAL,
		0,  # no damage — purely benevolent
		ZONE_COLOR,
		Callable(),  # no enemy callback
		Callable(self, "_apply_banner_aura")
	)

	# Ground "juice" — a tiled golden glow across the banner's aura radius.
	MapManager.broadcast_ground_vfx_everywhere(MapManager.get_player_map(owner_node.player_id), "holy_ground", owner_node.global_position, radius * 2.0, duration)


## Per-tick callback fired by the zone for each ally currently inside.
## Heals a small amount and refreshes the Banner Aura buff (which carries
## the +Defense modifier on the ally's stats).
func _apply_banner_aura(ally: Node) -> void:
	if not is_instance_valid(ally):
		return

	# HP regen tick — directly heal the ally via their HealthComponent. The regen
	# scales with ability level; Healing Banner (T3) doubles it via _heal_mult.
	var heal_amount: int = int(_hp_regen * (1.0 + _heal_mult))
	var hc = ally.get("health_component")
	if hc != null and is_instance_valid(hc) and not hc.is_dead:
		if hc.has_method("heal"):
			hc.heal(heal_amount)
		elif "current_health" in hc and "max_health" in hc:
			# Fallback if no heal method — clamp manually.
			var new_hp: int = mini(int(hc.max_health), int(hc.current_health) + heal_amount)
			hc.current_health = new_hp

	# Inspiring Banner (T3): tag the ally with a short-lived +damage meta combat
	# reads on their outgoing hits. Bulwark Banner (T3): a -incoming-damage meta.
	var until_ms: int = Time.get_ticks_msec() + int(BANNER_BUFF_DURATION * 1000.0)
	if _aura_damage > 0.0:
		ally.set_meta(DMG_AURA_META, until_ms)
		ally.set_meta(DMG_AURA_AMT_META, _aura_damage)
	if _damage_reduction > 0.0:
		ally.set_meta(DR_AURA_META, until_ms)
		ally.set_meta(DR_AURA_AMT_META, _damage_reduction)

	# Refresh the Banner Aura buff for slightly longer than the tick interval
	# so an ally inside the zone keeps the buff continuously; an ally that
	# walks out lets it expire after BANNER_BUFF_DURATION.
	var buff_comp = ally.get_node_or_null("Components/Buff")
	if buff_comp != null and is_instance_valid(buff_comp) and buff_comp.has_method("apply_buff"):
		buff_comp.apply_buff(BANNER_BUFF_NAME, null, BANNER_BUFF_DURATION)
		# Scale the aura's +Defense with the banner's level — once per ally per
		# cast (REFRESH keeps the scaled buff_data across subsequent ticks).
		var aid: int = ally.get_instance_id()
		if not _scaled_allies.has(aid) and buff_comp.has_method("scale_buff_stat"):
			_scaled_allies[aid] = true
			buff_comp.scale_buff_stat(BANNER_BUFF_NAME, Constants.StatType.DEFENSE, _aura_defense)


## Inspiring Banner (T3) outgoing-damage bonus for a node currently inside a
## banner (0.0 otherwise). Called from combat.gd on the attacker.
static func get_aura_damage_bonus(node: Node) -> float:
	if node == null or not is_instance_valid(node) or not node.has_meta(DMG_AURA_META):
		return 0.0
	if Time.get_ticks_msec() >= int(node.get_meta(DMG_AURA_META)):
		return 0.0
	return float(node.get_meta(DMG_AURA_AMT_META)) if node.has_meta(DMG_AURA_AMT_META) else 0.0


## Bulwark Banner (T3) incoming-damage reduction fraction for a node inside a
## banner (0.0 otherwise). Called from the damage-taken path on the defender.
static func get_incoming_damage_reduction(node: Node) -> float:
	if node == null or not is_instance_valid(node) or not node.has_meta(DR_AURA_META):
		return 0.0
	if Time.get_ticks_msec() >= int(node.get_meta(DR_AURA_META)):
		return 0.0
	return float(node.get_meta(DR_AURA_AMT_META)) if node.has_meta(DR_AURA_AMT_META) else 0.0
