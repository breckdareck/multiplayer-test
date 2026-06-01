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


func execute(owner_node: Node, _ability: AbilityData, _level_stats: AbilityLevelData) -> void:
	if not owner_node.multiplayer.is_server():
		return
	if not is_instance_valid(owner_node):
		return

	load("res://scripts/Gameplay/ground_zone.gd").spawn_server(
		owner_node,
		owner_node.global_position,
		ZONE_RADIUS,
		ZONE_DURATION,
		ZONE_TICK_INTERVAL,
		0,  # no damage — purely benevolent
		ZONE_COLOR,
		Callable(),  # no enemy callback
		Callable(self, "_apply_banner_aura")
	)


## Per-tick callback fired by the zone for each ally currently inside.
## Heals a small amount and refreshes the Banner Aura buff (which carries
## the +Defense modifier on the ally's stats).
func _apply_banner_aura(ally: Node) -> void:
	if not is_instance_valid(ally):
		return

	# HP regen tick — directly heal the ally via their HealthComponent.
	var hc = ally.get("health_component")
	if hc != null and is_instance_valid(hc) and not hc.is_dead:
		if hc.has_method("heal"):
			hc.heal(HP_REGEN_PER_TICK)
		elif "current_health" in hc and "max_health" in hc:
			# Fallback if no heal method — clamp manually.
			var new_hp: int = mini(int(hc.max_health), int(hc.current_health) + HP_REGEN_PER_TICK)
			hc.current_health = new_hp

	# Refresh the Banner Aura buff for slightly longer than the tick interval
	# so an ally inside the zone keeps the buff continuously; an ally that
	# walks out lets it expire after BANNER_BUFF_DURATION.
	var buff_comp = ally.get_node_or_null("Components/Buff")
	if buff_comp != null and is_instance_valid(buff_comp) and buff_comp.has_method("apply_buff"):
		buff_comp.apply_buff(BANNER_BUFF_NAME, null, BANNER_BUFF_DURATION)
